//
// ofxPocoHeadersCheck.cpp
//
// Fails the build with a clear message when ofxPoco (or any other POCO) is
// also in the project. Both addons put "Poco/..." on the include path, so
// whichever comes first wins and the other copy's code would be compiled
// against the wrong headers.
//

#include "ofxPocoHeaders.h"
#include "Poco/Version.h"

#if OFX_POCO_HEADERS_POCO_VERSION != POCO_VERSION
	#error "ofxPocoHeaders: Poco/Version.h does not match the vendored POCO. Remove ofxPoco from addons.make; ofxPocoHeaders replaces it."
#endif
