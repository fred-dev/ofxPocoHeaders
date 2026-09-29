#!/usr/bin/env bash
#
# test_addons_xcode.sh
#
# For one example of every addon in the ofxPocoHeaders migration:
#   1. copies the example into a fresh folder under apps/ (addon repos are
#      never touched),
#   2. generates an Xcode project with the projectGenerator command line tool,
#      using only the example's addons.make,
#   3. builds it with xcodebuild for this Mac's architecture (arm64 on Apple
#      silicon),
#   4. optionally runs each app for a few seconds and checks its output.
#
# Usage:
#   scripts/test_addons_xcode.sh [options]
#
#   --of PATH       openFrameworks root (default: three levels above this
#                   script, i.e. the OF that contains addons/ofxPocoHeaders)
#   --pg PATH       projectGenerator command line binary (default: first found
#                   of apps/projectGenerator/commandLine/bin/projectGenerator and
#                   projectGenerator/projectGenerator.app/.../app/projectGenerator)
#   --arch ARCH     arm64 or x86_64 (default: this Mac's architecture)
#   --config NAME   Release or Debug (default: Release)
#   --run SECONDS   also launch each app for SECONDS, then quit it and check
#                   its log for errors and crashes (default: don't run)
#   --make          also build each example with the OF makefiles
#   --only NAME     test only the addon NAME (repeatable)
#
# Results are written to apps/pocoHeadersTests_<timestamp>/ (projects and
# logs). Exit status is 0 when everything passes.

set -u

EXAMPLES=(
	"ofxPocoHeaders:example"
	"ofxTaskQueue:example"
	"ofxSSLManager:example"
	"ofxMediaType:example"
	"ofxNetworkUtils:example"
	"ofxIO:examples/compression/example_compression"
	"ofxSQLiteCpp:example"
	"ofxHTTP:example_advanced_client_get"
	"ofxCache:example"
	"ofxMaps:example"
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OF_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PG=""
ARCH="$(uname -m)"
CONFIG="Release"
RUN_SECONDS=0
MAKE=0
ONLY=()

while [ $# -gt 0 ]; do
	case "$1" in
		--of) shift; OF_ROOT="$(cd "$1" && pwd)" ;;
		--pg) shift; PG="$1" ;;
		--arch) shift; ARCH="$1" ;;
		--config) shift; CONFIG="$1" ;;
		--run) shift; RUN_SECONDS="$1" ;;
		--make) MAKE=1 ;;
		--only) shift; ONLY+=("$1") ;;
		-h|--help) sed -n '2,32p' "$0"; exit 0 ;;
		*) echo "Unknown option: $1" >&2; exit 2 ;;
	esac
	shift
done

if [ -z "$PG" ]; then
	for candidate in \
		"$OF_ROOT/apps/projectGenerator/commandLine/bin/projectGenerator" \
		"$OF_ROOT/projectGenerator/projectGenerator.app/Contents/Resources/app/app/projectGenerator" \
		"$OF_ROOT/projectGenerator/projectGenerator"; do
		if [ -x "$candidate" ] && [ -f "$candidate" ]; then PG="$candidate"; break; fi
	done
fi
if [ -z "$PG" ] || [ ! -x "$PG" ]; then
	echo "projectGenerator command line tool not found; pass --pg /path/to/projectGenerator" >&2
	exit 2
fi
command -v xcodebuild >/dev/null || { echo "xcodebuild not found (install Xcode)" >&2; exit 2; }

RUN_DIR="$OF_ROOT/apps/pocoHeadersTests_$(date +%Y%m%d_%H%M%S)"
LOG_DIR="$RUN_DIR/_logs"
mkdir -p "$LOG_DIR"

if [ -t 1 ]; then OK=$'\033[32m'; BAD=$'\033[31m'; END=$'\033[0m'; else OK=""; BAD=""; END=""; fi

echo "openFrameworks:   $OF_ROOT"
echo "projectGenerator: $PG ($("$PG" --version 2>/dev/null | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' | head -1))"
echo "arch/config:      $ARCH / $CONFIG"
echo "output:           $RUN_DIR"
echo

# The projectGenerator writes a template project into the OF root when it
# misreads its arguments; make sure we would notice.
root_untouched() {
	[ ! -e "$OF_ROOT/addons.make" ] && [ ! -e "$OF_ROOT/Makefile" ] && [ ! -e "$OF_ROOT/openFrameworks.xcodeproj" ]
}
if ! root_untouched; then
	echo "${BAD}The OF root already contains a stray project (addons.make / Makefile / openFrameworks.xcodeproj).${END}"
	echo "Remove it before running this script." >&2
	exit 2
fi

