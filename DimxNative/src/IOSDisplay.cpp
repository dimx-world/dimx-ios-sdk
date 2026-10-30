#include "IOSDisplay.h"
#include "IOSEngine.h"
#include "render/IOSRenderer.h"
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

void IOSDisplay::initialize(const Variant& config)
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

// The first thing in a frame (Engine::update): wait for the display to have a
// drawable for it, before DeviceAR reads the ARKit frame. The wait is what paces
// the engine loop to the display - CAMetalLayer blocks in nextDrawable once its
// pool is empty - and it used to come at the end of the frame, in the renderer:
// between the frame's camera pose read at its top and the background image read
// at its end, which put the two on different ARKit frames nearly every frame, the
// content trailing the camera feed by a camera frame. Here the ARKit frame is
// read right after the wait, once, and the frame is drawn from that one frame.
void IOSDisplay::beginFrame(const FrameContext& frameContext)
{
    Display::beginFrame(frameContext);
    static_cast<IOSRenderer&>(g_engine().renderer()).acquireDrawable();
}

void IOSDisplay::endFrame(const FrameContext& frameContext)
{
    Display::endFrame(frameContext);
}
