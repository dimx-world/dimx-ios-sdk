#pragma once
#include <Common.h>
#include "../JsFunction.h"
#include <quickjspp.hpp>

class JsEnv;
class Object;
class Trigger;
class JsTrigger
{
public:
    JsTrigger(JsEnv* env, Trigger* trigger);
    
    const qjs::Value& jsValue() const { return mJsValue; }

    double getRadius() const;
    void setRadius(double value);

    bool getOnce() const;
    void setOnce(bool value);

    JsFunction<void()> getOnEnter() const;
    void setOnEnter(JsFunction<void()> callback);

    JsFunction<void()> getOnExit() const;
    void setOnExit(JsFunction<void()> callback);

    static void registerClass(qjs::Context::Module& module) {
        module.class_<JsTrigger>("JsTrigger")
        .property<&JsTrigger::getRadius, &JsTrigger::setRadius>("radius")
        .property<&JsTrigger::getOnce, &JsTrigger::setOnce>("once")
        .property<&JsTrigger::getOnEnter, &JsTrigger::setOnEnter>("onEnter")
        .property<&JsTrigger::getOnExit, &JsTrigger::setOnExit>("onExit");
    }

private:
    JsEnv* mEnv{nullptr};
    Trigger* mTrigger{nullptr};

    qjs::Value mJsValue;
};
