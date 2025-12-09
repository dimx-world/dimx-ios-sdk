#pragma once
#include <Common.h>
#include "../JsFunction.h"
#include <quickjspp.hpp>

class JsEnv;
class Object;
class Node;
class JsObjectPhysics
{
public:
    JsObjectPhysics(JsEnv* env, Node* node);
    
    const qjs::Value& jsValue() const { return mJsValue; }

    double getCollisionRadius() const;
    void setCollisionRadius(double value);

    static void registerClass(qjs::Context::Module& module) {
        module.class_<JsObjectPhysics>("JsObjectPhysics")
        .property<&JsObjectPhysics::getCollisionRadius, &JsObjectPhysics::setCollisionRadius>("collisionRadius");
    }

private:
    JsEnv* mEnv{nullptr};
    Node* mNode{nullptr};
    qjs::Value mJsValue;
};
