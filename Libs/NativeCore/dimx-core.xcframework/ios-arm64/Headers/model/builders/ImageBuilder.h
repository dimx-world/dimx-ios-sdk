#pragma once
#include "PlaneBuilder.h"

DECL_ENUM(ImageOrientation,  Vertical,   Horizontal)
DECL_ESTR(ImageOrientation, "Vertical", "Horizontal")

class ImageBuilder: public PlaneBuilder
{
public:
    ImageBuilder(Model& model, const Config& config);

    void serialize(Config& out) override;

    ImageOrientation orientation() const { return mOrientation; }
    void setOrientation(ImageOrientation orientation, bool rebuild = true);

    const std::string& texture() const { return mTexture; }
    void setTexture(const std::string& texture, bool rebuild = true);

    bool transparent() const { return mTransparent; }
    void setTransparent(bool transparent, bool rebuild = true);

    bool receiveLighting() const { return mReceiveLighting; }
    void setReceiveLighting(bool receiveLighting, bool rebuild = true);

protected:
    std::shared_ptr<edit::Property> createEditableProperty() override;

private:
    ImageOrientation mOrientation{ImageOrientation::Vertical};
    std::string mTexture;
    bool mTransparent{false};
    bool mReceiveLighting{true};
};
