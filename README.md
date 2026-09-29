# ofxPocoHeaders

The [POCO C++ Libraries](https://pocoproject.org) for openFrameworks, compiled from source as part of your project.

ofxPocoHeaders is a drop-in replacement for `ofxPoco`:

- **Same API.** `Poco::` classes and `#include "Poco/..."` paths are unchanged, so existing code compiles without edits.
- **No prebuilt POCO libraries.** POCO is compiled with your app, for whatever platform and architecture you are building.
- **Uses openFrameworks' own OpenSSL and zlib.** No second OpenSSL to build, package or link.
- **Includes the networking modules** that recent `ofxPoco` builds dropped: `Net` and `NetSSL_OpenSSL`, along with `Foundation`, `Crypto`, `Util`, `JSON` and `XML`.
- **Includes `ofxXmlPoco`** from `ofxPoco`.

Currently vendored: **POCO 1.15.2**.

## Usage

Replace `ofxPoco` with `ofxPocoHeaders` in your project's `addons.make` (and in the `ADDON_DEPENDENCIES` of any addon that depended on `ofxPoco`), then regenerate the project with the projectGenerator.

```
ofxPocoHeaders
```

Do not use `ofxPoco` and `ofxPocoHeaders` in the same project. Both provide the `Poco::` classes. If both are present, the build stops with an error that says so.

The first build of a project compiles POCO (about 500 files) and takes a few minutes. Later builds are incremental.

## Platforms

| Platform | Status |
|---|---|
| macOS (make) | builds and runs the example (HTTPS included) |
| macOS (Xcode), iOS, tvOS | not yet tested |
| Linux, Windows (VS, MSYS2), Android | not yet tested |
| Emscripten | `Net` only; `NetSSL_OpenSSL` and `Crypto` are excluded because there is no OpenSSL in the browser |

On Apple platforms POCO requires C++20 or newer, which openFrameworks already uses.

## How it works

```
libs/poco/include/Poco/...   public headers of all vendored modules
libs/poco/source/...         POCO's own sources (not compiled directly)
libs/poco/src/...            generated one-line wrappers, the only files compiled
```

POCO's CMake build decides which files to compile per platform, and which sources are only ever `#include`d by others (for example `Mutex_POSIX.cpp`). `scripts/update_poco.py` applies the same rules and generates one small wrapper file per compilation unit, so any build system can compile the result without CMake. Build settings that POCO's CMake would pass as compiler flags live in the generated `Poco/ofxPocoConfig.h`, which `Poco/Config.h` includes. No `ADDON_DEFINES` are needed, and your code always sees the same settings POCO was compiled with.

### Updating POCO

```bash
python3 scripts/update_poco.py --version 1.15.2
```

The script clones the given POCO release and regenerates everything under `libs/poco`. Pass `--source /path/to/poco` to use an existing checkout instead.

## OpenSSL 4.0 workarounds

The OpenSSL 4.0.2 package that openFrameworks currently ships for Apple platforms has two build-configuration problems that break TLS. The addon works around both. Each workaround only compiles when OpenSSL's own headers show the broken configuration, so both disappear once openFrameworks ships a fixed OpenSSL.

| Problem | Symptom | Workaround | Disable with |
|---|---|---|---|
| Built without `OPENSSL_NO_FIPS_JITTER`: OpenSSL asks for a `JITTER` seed source that does not exist | `RAND_bytes()` fails, `SSL_CTX_new()` returns NULL, no TLS at all | `src/ofxPocoOpenSSLSeedFix.cpp` registers a small provider that seeds from the operating system's random number generator, only if no real `JITTER` source exists | `OFX_POCO_NO_OPENSSL_SEED_FIX` |
| Built with `OPENSSL_NO_AUTOALGINIT`: OpenSSL's digest and cipher name tables stay empty | Every certificate chain fails with "CA signature digest algorithm too weak"; `EVP_get_cipherbyname()` lookups fail | `src/ofxPocoOpenSSLAlgorithmsFix.cpp` registers the same digests and ciphers OpenSSL registers itself by default | `OFX_POCO_NO_OPENSSL_ALGORITHMS_FIX` |

## License

- POCO: Boost Software License 1.0, see `libs/poco/LICENSE`. The bundled third-party libraries (PCRE2, utf8proc, Expat, pdjson, wepoll, double-conversion, Tessil ordered-map) keep their own licenses, stated in the headers of their source files in `libs/poco/source/dependencies`.
- `ofxXmlPoco`: from openFrameworks' `ofxPoco`, MIT license.
- Everything else in this addon: MIT, see `LICENSE`.
