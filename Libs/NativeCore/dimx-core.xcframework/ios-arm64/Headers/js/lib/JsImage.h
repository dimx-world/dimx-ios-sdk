#pragma once
#include <Common.h>
#include <quickjspp.hpp>

class JsEnv;
class Object;
class ModelBuilder;
class ImageBuilder;
class JsImage
{
public:
    JsImage(JsEnv* env, ModelBuilder* builder);

    const qjs::Value& jsValue() const { return mJsValue; }

    const std::string& getTexture() const;
    void setTexture(const std::string& value);

    const std::string& getOrientation() const;
    void setOrientation(const std::string& value);

    double getWidth() const;
    void setWidth(double value);

    double getHeight() const;
    void setHeight(double value);

    std::vector<double> getSize() const;
    void setSize(double width, double height);

    bool isTransparent() const;
    void setTransparent(bool value);

    bool receiveLighting() const;
    void setReceiveLighting(bool value);

    static void registerClass(qjs::Context::Module& module) {
        module.class_<JsImage>("JsImage")
        .property<&JsImage::getTexture, &JsImage::setTexture>("texture")
        .property<&JsImage::getOrientation, &JsImage::setOrientation>("orientation")
        .property<&JsImage::getWidth, &JsImage::setWidth>("width")
        .property<&JsImage::getHeight, &JsImage::setHeight>("height")
        .property<&JsImage::getSize, &JsImage::setSize>("size")
        .property<&JsImage::isTransparent, &JsImage::setTransparent>("transparent")
        .property<&JsImage::receiveLighting, &JsImage::setReceiveLighting>("receiveLighting");
    }

private:
    JsEnv* mEnv{nullptr};
    ImageBuilder* mImageBuilder{nullptr};
    qjs::Value mJsValue;
};