wanted() {
	[ ${#ONLY[@]} -eq 0 ] && return 0
	local n; for n in "${ONLY[@]}"; do [ "$n" = "$1" ] && return 0; done
	return 1
}

SUMMARY=()
failures=0

for entry in "${EXAMPLES[@]}"; do
	addon="${entry%%:*}"
	example="${entry#*:}"
	wanted "$addon" || continue

	src="$OF_ROOT/addons/$addon/$example"
	name="${addon}_$(basename "$example")"
	proj="$RUN_DIR/$name"
	status="ok"
	notes=""

	printf "%-40s " "$name"

	if [ ! -f "$src/addons.make" ]; then
		status="FAIL"; notes="example not found at $src"
	else
		# Copy sources, addons.make and data (without any tile/data caches).
		mkdir -p "$proj"
		cp -R "$src/src" "$proj/"
		cp "$src/addons.make" "$proj/"
		if [ -d "$src/bin/data" ]; then
			mkdir -p "$proj/bin"
			rsync -a --exclude cache "$src/bin/data" "$proj/bin/"
		fi

		# 1. projectGenerator. Values must be attached (--ofPath=...), see README.
		if ! (cd "$RUN_DIR" && "$PG" --ofPath="$OF_ROOT" --platforms=osx "$proj") > "$LOG_DIR/$name.pg.log" 2>&1; then
			status="FAIL"; notes="projectGenerator failed"
		elif ! root_untouched; then
			status="FAIL"; notes="projectGenerator wrote a project into the OF root"
		elif [ ! -d "$proj/$name.xcodeproj" ]; then
			status="FAIL"; notes="no Xcode project generated"
		elif ! grep -q "ofxPocoHeaders" "$proj/$name.xcodeproj/project.pbxproj"; then
			status="FAIL"; notes="ofxPocoHeaders not in the generated project"
		fi

		# 2. xcodebuild
		if [ "$status" = "ok" ]; then
			scheme="$(xcodebuild -list -project "$proj/$name.xcodeproj" 2>/dev/null \
				| awk -v c="$CONFIG" '/Schemes:/{f=1;next} f&&index($0,c){gsub(/^ +/,"");print;exit}')"
			start=$(date +%s)
			if (cd "$proj" && xcodebuild -project "$name.xcodeproj" ${scheme:+-scheme "$scheme"} \
					-configuration "$CONFIG" -arch "$ARCH" ONLY_ACTIVE_ARCH=YES build) > "$LOG_DIR/$name.xcode.log" 2>&1; then
				notes="xcode ${ARCH} $(( $(date +%s) - start ))s"
			else
				status="FAIL"
				first_error="$(grep -m1 -E " error: |Undefined symbols|duplicate symbol" "$LOG_DIR/$name.xcode.log" | sed -E 's|.*/(addons|apps)/||' | cut -c1-120)"
				notes="xcodebuild failed: ${first_error:-see log}"
			fi
		fi

		# 3. optional makefile build
		if [ "$status" = "ok" ] && [ $MAKE -eq 1 ]; then
			if (cd "$proj" && make -j"$(sysctl -n hw.ncpu)" "$CONFIG") > "$LOG_DIR/$name.make.log" 2>&1; then
				notes="$notes, make ok"
			else
				status="FAIL"; notes="$notes, make failed (see log)"
			fi
		fi

		# 4. optional run
		if [ "$status" = "ok" ] && [ "$RUN_SECONDS" -gt 0 ]; then
			app="$(find "$proj/bin" -maxdepth 1 -name "*.app" ! -name "*Debug.app" | head -1)"
			[ "$CONFIG" = "Debug" ] && app="$(find "$proj/bin" -maxdepth 1 -name "*Debug.app" | head -1)"
			if [ -z "$app" ]; then
				status="FAIL"; notes="$notes, no .app to run"
			else
				exe="$app/Contents/MacOS/$(basename "$app" .app)"
				"$exe" > "$LOG_DIR/$name.run.log" 2>&1 &
				pid=$!
				sleep "$RUN_SECONDS"
				if ! kill -0 "$pid" 2>/dev/null; then
					status="FAIL"; notes="$notes, app exited/crashed within ${RUN_SECONDS}s"
				else
					# Quit normally so exit-time crashes (static destructors) show up.
					osascript -e "tell application \"$(basename "$app" .app)\" to quit" >/dev/null 2>&1
					for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
					kill -0 "$pid" 2>/dev/null && kill "$pid" 2>/dev/null
					wait "$pid" 2>/dev/null
					if grep -qE "terminating|libc\+\+abi|Assertion failed|\[FAIL\]|\[ ?error ?\]" "$LOG_DIR/$name.run.log"; then
						status="FAIL"; notes="$notes, errors in run log"
					else
						notes="$notes, ran ${RUN_SECONDS}s cleanly"
					fi
				fi
			fi
		fi
	fi

	if [ "$status" = "ok" ]; then
		echo "${OK}PASS${END}  $notes"
	else
		echo "${BAD}FAIL${END}  $notes"
		failures=$((failures + 1))
	fi
	SUMMARY+=("$status  $name  $notes")
done

printf "%s\n" "${SUMMARY[@]}" > "$LOG_DIR/summary.txt"
echo
echo "Logs: $LOG_DIR"
if [ $failures -eq 0 ]; then
	echo "${OK}All examples passed.${END}"
	exit 0
fi
echo "${BAD}$failures example(s) failed.${END}"
exit 1
