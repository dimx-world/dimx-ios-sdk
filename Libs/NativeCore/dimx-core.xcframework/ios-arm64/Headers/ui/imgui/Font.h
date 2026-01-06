#pragma once
#include <Common.h>

DECL_ENUM(FontWeight,  Light,   Regular,   Medium,   Bold,   Black)
DECL_ESTR(FontWeight, "Light", "Regular", "Medium", "Bold", "Black")

struct ImFont;
class Font
{
public:
    Font(ImFont* imFont, int size, FontWeight weight = FontWeight::Regular);

    ImFont* imguiFont() const { return mImguiFont; }
    float scale() const { return mScale; }
    int size() const { return mSize; };
    FontWeight weight() const { return mWeight; }
    
private:
    ImFont* mImguiFont{nullptr};
    float mScale{1.f};
    int mSize{0};
    FontWeight mWeight{FontWeight::Regular};
};
