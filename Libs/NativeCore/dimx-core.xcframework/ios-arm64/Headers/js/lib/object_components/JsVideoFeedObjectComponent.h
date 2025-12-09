#pragma once
#include <Common.h>
#include "JsObjectComponent.h"
#include <config/Config.h>
#include <LifeWatcher.h>
#include <quickjspp.hpp>

class JsEnv;

class JsVideoFeedObjectComponent: public JsObjectComponent
{
    MAKE_JS_VALUE(JsVideoFeedObjectComponent)
    JS_OBJECT_COMPONENT_BASE_METHODS()
public:
    static constexpr const char* Type = "VideoFeed";

public:
    JsVideoFeedObjectComponent(ObjectComponentManager* manager, const Config& config);
    bool update(const FrameContext& frameContext) override;

    static void registerClass(qjs::Context::Module& module) {
        auto cls = module.class_<JsVideoFeedObjectComponent>("VideoFeedObjectComponent");
        registerBaseProperties<JsVideoFeedObjectComponent>(module, cls);
    }

private:
    void initTexture();
    void setTexture(ObjectPtr tex);

private:
    LifeWatcher mLifeWatcher;
    ObjectPtr mTexture;
};
