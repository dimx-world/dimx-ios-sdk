#pragma once
#include <Common.h>
#include <object_ecs/ObjectComponent.h>
#include <js/JsEnv.h>
#include <js/JsFunction.h>
#include <quickjspp.hpp>

#define MAKE_JS_VALUE(ConcreteClassName)                                                \
public:                                                                                 \
    qjs::Value jsValue() override {                                                     \
        return qjs::Value{jsEnv()->jsContext(), static_cast<ConcreteClassName*>(this)}; \
    }

#define JS_OBJECT_COMPONENT_BASE_METHODS()                                                \
    std::string jsName() const { return JsObjectComponent::jsName(); }                    \
    void remove() { JsObjectComponent::remove(); }

class JsObjectComponent : public ObjectComponent
{
public:
    JsObjectComponent(ObjectComponentManager* manager, const Config& config);

    virtual qjs::Value jsValue() = 0;
    void onEnd() override;
    void postUpdate(const FrameContext& frameContext) override;

    JsEnv* jsEnv() const { return mJsEnv; }

    // Common JavaScript interface
    std::string jsName() const { return ObjectComponent::name(); }
    void remove();

    // Helper to register common base properties for any derived class
    template<typename T, typename ClassRegistrar>
    static void registerBaseProperties(qjs::Context::Module& module, ClassRegistrar& registrar) {
        registrar.template property<&T::jsName>("name")
                 .template fun<&T::remove>("remove");
    }
/*
    void onBegin() {
        safeJsCall(mOnBeginCb);
    }

    void onEnd() {
        safeJsCall(mOnEndCb);
    }
*/
    template <typename Call, typename... Args>
    void safeJsCall(Call call, Args&&... args) {
        if (call) {
            mJsEnv->safeCall(call, std::forward<decltype(args)>(args)...);
        }
    }

private:
    JsEnv* mJsEnv{nullptr};
    //std::function<void()> mOnBeginCb;
    JsFunction<void()> mOnEndCb;
    JsFunction<void()> mOnUpdateCb;
};
