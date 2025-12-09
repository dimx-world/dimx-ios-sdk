#pragma once
#include <Common.h>
#include "../utils/Utils.h"
#include <quickjspp.hpp>

class JsEnv;
class Object;
class Material;
class JsMaterial
{
public:
    JsMaterial(JsEnv* env, Material* material);

    const std::string& name() const;

    Vec4 getBaseColor();
    void setBaseColor(Vec4 jsColor);

    std::string getBaseColorMap();
    void setBaseColorMap(const std::string& texturePath);

    double getBaseColorWeight();
    void setBaseColorWeight(double factor);

    double getAlpha();
    void setAlpha(double factor);
    
    double getMetalness();
    void setMetalness(double factor);

    std::string getMetalnessMap();
    void setMetalnessMap(const std::string& texturePath);

    double getRoughness();
    void setRoughness(double factor);

    std::string getRoughnessMap();
    void setRoughnessMap(const std::string& texturePath);

    std::string getNormalMap();
    void setNormalMap(const std::string& texturePath);

    Vec4 getAddColor();
    void setAddColor(Vec4 jsColor);

    Vec4 getMultColor();
    void setMultColor(Vec4 jsColor);

    bool getReceiveLighting();
    void setReceiveLighting(bool factor);

    bool getReceiveShadows();
    void setReceiveShadows(bool factor);

    static void registerClass(qjs::Context::Module& module) {
        module.class_<JsMaterial>("JsMaterial")
        .property<&JsMaterial::name>("name")
        .property<&JsMaterial::getBaseColor, &JsMaterial::setBaseColor>("baseColor")
        .property<&JsMaterial::getBaseColorMap, &JsMaterial::setBaseColorMap>("baseColorMap")
        .property<&JsMaterial::getBaseColorWeight, &JsMaterial::setBaseColorWeight>("baseColorWeight")
        .property<&JsMaterial::getAlpha, &JsMaterial::setAlpha>("alpha")
        .property<&JsMaterial::getMetalness, &JsMaterial::setMetalness>("metalness")
        .property<&JsMaterial::getMetalnessMap, &JsMaterial::setMetalnessMap>("metalnessMap")
        .property<&JsMaterial::getRoughness, &JsMaterial::setRoughness>("roughness")
        .property<&JsMaterial::getRoughnessMap, &JsMaterial::setRoughnessMap>("roughnessMap")
        .property<&JsMaterial::getNormalMap, &JsMaterial::setNormalMap>("normalMap")
        .property<&JsMaterial::getAddColor, &JsMaterial::setAddColor>("addColor")
        .property<&JsMaterial::getMultColor, &JsMaterial::setMultColor>("multiplyColor")
        .property<&JsMaterial::getReceiveLighting, &JsMaterial::setReceiveLighting>("receiveLighting")
        .property<&JsMaterial::getReceiveShadows, &JsMaterial::setReceiveShadows>("receiveShadows");
    }

private:
    JsEnv* mEnv{nullptr};
    Material* mMaterial{nullptr};
};
