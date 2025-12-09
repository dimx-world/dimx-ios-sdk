#pragma once
#include <Common.h>
#include "TrackObjectComponent.h"
#include <config/Config.h>
#include <quickjspp.hpp>

DECL_ENUM(MaterialAgentProperty,  Alpha)
DECL_ESTR(MaterialAgentProperty, "Alpha")

class JsEnv;

class JsMaterialObjectComponent: public TrackObjectComponent<float>
{
    MAKE_JS_VALUE(JsMaterialObjectComponent)
    JS_OBJECT_COMPONENT_BASE_METHODS()

public:
    static constexpr const char* Type = "MaterialAnimator";

public:
    JsMaterialObjectComponent(ObjectComponentManager* manager, const Config& config);
    bool update(const FrameContext& frameContext) override;


    static void registerClass(qjs::Context::Module& module) {
        auto cls = module.class_<JsMaterialObjectComponent>("MaterialObjectComponent");
        registerBaseProperties<JsMaterialObjectComponent>(module, cls);
    }

private:
    void applyToObject(Object& obj);

private:
    MaterialAgentProperty mProperty{MaterialAgentProperty::None};
    bool mRecursive{false};
};
