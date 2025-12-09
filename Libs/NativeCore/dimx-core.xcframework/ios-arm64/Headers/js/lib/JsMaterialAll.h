#pragma once
#include <Common.h>
#include "../utils/Utils.h"
#include <quickjspp.hpp>

class JsEnv;
class Object;
class JsObjectMaterials;
class JsMaterialAll
{
public:
    JsMaterialAll(JsEnv* env, JsObjectMaterials* material);

    qjs::Value undefined();
    void setBaseColor(Vec4 jsColor);
    void setBaseColorMap(const std::string& texturePath);
    void setBaseColorWeight(double factor);
    void setAlpha(double factor);
    void setMetalness(double factor);
    void setMetalnessMap(const std::string& texturePath);
    void setRoughness(double factor);
    void setRoughnessMap(const std::string& texturePath);
    void setNormalMap(const std::string& texturePath);
    void setAddColor(Vec4 jsColor);
    void setMultColor(Vec4 jsColor);
    void setReceiveLighting(bool factor);
    void setReceiveShadows(bool factor);

    static void registerClass(qjs::Context::Module& module) {
        module.class_<JsMaterialAll>("JsMaterialAll")
        .property<&JsMaterialAll::undefined, &JsMaterialAll::setBaseColor>("baseColor")
        .property<&JsMaterialAll::undefined, &JsMaterialAll::setBaseColorMap>("baseColorMap")
        .property<&JsMaterialAll::undefined, &JsMaterialAll::setBaseColorWeight>("baseColorWeight")
        .property<&JsMaterialAll::undefined, &JsMaterialAll::setAlpha>("alpha")
        .property<&JsMaterialAll::undefined, &JsMaterialAll::setMetalness>("metalness")
        .property<&JsMaterialAll::undefined, &JsMaterialAll::setMetalnessMap>("metalnessMap")
        .property<&JsMaterialAll::undefined, &JsMaterialAll::setRoughness>("roughness")
        .property<&JsMaterialAll::undefined, &JsMaterialAll::setRoughnessMap>("roughnessMap")
        .property<&JsMaterialAll::undefined, &JsMaterialAll::setNormalMap>("normalMap")
        .property<&JsMaterialAll::undefined, &JsMaterialAll::setAddColor>("addColor")
        .property<&JsMaterialAll::undefined, &JsMaterialAll::setMultColor>("multiplyColor")
        .property<&JsMaterialAll::undefined, &JsMaterialAll::setReceiveLighting>("receiveLighting")
        .property<&JsMaterialAll::undefined, &JsMaterialAll::setReceiveShadows>("receiveShadows");
    }

private:
    JsEnv* mEnv{nullptr};
    JsObjectMaterials* mObjectMaterials{nullptr};
};
