#pragma once
#include <Common.h>
#include "Font.h"
#include <Buffer.h>
#include <config/Config.h>

struct ImFontAtlas;

class ImguiFontContainer {
    using FontSizeVec   = std::vector<std::pair<int, ImFont*>>; // need to store size because ImFont doesn't initialize it immediately
    using FontWeightArray = std::array<FontSizeVec, static_cast<size_t>(FontWeight::Max) + 1>;
    using FontFamilyMap = std::map<std::string, FontWeightArray>;

public:
    void add(const std::string& name, FontWeight weight, int size, ImFont* font);
    ImFont* get(const std::string& name, FontWeight weight, int targetSize, bool highResolution = false);
    void clear() { mFonts.clear();}

private:
    FontFamilyMap mFonts;
};

class CoreFontContainer {
    using FontSizeCache = std::map<int, std::unique_ptr<Font>>;
    using FontWeightCache = std::map<FontWeight, FontSizeCache>;
public:
    const Font* add(const std::string& name, FontWeight weight, int size, bool highResolution, ImFont* imFont);
    const Font* get(const std::string& name, FontWeight weight, int size, bool highResolution) const;
    void clear() { mFonts.clear(); }
private:
    std::map<std::string, FontWeightCache> mFonts;
};

class FontManager
{
    NO_COPY_MOVE(FontManager);

    using FontSizeCache = std::map<int, Font>;
    using FontWeightCache = std::map<FontWeight, FontSizeCache>;

public:
    FontManager() = default;

    void initialize(const Config& config, CounterPtr counter);
    void deinitialize();

    ImFontAtlas* atlas() { return mFontAtlas.get(); }
    const ObjectPtr& texture() { return mTexture; }

    const Font* getFont(const std::string& name = {}, int size = 0, FontWeight weight = FontWeight::Regular, bool highResolution = false);

private:
    void initImguiFonts(const Config& config, std::function<void()> callback);

private:
    std::unique_ptr<ImFontAtlas> mFontAtlas;
    ObjectPtr mTexture;
    ImguiFontContainer mImguiFonts;
    CoreFontContainer mCoreFonts;

    std::string mDefaultFontName;
    int mDefaultFontSize{-1};
};
