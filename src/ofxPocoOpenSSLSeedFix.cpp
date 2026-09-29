//
// ofxPocoOpenSSLSeedFix.cpp
//
// TEMPORARY workaround for the OpenSSL 4.0.x package shipped with
// openFrameworks (apothecary, built with danoli3/openssl-cmake 4.0).
//
// That build defines OPENSSL_NO_JITTER but not OPENSSL_NO_FIPS_JITTER. In
// OpenSSL >= 3.5, rand_new_seed() (crypto/rand/rand_lib.c) then always fetches
// a seed source named "JITTER", which does not exist, so the primary DRBG can
// never be created: RAND_bytes() fails and SSL_CTX_new() returns NULL. Every
// TLS connection made through OF's OpenSSL fails, including POCO NetSSL.
//
// This file registers a tiny built-in provider that implements a "JITTER"
// seed source on top of the operating system's CSPRNG (the same thing
// OpenSSL's own SEED-SRC does). It only activates when:
//   - the OpenSSL headers show the broken configuration (compile time), and
//   - no real "JITTER" implementation can be fetched (run time).
// Once OF ships an OpenSSL built with OPENSSL_NO_FIPS_JITTER this file
// compiles to nothing and can be deleted.
//

#include <openssl/opensslv.h>
#include <openssl/opensslconf.h>

#if defined(OPENSSL_VERSION_NUMBER) && OPENSSL_VERSION_NUMBER >= 0x30500000L \
	&& defined(OPENSSL_NO_JITTER) && !defined(OPENSSL_NO_FIPS_JITTER) \
	&& !defined(OFX_POCO_NO_OPENSSL_SEED_FIX)

#include <openssl/core_dispatch.h>
#include <openssl/core_names.h>
#include <openssl/crypto.h>
#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/params.h>
#include <openssl/provider.h>

#include <cstdlib>
#include <cstring>

#if defined(_WIN32)
	#include <windows.h>
	#include <bcrypt.h>
	#pragma comment(lib, "bcrypt.lib")
#elif defined(__APPLE__) || defined(__ANDROID__) || defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__NetBSD__)
	// arc4random_buf is declared in <stdlib.h> and never fails.
#elif defined(__linux__)
	#include <sys/random.h>
	#include <cerrno>
#else
	#include <unistd.h>
#endif

