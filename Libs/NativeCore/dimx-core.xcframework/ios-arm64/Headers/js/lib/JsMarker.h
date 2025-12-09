#pragma once
#include <Common.h>
#include "../JsFunction.h"
#include <quickjspp.hpp>

class JsEnv;
class Object;
class Marker;
class JsMarker
{
public:
    JsMarker(JsEnv* env, Marker* marker);
    
    const qjs::Value& jsValue() const { return mJsValue; }

    const std::string& image() const;
    double width() const;
    double height() const;

    static void registerClass(qjs::Context::Module& module) {
        module.class_<JsMarker>("JsMarker")
        .property<&JsMarker::image, nullptr>("image")
        .property<&JsMarker::width, nullptr>("width")
        .property<&JsMarker::height, nullptr>("height");
    }

private:
    JsEnv* mEnv{nullptr};
    Marker* mMarker{nullptr};
    qjs::Value mJsValue;
};
