#include "IOSRenderable.h"
//#include "IOSEngine.h"
#include "IOSRenderer.h"

struct SwiftRenderable* g_swiftRenderable()
{
    static struct SwiftRenderable callbacks;
    return &callbacks;
}

IOSRenderable::IOSRenderable(const Renderable& coreRenderable)
: NativeRenderable(coreRenderable)
{
    mNativeId = g_swiftRenderable()->createRenderable(&coreRenderable);
}

IOSRenderable::~IOSRenderable()
{
    g_swiftRenderable()->deleteRenderable(mNativeId);
}

void IOSRenderable::render(const FrameContext& frameContext)
{
    g_swiftRenderable()->render(mNativeId);
}

void IOSRenderable::setHighlightFactor(float factor)
{
    NativeRenderable::setHighlightFactor(factor);

    g_swiftRenderable()->setHighlightFactor(mNativeId, factor);
}

void IOSRenderable::setOcclusion(bool value)
{
    g_swiftRenderable()->setOcclusion(mNativeId, value);
}
