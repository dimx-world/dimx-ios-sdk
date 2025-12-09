#pragma once
#include <Common.h>
#include <quickjspp.hpp>

class JsEnv;
class Object;
class Node;
class JsObjectTransform
{
public:
    JsObjectTransform(JsEnv* env, Node* node);

    qjs::Value jsValue() const { return mJsValue; }

    qjs::Value getWorldTransform() const;
    void setWorldTransform(qjs::Value value);

    qjs::Value getWorldPosition() const;
    void setWorldPosition(qjs::Value value);

    qjs::Value getWorldRotation() const;
    void setWorldRotation(qjs::Value value);

    qjs::Value getWorldScale() const;
    void setWorldScale(qjs::Value value);

    qjs::Value getLocalTransform() const;
    void setLocalTransform(qjs::Value value);

    qjs::Value getLocalPosition() const;
    void setLocalPosition(qjs::Value value);

    qjs::Value getLocalRotation() const;
    void setLocalRotation(qjs::Value value);

    qjs::Value getLocalScale() const;
    void setLocalScale(qjs::Value value);

    qjs::Value localToWorldPosition(qjs::Value jsPosition) const;
    qjs::Value localToWorldDirection(qjs::Value jsDirection) const;
    qjs::Value localToWorldRotation(qjs::Value jsRotation) const;
    qjs::Value localToWorldScale(qjs::Value jsScale) const;

    qjs::Value worldToLocalPosition(qjs::Value jsPosition) const;
    qjs::Value worldToLocalDirection(qjs::Value jsDirection) const;
    qjs::Value worldToLocalRotation(qjs::Value jsRotation) const;
    qjs::Value worldToLocalScale(qjs::Value jsScale) const;

    static void registerClass(qjs::Context::Module& module) {
        module.class_<JsObjectTransform>("JsObjectTransform")
        .property<&JsObjectTransform::getWorldTransform, &JsObjectTransform::setWorldTransform>("world")
        .property<&JsObjectTransform::getWorldPosition, &JsObjectTransform::setWorldPosition>("position")
        .property<&JsObjectTransform::getWorldRotation, &JsObjectTransform::setWorldRotation>("rotation")
        .property<&JsObjectTransform::getWorldScale, &JsObjectTransform::setWorldScale>("scale")
        .property<&JsObjectTransform::getLocalTransform, &JsObjectTransform::setLocalTransform>("local")
        .property<&JsObjectTransform::getLocalPosition, &JsObjectTransform::setLocalPosition>("localPosition")
        .property<&JsObjectTransform::getLocalRotation, &JsObjectTransform::setLocalRotation>("localRotation")
        .property<&JsObjectTransform::getLocalScale, &JsObjectTransform::setLocalScale>("localScale")
        .fun<&JsObjectTransform::localToWorldPosition>("localToWorldPosition")
        .fun<&JsObjectTransform::localToWorldDirection>("localToWorldDirection")
        .fun<&JsObjectTransform::localToWorldRotation>("localToWorldRotation")
        .fun<&JsObjectTransform::localToWorldScale>("localToWorldScale")
        .fun<&JsObjectTransform::worldToLocalPosition>("worldToLocalPosition")
        .fun<&JsObjectTransform::worldToLocalDirection>("worldToLocalDirection")
        .fun<&JsObjectTransform::worldToLocalRotation>("worldToLocalRotation")
        .fun<&JsObjectTransform::worldToLocalScale>("worldToLocalScale");
    }

private:
    JsEnv* mEnv{nullptr};
    Node* mNode{nullptr};
    qjs::Value mJsValue;
};
