#pragma once
#include <Common.h>
#include <quickjspp.hpp>

class JsEnv;
class JsCamera
{
public:
    JsCamera(JsEnv* env);

    qjs::Value position() const;
    qjs::Value rotation() const;
    qjs::Value right() const;
    qjs::Value up() const;
    qjs::Value forward() const;

    static void registerClass(qjs::Context::Module& module) {
        module.class_<JsCamera>("Camera")
        .property<&JsCamera::position>("position")
        .property<&JsCamera::rotation>("rotation")
        .property<&JsCamera::right>("right")
        .property<&JsCamera::up>("up")
        .property<&JsCamera::forward>("forward");
    }

private:
    JsEnv* mEnv{nullptr};
};
