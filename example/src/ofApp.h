#pragma once

#include "ofMain.h"
#include "ofxPocoHeaders.h"

class ofApp : public ofBaseApp {
public:
	void setup() override;
	void draw() override;

private:
	void check(const std::string & name, const std::function<std::string()> & test);

	std::vector<std::string> results;
};
