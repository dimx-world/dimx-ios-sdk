#pragma once
#include <Common.h>
#include "TrackObjectComponent.h"
#include <config/Config.h>
#include <quickjspp.hpp>

class JsEnv;
class JsRotateObjectComponent: public TrackObjectComponent<float>
{
    MAKE_JS_VALUE(JsRotateObjectComponent)
    JS_OBJECT_COMPONENT_BASE_METHODS()

public:
    static constexpr const char* Type = "Rotator";

public:
    JsRotateObjectComponent(ObjectComponentManager* manager, const Config& config);
    bool update(const FrameContext& frameContext) override;
    
    static void registerClass(qjs::Context::Module& module) {
        auto cls = module.class_<JsRotateObjectComponent>("RotateObjectComponent");
        registerBaseProperties<JsRotateObjectComponent>(module, cls);
    }

private:
    Vec3 mAxis{0, 1, 0};
    Quat mStartRot;
};
