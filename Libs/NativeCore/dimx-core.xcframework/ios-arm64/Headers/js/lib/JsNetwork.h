#pragma once
#include <Common.h>
#include <quickjspp.hpp>

class JsEnv;
class JsDimensionController;
class JsNetwork
{
    using ValueCb = std::function<void(qjs::Value)>;
public:
    JsNetwork(JsDimensionController* controller);

    qjs::Value sendRequest(qjs::Value jsRequest, qjs::Value jsOptions);
    void subscribe(std::string event, qjs::Value arg1, qjs::Value arg2);

    void onRemoteMessage(const Config& msg);

    static void registerClass(qjs::Context::Module& module) {
        module.class_<JsNetwork>("Network")
        .fun<&JsNetwork::sendRequest>("sendRequest")
        .fun<&JsNetwork::subscribe>("on");
    }

private:
    JsDimensionController* mController{nullptr};
    std::map<std::string, std::vector<ValueCb>> mRemoteMessageCb;
};
