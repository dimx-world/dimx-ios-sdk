#pragma once
#include <model/ModelBuilder.h>

class Mesh;
class Text2DBuilder: public ModelBuilder
{
public:
    Text2DBuilder(Model& model, const Config& config);

    void serialize(Config& out) override;

    const std::string& text() const { return mText; }
    void setText(const std::string& text, bool rebuild = true);

    float fontSize() const { return mFontSize; }
    void setFontSize(float size, bool rebuild = true);

    float framePadding() const { return mFramePadding; }
    void setFramePadding(float value, bool rebuild = true);

    float frameWidth() const { return mFrameWidth; }
    void setFrameWidth(float value, bool rebuild = true);

    float frameHeight() const { return mFrameHeight; }
    void setFrameHeight(float value, bool rebuild = true);

    float borderSize() const { return mBorderSize; }
    void setBorderSize(float value, bool rebuild = true);

    float cornerRadius() const { return mCornerRadius; }
    void setCornerRadius(float value, bool rebuild = true);

    const Vec4& textColor() const { return mTextColor; }
    void setTextColor(const Vec4& value, bool rebuild = true);

    const Vec4& backgroundColor() const { return mBackgroundColor; }
    void setBackgroundColor(const Vec4& value, bool rebuild = true);

    const Vec4& borderColor() const { return mBorderColor; }
    void setBorderColor(const Vec4& value, bool rebuild = true);

    bool receiveLighting() const { return mReceiveLighting; }
    void setReceiveLighting(bool value, bool rebuild = true);

protected:
    std::shared_ptr<edit::Property> createEditableProperty() override;

private:
    void rebuildNative();
    AABB getFrameAABB(const AABB& textAabb);
    Mesh* buildTextMesh(float posZ);
    void buildFrameMesh(const AABB& aabb, float posZ);
    void buildBorderMesh(const AABB& aabb, float posZ);

private:
    std::string mText;
    float mFontSize{10.f}; // Measured in cm

    float mFramePadding{0.f};
    float mFrameWidth{0.f};
    float mFrameHeight{0.f};
    float mBorderSize{0.f};
    float mCornerRadius{0.f};
    size_t mNumCornerSegments{4};

    Vec4 mTextColor{1.f, 1.f, 1.f, 1.f};
    Vec4 mBackgroundColor{0.f, 0.f, 0.f, 0.f};
    Vec4 mBorderColor{1.f, 1.f, 1.f, 1.f};

    bool mReceiveLighting{false};
};