namespace {

bool osRandom(unsigned char * out, size_t len) {
#if defined(_WIN32)
	return BCRYPT_SUCCESS(BCryptGenRandom(nullptr, out, static_cast<ULONG>(len), BCRYPT_USE_SYSTEM_PREFERRED_RNG));
#elif defined(__APPLE__) || defined(__ANDROID__) || defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__NetBSD__)
	arc4random_buf(out, len);
	return true;
#elif defined(__linux__)
	while (len > 0) {
		ssize_t n = getrandom(out, len, 0);
		if (n < 0) {
			if (errno == EINTR) continue;
			return false;
		}
		out += n;
		len -= static_cast<size_t>(n);
	}
	return true;
#else
	while (len > 0) {
		size_t chunk = len < 256 ? len : 256; // getentropy() limit
		if (getentropy(out, chunk) != 0) return false;
		out += chunk;
		len -= chunk;
	}
	return true;
#endif
}

// Seed source context; mirrors OpenSSL's providers/implementations/rands/seed_src.c.
struct SeedCtx {
	int state = EVP_RAND_STATE_UNINITIALISED;
};

void * seedNew(void *, void * parent, const OSSL_DISPATCH *) {
	if (parent != nullptr) return nullptr; // seed sources have no parent
	return new SeedCtx();
}

void seedFree(void * vctx) {
	delete static_cast<SeedCtx *>(vctx);
}

int seedInstantiate(void * vctx, unsigned int, int, const unsigned char *, size_t, const OSSL_PARAM[]) {
	static_cast<SeedCtx *>(vctx)->state = EVP_RAND_STATE_READY;
	return 1;
}

int seedUninstantiate(void * vctx) {
	static_cast<SeedCtx *>(vctx)->state = EVP_RAND_STATE_UNINITIALISED;
	return 1;
}

int seedGenerate(void * vctx, unsigned char * out, size_t outlen, unsigned int, int, const unsigned char *, size_t) {
	if (static_cast<SeedCtx *>(vctx)->state != EVP_RAND_STATE_READY) return 0;
	return osRandom(out, outlen) ? 1 : 0;
}

int seedReseed(void * vctx, int, const unsigned char *, size_t, const unsigned char *, size_t) {
	return static_cast<SeedCtx *>(vctx)->state == EVP_RAND_STATE_READY ? 1 : 0;
}

size_t seedGetSeed(void *, unsigned char ** pout, int, size_t minLen, size_t, int, const unsigned char *, size_t) {
	unsigned char * buf = static_cast<unsigned char *>(OPENSSL_secure_malloc(minLen));
	if (buf == nullptr) return 0;
	if (!osRandom(buf, minLen)) {
		OPENSSL_secure_clear_free(buf, minLen);
		return 0;
	}
	*pout = buf;
	return minLen;
}

void seedClearSeed(void *, unsigned char * out, size_t outlen) {
	OPENSSL_secure_clear_free(out, outlen);
}

int seedGetCtxParams(void * vctx, OSSL_PARAM params[]) {
	OSSL_PARAM * p;
	if ((p = OSSL_PARAM_locate(params, OSSL_RAND_PARAM_STATE)) != nullptr
		&& !OSSL_PARAM_set_int(p, static_cast<SeedCtx *>(vctx)->state)) return 0;
	if ((p = OSSL_PARAM_locate(params, OSSL_RAND_PARAM_STRENGTH)) != nullptr
		&& !OSSL_PARAM_set_uint(p, 1024)) return 0;
	if ((p = OSSL_PARAM_locate(params, OSSL_RAND_PARAM_MAX_REQUEST)) != nullptr
		&& !OSSL_PARAM_set_size_t(p, 128)) return 0;
	return 1;
}

const OSSL_PARAM * seedGettableCtxParams(void *, void *) {
	static const OSSL_PARAM params[] = {
		OSSL_PARAM_int(OSSL_RAND_PARAM_STATE, nullptr),
		OSSL_PARAM_uint(OSSL_RAND_PARAM_STRENGTH, nullptr),
		OSSL_PARAM_size_t(OSSL_RAND_PARAM_MAX_REQUEST, nullptr),
		OSSL_PARAM_END
	};
	return params;
}

int seedOne(void *) { return 1; }
void seedUnlock(void *) { }

using Fn = void (*)(void);

const OSSL_DISPATCH seedFunctions[] = {
	{ OSSL_FUNC_RAND_NEWCTX, reinterpret_cast<Fn>(seedNew) },
	{ OSSL_FUNC_RAND_FREECTX, reinterpret_cast<Fn>(seedFree) },
	{ OSSL_FUNC_RAND_INSTANTIATE, reinterpret_cast<Fn>(seedInstantiate) },
	{ OSSL_FUNC_RAND_UNINSTANTIATE, reinterpret_cast<Fn>(seedUninstantiate) },
	{ OSSL_FUNC_RAND_GENERATE, reinterpret_cast<Fn>(seedGenerate) },
	{ OSSL_FUNC_RAND_RESEED, reinterpret_cast<Fn>(seedReseed) },
	{ OSSL_FUNC_RAND_ENABLE_LOCKING, reinterpret_cast<Fn>(seedOne) },
	{ OSSL_FUNC_RAND_LOCK, reinterpret_cast<Fn>(seedOne) },
	{ OSSL_FUNC_RAND_UNLOCK, reinterpret_cast<Fn>(seedUnlock) },
	{ OSSL_FUNC_RAND_GETTABLE_CTX_PARAMS, reinterpret_cast<Fn>(seedGettableCtxParams) },
	{ OSSL_FUNC_RAND_GET_CTX_PARAMS, reinterpret_cast<Fn>(seedGetCtxParams) },
	{ OSSL_FUNC_RAND_VERIFY_ZEROIZATION, reinterpret_cast<Fn>(seedOne) },
	{ OSSL_FUNC_RAND_GET_SEED, reinterpret_cast<Fn>(seedGetSeed) },
	{ OSSL_FUNC_RAND_CLEAR_SEED, reinterpret_cast<Fn>(seedClearSeed) },
	OSSL_DISPATCH_END
};

const OSSL_ALGORITHM seedAlgorithms[] = {
	{ "JITTER", "provider=ofxpoco-seed", seedFunctions, "OS entropy seed source (ofxPocoHeaders workaround)" },
	{ nullptr, nullptr, nullptr, nullptr }
};

const OSSL_ALGORITHM * providerQuery(void *, int operationId, int * noCache) {
	*noCache = 0;
	return operationId == OSSL_OP_RAND ? seedAlgorithms : nullptr;
}

const OSSL_DISPATCH providerFunctions[] = {
	{ OSSL_FUNC_PROVIDER_QUERY_OPERATION, reinterpret_cast<Fn>(providerQuery) },
	OSSL_DISPATCH_END
};

int providerInit(const OSSL_CORE_HANDLE *, const OSSL_DISPATCH *, const OSSL_DISPATCH ** out, void ** provctx) {
	*out = providerFunctions;
	*provctx = const_cast<OSSL_DISPATCH *>(providerFunctions); // any non-null value
	return 1;
}

struct InstallSeedFix {
	InstallSeedFix() {
		// Leave builds that really have a JITTER source alone.
		ERR_set_mark();
		EVP_RAND * jitter = EVP_RAND_fetch(nullptr, "JITTER", nullptr);
		ERR_pop_to_mark();
		if (jitter != nullptr) {
			EVP_RAND_free(jitter);
			return;
		}
		// retain_fallbacks = 1 keeps OpenSSL's automatic loading of the
		// default provider, which an explicit load would otherwise disable.
		if (OSSL_PROVIDER_add_builtin(nullptr, "ofxpoco-seed", providerInit)) {
			OSSL_PROVIDER_try_load(nullptr, "ofxpoco-seed", 1);
		}
	}
};

// Runs before main(), so the fix is in place before anything uses OpenSSL.
const InstallSeedFix installSeedFix;

} // namespace

#endif
