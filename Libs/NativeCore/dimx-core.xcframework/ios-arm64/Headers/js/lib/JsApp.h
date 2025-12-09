#pragma once
#include <Common.h>
#include <js/JsFunction.h>
#include <quickjspp.hpp>

class JsEnv;
class JsDimensionController;
class JsApp
{
    using ValueCb = JsFunction<void(qjs::Value)>;
public:
    JsApp(JsDimensionController* controller);

    void openUrl(const std::string& url);
    void showScreen(qjs::Value options);
    qjs::Value send(std::string type, qjs::Value jsMessage, qjs::Value jsOptions); // Send messages to the native app
    void subscribe(std::string event, qjs::Value arg1, qjs::Value arg2);

    void onIntent(const std::string& params);

    static void registerClass(qjs::Context::Module& module) {
        module.class_<JsApp>("App")
        .fun<&JsApp::openUrl>("openUrl")
        .fun<&JsApp::showScreen>("showScreen")
        .fun<&JsApp::send>("send")
        .fun<&JsApp::subscribe>("on");
    }

private:
    JsDimensionController* mController{nullptr};
    std::map<std::string, std::vector<ValueCb>> mIntentCallbacks;
};
