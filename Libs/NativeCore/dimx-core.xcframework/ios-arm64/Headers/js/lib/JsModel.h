#pragma once
#include <Common.h>
#include <quickjspp.hpp>
#include "JsAnimator.h"

class JsEnv;
class Object;
class ModelNode;
class JsModel
{
public:
    JsModel(JsEnv* env, ModelNode* modelNode);

    const qjs::Value& jsValue() const { return mJsValue; }

    const std::string& getAsset() const;

    qjs::Value getAnimator();

    static void registerClass(qjs::Context::Module& module) {
        module.class_<JsModel>("JsModel")
        .property<&JsModel::getAsset>("asset")
        .property<&JsModel::getAnimator>("animator");
    }

private:
    JsEnv* mEnv{nullptr};
    ModelNode* mModelNode{nullptr};
    qjs::Value mJsValue;
    std::unique_ptr<JsAnimator> mAnimator;
};
