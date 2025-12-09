#pragma once
#include <Common.h>
#include "TrackObjectComponent.h"
#include <config/Config.h>
#include <quickjspp.hpp>

class JsEnv;

class JsFollowPathObjectComponent: public TrackObjectComponent<Vec3>
{
    MAKE_JS_VALUE(JsFollowPathObjectComponent)
    JS_OBJECT_COMPONENT_BASE_METHODS()

public:
    static constexpr const char* Type = "FollowPath";

public:
    JsFollowPathObjectComponent(ObjectComponentManager* manager, const Config& config);
    bool update(const FrameContext& frameContext) override;

    static void registerClass(qjs::Context::Module& module) {
        auto cls = module.class_<JsFollowPathObjectComponent>("FollowPathObjectComponent");
        registerBaseProperties<JsFollowPathObjectComponent>(module, cls);
    }

private:
    Vec3 mStartPos;
    bool mOrient{true};
    Vec3 mOrientUp{0, 1, 0};
    float mOrientSpeed{1.f};
};
