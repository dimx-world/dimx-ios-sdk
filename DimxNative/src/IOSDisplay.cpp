#include "IOSDisplay.h"
#include "IOSEngine.h"
#include <Engine.h>

void Display_setSize(long width, long height)
{
    g_engine().display().setSize(width, height);
}

//=======================================================================//

IOSDisplay::IOSDisplay()
{
}

IOSDisplay::~IOSDisplay()
{
}

void IOSDisplay::initialize(const Config& config)
{
    Display::initialize(config);


    // Seeded from UIScreen at initEngine, not from the drawable: the display is
    // initialized long before any AR screen exists to hand the renderer a layer.
    // A layer that ends up a different size reports it through Display_setSize.
    Vec2i size { g_iosEngine().screenWidth(), g_iosEngine().screenHeight() };
    LOGI("IOSDisplay size: " << size.x << " x " << size.y);
    setSize(size.x, size.y);
}

void IOSDisplay::deinitialize()
{
    Display::deinitialize();
}

void IOSDisplay::update(const FrameContext& frameContext)
{
    Display::update(frameContext);
}

void IOSDisplay::endFrame(const FrameContext& frameContext)
{
    Display::endFrame(frameContext);
}
