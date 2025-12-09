#pragma once
#include <Common.h>
#include "TrackObjectComponent.h"
#include <config/Config.h>
#include <quickjspp.hpp>

class JsEnv;

class JsScaleObjectComponent: public TrackObjectComponent<float>
{
    MAKE_JS_VALUE(JsScaleObjectComponent)
    JS_OBJECT_COMPONENT_BASE_METHODS()

public:
    static constexpr const char* Type = "Scaler";

public:
    JsScaleObjectComponent(ObjectComponentManager* manager, const Config& config);
    bool update(const FrameContext& frameContext) override;
    
    static void registerClass(qjs::Context::Module& module) {
        auto cls = module.class_<JsScaleObjectComponent>("ScaleObjectComponent");
        registerBaseProperties<JsScaleObjectComponent>(module, cls);
    }
};
