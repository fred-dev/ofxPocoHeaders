#include "ofApp.h"

#include "Poco/DigestEngine.h"
#include "Poco/DOM/AutoPtr.h"
#include "Poco/DOM/Document.h"
#include "Poco/DOM/DOMParser.h"
#include "Poco/DOM/Element.h"
#include "Poco/JSON/Object.h"
#include "Poco/JSON/Parser.h"
#include "Poco/Net/HTTPRequest.h"
#include "Poco/Net/HTTPResponse.h"
#include "Poco/Net/HTTPSClientSession.h"
#include "Poco/Net/NetworkInterface.h"
#include "Poco/Net/SSLManager.h"
#include "Poco/RegularExpression.h"
#include "Poco/SAX/InputSource.h"
#include "Poco/SHA1Engine.h"
#include "Poco/StreamCopier.h"
#include "Poco/Task.h"
#include "Poco/TaskManager.h"
#include "Poco/URI.h"
#include "Poco/Version.h"

namespace {

class CountTask : public Poco::Task {
public:
	CountTask() : Poco::Task("count") { }
	void runTask() override {
		for (int i = 0; i <= 10 && !isCancelled(); ++i) {
			setProgress(i / 10.f);
		}
	}
};

} // namespace

void ofApp::check(const std::string & name, const std::function<std::string()> & test) {
	std::string line;
	try {
		line = "[ OK ] " + name + ": " + test();
	} catch (const Poco::Exception & e) {
		line = "[FAIL] " + name + ": " + e.displayText();
	} catch (const std::exception & e) {
		line = "[FAIL] " + name + ": " + e.what();
	}
	ofLogNotice("ofxPocoHeaders") << line;
	results.push_back(line);
}

void ofApp::setup() {
	ofSetWindowTitle("ofxPocoHeaders example");

	check("POCO version", [] {
		return ofToHex(POCO_VERSION);
	});

	check("Poco::URI", [] {
		Poco::URI uri("https://tile.openstreetmap.org/3/4/2.png?style=light");
		return uri.getHost() + " " + uri.getPath();
	});

	check("Poco::RegularExpression", [] {
		Poco::RegularExpression re("\\{([a-zA-Z0-9_-]+)\\}");
		std::vector<std::string> groups;
		re.split("https://example.com/{zoom}/{x}/{y}.png", groups);
		return "first template param: " + groups.at(1);
	});

	check("Poco::TaskManager", [] {
		Poco::TaskManager manager;
		manager.start(new CountTask());
		manager.joinAll();
		return std::string("task finished");
	});

	check("Poco::JSON", [] {
		auto object = Poco::JSON::Parser().parse("{\"lat\": -37.81, \"lon\": 144.96}").extract<Poco::JSON::Object::Ptr>();
		return "lat " + ofToString(object->getValue<double>("lat"));
	});

	check("Poco::XML", [] {
		std::istringstream xml("<map><tile/></map>");
		Poco::XML::InputSource source(xml);
		Poco::XML::AutoPtr<Poco::XML::Document> doc = Poco::XML::DOMParser().parse(&source);
		return "root <" + doc->documentElement()->nodeName() + ">";
	});

	check("Poco::SHA1Engine", [] {
		Poco::SHA1Engine sha1;
		sha1.update("abc");
		return Poco::DigestEngine::digestToHex(sha1.digest());
	});

	check("Poco::Net::NetworkInterface", [] {
		return ofToString(Poco::Net::NetworkInterface::list().size()) + " interfaces";
	});

	check("Poco::Net::HTTPSClientSession", [] {
		// Certificate verification needs a CA bundle (see ofxSSLManager);
		// this only checks that TLS works end to end.
		Poco::Net::Context::Ptr context = new Poco::Net::Context(Poco::Net::Context::TLS_CLIENT_USE, "", Poco::Net::Context::VERIFY_NONE);
		Poco::Net::HTTPSClientSession session("example.com", 443, context);
		Poco::Net::HTTPRequest request(Poco::Net::HTTPRequest::HTTP_GET, "/", Poco::Net::HTTPMessage::HTTP_1_1);
		session.sendRequest(request);
		Poco::Net::HTTPResponse response;
		std::string body;
		Poco::StreamCopier::copyToString(session.receiveResponse(response), body);
		return "GET https://example.com/ -> " + ofToString(response.getStatus()) + ", " + ofToString(body.size()) + " bytes";
	});
}

void ofApp::draw() {
	ofBackground(30);
	float y = 30;
	for (const auto & line : results) {
		ofSetColor(line.rfind("[ OK ]", 0) == 0 ? ofColor(120, 220, 120) : ofColor(240, 100, 100));
		ofDrawBitmapString(line, 20, y);
		y += 20;
	}
}
