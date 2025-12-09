#pragma once
#include <Common.h>
#include <quickjspp.hpp>

class JsEnv;
class Animator;
class JsAnimator
{
public:
    JsAnimator(JsEnv* env, Animator* animator);

    const qjs::Value& jsValue() const { return mJsValue; }

    bool getLooped() const;
    void setLooped(bool looped);

    double getSpeed() const;
    void setSpeed(double speed);

    std::vector<std::string> list() const;

    void play(const std::string& anim, qjs::Value options);
    void stop();
    void reset();

    void subscribe(qjs::Value arg1, qjs::Value arg2, qjs::Value arg3);

    static void registerClass(qjs::Context::Module& module) {
        module.class_<JsAnimator>("JsAnimator")
        .property<&JsAnimator::setLooped, &JsAnimator::getLooped>("loop")
        .property<&JsAnimator::setSpeed, &JsAnimator::getSpeed>("speed")
        .fun<&JsAnimator::list>("list")
        .fun<&JsAnimator::play>("play")
        .fun<&JsAnimator::stop>("stop")
        .fun<&JsAnimator::reset>("reset")
        .fun<&JsAnimator::subscribe>("on");
    }

private:
    JsEnv* mEnv{nullptr};
    qjs::Value mJsValue;
    Animator* mAnimator{nullptr};
    std::function<void()> mCallback;
};
