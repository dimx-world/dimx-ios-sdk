#pragma once
#include <Common.h>
#include "JsObjectComponent.h"
#include <config/Config.h>
#include <quickjspp.hpp>

class JsEnv;

class JsFaceCameraObjectComponent: public JsObjectComponent
{
    MAKE_JS_VALUE(JsFaceCameraObjectComponent)
    JS_OBJECT_COMPONENT_BASE_METHODS()

public:
    static constexpr const char* Type = "FaceCamera";

public:
    JsFaceCameraObjectComponent(ObjectComponentManager* manager, const Config& config);
    bool update(const FrameContext& frameContext) override;

    static void registerClass(qjs::Context::Module& module) {
        auto cls = module.class_<JsFaceCameraObjectComponent>("FaceCameraObjectComponent");
        registerBaseProperties<JsFaceCameraObjectComponent>(module, cls);
    }

private:
    bool mFixed{false};
};
