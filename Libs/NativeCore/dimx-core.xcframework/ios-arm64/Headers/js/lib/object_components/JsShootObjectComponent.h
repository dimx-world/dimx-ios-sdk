#pragma once
#include <Common.h>
#include "JsObjectComponent.h"
#include <config/Config.h>
#include <quickjspp.hpp>

class JsEnv;

class JsShootObjectComponent: public JsObjectComponent
{
    MAKE_JS_VALUE(JsShootObjectComponent)
    JS_OBJECT_COMPONENT_BASE_METHODS()
public:
    static constexpr const char* Type = "Shooter";

public:
    JsShootObjectComponent(ObjectComponentManager* manager, const Config& config);
    bool update(const FrameContext& frameContext) override;

    static void registerClass(qjs::Context::Module& module) {
        auto cls = module.class_<JsShootObjectComponent>("ShootObjectComponent");
        registerBaseProperties<JsShootObjectComponent>(module, cls);
    }

private:
    float mMaxDistance{10.f};
    float mDistanceTraveled{0};
    float mSpeed{1.f};
    Vec3 mVelocity;
    float mCollisionRadius{0.1f};

    std::function<void(std::string)> mOnHitCb;
};
