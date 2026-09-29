#!/usr/bin/env bash
#
# check_addon_branches.sh
#
# Checks that every addon in the ofxPocoHeaders migration is cloned from
# fred-dev's fork and is on the right branch, up to date with GitHub.
#
# Usage:
#   scripts/check_addon_branches.sh [--fix] [--of /path/to/openFrameworks]
#
#   --fix   clone missing addons, fetch, switch to the expected branch and
#           fast-forward it. Never discards local changes: a repo with
#           uncommitted changes or a wrong origin is only reported.
#   --of    openFrameworks root (default: three levels above this script,
#           i.e. the OF that contains addons/ofxPocoHeaders).
#
# Exit status is 0 when everything is as expected, 1 otherwise.

set -u

GITHUB_USER="fred-dev"
MIGRATION_BRANCH="poco_headers_only"

# addon:expected-branch
# ofxGeo and ofxSpatialHash are not forked: they never used POCO.
ADDONS=(
	"ofxPocoHeaders:main"
	"ofxIO:${MIGRATION_BRANCH}"
	"ofxSQLiteCpp:${MIGRATION_BRANCH}"
	"ofxTaskQueue:${MIGRATION_BRANCH}"
	"ofxCache:${MIGRATION_BRANCH}"
	"ofxSSLManager:${MIGRATION_BRANCH}"
	"ofxMediaType:${MIGRATION_BRANCH}"
	"ofxNetworkUtils:${MIGRATION_BRANCH}"
	"ofxHTTP:${MIGRATION_BRANCH}"
	"ofxMaps:${MIGRATION_BRANCH}"
)
UNFORKED=(
	"ofxGeo:https://github.com/bakercp/ofxGeo.git"
	"ofxSpatialHash:https://github.com/bakercp/ofxSpatialHash.git"
)

FIX=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OF_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

while [ $# -gt 0 ]; do
	case "$1" in
		--fix) FIX=1 ;;
		--of) shift; OF_ROOT="$(cd "$1" && pwd)" ;;
		-h|--help) sed -n '2,20p' "$0"; exit 0 ;;
		*) echo "Unknown option: $1" >&2; exit 2 ;;
	esac
	shift
done

ADDONS_DIR="$OF_ROOT/addons"
if [ ! -d "$ADDONS_DIR" ]; then
	echo "No addons folder at $ADDONS_DIR (use --of)" >&2
	exit 2
fi

if [ -t 1 ]; then OK=$'\033[32m'; BAD=$'\033[31m'; WARN=$'\033[33m'; END=$'\033[0m'; else OK=""; BAD=""; WARN=""; END=""; fi
problems=0
report() { # status name message
	case "$1" in
		ok)   printf "  %sOK%s    %-16s %s\n" "$OK" "$END" "$2" "$3" ;;
		warn) printf "  %sWARN%s  %-16s %s\n" "$WARN" "$END" "$2" "$3" ;;
		*)    printf "  %sFAIL%s  %-16s %s\n" "$BAD" "$END" "$2" "$3"; problems=$((problems + 1)) ;;
	esac
}

origin_is_fork() { # url name
	case "$1" in
		"https://github.com/$GITHUB_USER/$2"|"https://github.com/$GITHUB_USER/$2.git"|\
		"git@github.com:$GITHUB_USER/$2"|"git@github.com:$GITHUB_USER/$2.git") return 0 ;;
		*) return 1 ;;
	esac
}

echo "openFrameworks: $OF_ROOT"
echo

for entry in "${ADDONS[@]}"; do
	name="${entry%%:*}"
	branch="${entry#*:}"
	dir="$ADDONS_DIR/$name"
	url="https://github.com/$GITHUB_USER/$name.git"

	if [ ! -d "$dir" ]; then
		if [ $FIX -eq 1 ]; then
			if git clone -q -b "$branch" "$url" "$dir"; then
				report ok "$name" "cloned $url ($branch)"
			else
				report fail "$name" "clone of $url failed"
			fi
		else
			report fail "$name" "missing (git clone -b $branch $url)"
		fi
		continue
	fi

	if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
		report fail "$name" "exists but is not a git repository"
		continue
	fi

	origin="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
	if ! origin_is_fork "$origin" "$name"; then
		report fail "$name" "origin is '$origin', expected $url"
		continue
	fi

	git -C "$dir" fetch -q origin 2>/dev/null || { report fail "$name" "git fetch failed"; continue; }
	if ! git -C "$dir" rev-parse -q --verify "origin/$branch" >/dev/null; then
		report fail "$name" "origin has no branch $branch"
		continue
	fi

	dirty="$(git -C "$dir" status --porcelain --untracked-files=no)"
	current="$(git -C "$dir" rev-parse --abbrev-ref HEAD)"

	if [ "$current" != "$branch" ]; then
		if [ $FIX -eq 1 ] && [ -z "$dirty" ]; then
			git -C "$dir" checkout -q "$branch" 2>/dev/null || git -C "$dir" checkout -q -b "$branch" --track "origin/$branch"
			current="$(git -C "$dir" rev-parse --abbrev-ref HEAD)"
		fi
		if [ "$current" != "$branch" ]; then
			report fail "$name" "on branch '$current', expected $branch${dirty:+ (has uncommitted changes)}"
			continue
		fi
	fi

	behind="$(git -C "$dir" rev-list --count "HEAD..origin/$branch")"
	ahead="$(git -C "$dir" rev-list --count "origin/$branch..HEAD")"
	if [ "$behind" -gt 0 ] && [ "$ahead" -eq 0 ] && [ $FIX -eq 1 ] && [ -z "$dirty" ]; then
		git -C "$dir" merge -q --ff-only "origin/$branch" && behind=0
	fi

	head="$(git -C "$dir" rev-parse --short HEAD)"
	if [ "$behind" -gt 0 ]; then
		report fail "$name" "$branch @ $head is $behind commit(s) behind origin (git pull --ff-only)"
	elif [ -n "$dirty" ]; then
		report warn "$name" "$branch @ $head, up to date, but has uncommitted changes"
	elif [ "$ahead" -gt 0 ]; then
		report warn "$name" "$branch @ $head, $ahead local commit(s) not pushed"
	else
		report ok "$name" "$branch @ $head, up to date"
	fi
done

for entry in "${UNFORKED[@]}"; do
	name="${entry%%:*}"
	url="${entry#*:}"
	dir="$ADDONS_DIR/$name"
	if [ -d "$dir" ]; then
		report ok "$name" "present (not forked, no POCO)"
	elif [ $FIX -eq 1 ] && git clone -q "$url" "$dir"; then
		report ok "$name" "cloned $url"
	else
		report fail "$name" "missing (git clone $url)"
	fi
done

# The old POCO addons must not be used alongside ofxPocoHeaders.
for old in ofxPoco ofxPocoFat; do
	if [ -d "$ADDONS_DIR/$old" ]; then
		report warn "$old" "present; fine as long as no project lists it (it conflicts with ofxPocoHeaders)"
	fi
done

echo
if [ $problems -eq 0 ]; then
	echo "${OK}All addons are on the expected branches.${END}"
	exit 0
fi
echo "${BAD}$problems problem(s).${END} Run with --fix to clone/switch/fast-forward where it is safe."
exit 1
