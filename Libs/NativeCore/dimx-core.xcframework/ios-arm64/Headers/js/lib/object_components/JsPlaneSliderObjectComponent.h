#pragma once
#include <Common.h>
#include "JsObjectComponent.h"
#include <config/Config.h>
#include <quickjspp.hpp>

class JsEnv;

class JsPlaneSliderObjectComponent: public JsObjectComponent
{
    MAKE_JS_VALUE(JsPlaneSliderObjectComponent)
    JS_OBJECT_COMPONENT_BASE_METHODS()
public:
    static constexpr const char* Type = "PlaneSlider";

public:
    JsPlaneSliderObjectComponent(ObjectComponentManager* manager, const Config& config);
    bool update(const FrameContext& frameContext) override;

    static void registerClass(qjs::Context::Module& module) {
        auto cls = module.class_<JsPlaneSliderObjectComponent>("PlaneSliderObjectComponent");
        registerBaseProperties<JsPlaneSliderObjectComponent>(module, cls);
    }

private:
    Vec3 mPlaneOrigin;
    Vec3 mPlaneNormal{0, 1, 0};
    Vec3 mPlaneSize;

    Vec3 mPlaneMin;
    Vec3 mPlaneMax;
};
