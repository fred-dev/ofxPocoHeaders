//
// ofxPocoHeaders.h
//
// ofxPocoHeaders compiles the POCO C++ Libraries from source as part of your
// project. Include POCO headers exactly as with ofxPoco, e.g.
//
//     #include "Poco/URI.h"
//     #include "Poco/Net/HTTPSClientSession.h"
//
// This header is optional; it only adds a check that the POCO headers being
// used are the ones shipped with this addon.
//

#pragma once

#include "Poco/Foundation.h"

#if !defined(OFX_POCO_HEADERS)
	#error "ofxPocoHeaders: another copy of POCO (probably ofxPoco) is on the include path. Remove ofxPoco from addons.make; ofxPocoHeaders replaces it."
#endif
