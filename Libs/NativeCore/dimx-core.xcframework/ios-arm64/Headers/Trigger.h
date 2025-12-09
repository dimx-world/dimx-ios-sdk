#pragma once

#ifndef DIMX_CORE_TRIGGER_H
#define DIMX_CORE_TRIGGER_H

#include <ecs/Component.h>
#include <js/JsFunction.h>

#include <quickjspp.hpp>

class JsEnv;
class Trigger: public Component
{
    DECLARE_COMPONENT(Trigger)

    static constexpr float Margin = 0.5f;
public:
    Trigger(Object* entity, const Config& config);
    ~Trigger() override;
    void initialize(CounterPtr counter) override;
    void serialize(Config& out) override;
    std::shared_ptr<edit::Property> createEditableProperty() override;

    void update(const FrameContext& frameContext);

    float radius() const { return mRadius; }
    void setRadius(float value);
    bool once() const { return mOnce; }
    void setOnce(bool value) { mOnce = value; }

    const JsFunction<void()>& onEnter() const { return mOnEnter; }
    const JsFunction<void()>& onExit() const { return mOnExit; }

    void setOnEnter(JsFunction<void()> callback) { mOnEnter = std::move(callback); }
    void setOnExit(JsFunction<void()> callback) { mOnExit = std::move(callback); }

private:
    JsEnv* mJsEnv{nullptr};
    float mRadius{3.5f};
    float mRadiusEnterSq{9.f};
    float mRadiusExitSq{9.f};
    bool mOnce{false};

    JsFunction<void()> mOnEnter;
    JsFunction<void()> mOnExit;

    bool mUserInside{false};
};

#endif // DIMX_CORE_TRIGGER_H