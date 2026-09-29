meta:
	ADDON_NAME = ofxPocoHeaders
	ADDON_DESCRIPTION = POCO C++ Libraries compiled from source with your project. Drop-in replacement for ofxPoco: same Poco:: API and include paths, no prebuilt POCO libraries, uses openFrameworks' own OpenSSL and zlib.
	ADDON_AUTHOR = Fred Rodrigues
	ADDON_TAGS = "poco" "network" "http" "ssl"
	ADDON_URL = https://github.com/fred-dev/ofxPocoHeaders

common:
	# Public POCO headers (same layout as ofxPoco) and the addon's own src.
	ADDON_INCLUDES = libs/poco/include
	ADDON_INCLUDES += src

	# libs/poco/source holds POCO's untouched sources. They are compiled only
	# through the generated wrappers in libs/poco/src (see scripts/update_poco.py),
	# so nothing in source/ may be compiled directly or added to include paths.
	ADDON_SOURCES_EXCLUDE = libs/poco/source/%
	ADDON_INCLUDES_EXCLUDE = libs/poco/source/%
	ADDON_INCLUDES_EXCLUDE += libs/poco/src/%

linux64:
	ADDON_PKG_CONFIG_LIBRARIES = openssl

linuxarmv6l:
	ADDON_PKG_CONFIG_LIBRARIES = openssl

linuxarmv7l:
	ADDON_PKG_CONFIG_LIBRARIES = openssl

linuxaarch64:
	ADDON_PKG_CONFIG_LIBRARIES = openssl

msys2:
	ADDON_LDFLAGS = -lssl -lcrypto -liphlpapi -lws2_32 -lcrypt32

vs:
	ADDON_LIBS = iphlpapi.lib
	ADDON_LIBS += ws2_32.lib
	ADDON_LIBS += crypt32.lib

emscripten:
	# No OpenSSL in the browser: drop the TLS and crypto modules.
	ADDON_SOURCES_EXCLUDE += libs/poco/src/NetSSL_OpenSSL/%
	ADDON_SOURCES_EXCLUDE += libs/poco/src/Crypto/%
	ADDON_SOURCES_EXCLUDE += src/ofxPocoOpenSSLSeedFix.cpp
	ADDON_SOURCES_EXCLUDE += src/ofxPocoOpenSSLAlgorithmsFix.cpp
