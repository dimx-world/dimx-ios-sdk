#pragma once
#include <Common.h>
#include <quickjspp.hpp>

class JsEnv;
class Object;
class ModelBuilder;
class Text2DBuilder;
class JsText
{
public:
    JsText(JsEnv* env, ModelBuilder* builder);

    const qjs::Value& jsValue() const { return mJsValue; }

    const std::string& getText() const;
    void setText(const std::string& text);

    double getFontSize() const;
    void setFontSize(double size);

    double getFramePadding() const;
    void setFramePadding(double value);

    double getFrameWidth() const;
    void setFrameWidth(double value);

    double getFrameHeight() const;
    void setFrameHeight(double value);

    double getBorderSize() const;
    void setBorderSize(double value);

    double getCornerRadius() const;
    void setCornerRadius(double value);

    qjs::Value getTextColor() const;
    void setTextColor(qjs::Value value);

    qjs::Value getBackgroundColor() const;
    void setBackgroundColor(qjs::Value value);

    qjs::Value getBorderColor() const;
    void setBorderColor(qjs::Value value);

    bool getReceiveLighting() const;
    void setReceiveLighting(bool value);

    static void registerClass(qjs::Context::Module& module) {
        module.class_<JsText>("JsText")
        .property<&JsText::getText, &JsText::setText>("text")
        .property<&JsText::getTextColor, &JsText::setTextColor>("color")
        .property<&JsText::getFontSize, &JsText::setFontSize>("fontSize")
        .property<&JsText::getFramePadding, &JsText::setFramePadding>("framePadding")
        .property<&JsText::getFrameWidth, &JsText::setFrameWidth>("frameWidth")
        .property<&JsText::getFrameHeight, &JsText::setFrameHeight>("frameHeight")
        .property<&JsText::getBorderSize, &JsText::setBorderSize>("borderSize")
        .property<&JsText::getCornerRadius, &JsText::setCornerRadius>("cornerRadius")
        .property<&JsText::getBackgroundColor, &JsText::setBackgroundColor>("backgroundColor")
        .property<&JsText::getBorderColor, &JsText::setBorderColor>("borderColor")
        .property<&JsText::getReceiveLighting, &JsText::setReceiveLighting>("receiveLighting");
    }

private:
    JsEnv* mEnv{nullptr};
    Text2DBuilder* mText2DBuilder{nullptr};
    qjs::Value mJsValue;
};
