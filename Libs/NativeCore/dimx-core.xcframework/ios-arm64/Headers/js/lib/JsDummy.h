#pragma once
#include <Common.h>
#include <quickjspp.hpp>

class JsEnv;
class Object;
class Dummy;
class JsDummy
{
public:
    JsDummy(JsEnv* env, Dummy* dummy);
    
    const qjs::Value& jsValue() const { return mJsValue; }

    bool analytics() const;
    double getSize() const;
    void setSize(double value);

    static void registerClass(qjs::Context::Module& module) {
        module.class_<JsDummy>("JsDummy")
        .property<&JsDummy::analytics>("analytics")
        .property<&JsDummy::getSize, &JsDummy::setSize>("size");
    }

private:
    JsEnv* mEnv{nullptr};
    Dummy* mDummy{nullptr};

    qjs::Value mJsValue;
};
