#include "IOSDeviceAR.h"

#include <Engine.h>

struct SwiftDeviceAR* g_swiftDeviceAR()
{
    static struct SwiftDeviceAR callbacks;
    return &callbacks;
}

bool DeviceAR_qrScanEnabled()
{
    return g_deviceAR().qrScanEnabled();
}

bool DeviceAR_depthWanted()
{
    return g_deviceAR().depthWanted();
}

bool DeviceAR_captureDepthWanted()
{
    return g_deviceAR().captureDepthWanted();
}

void DeviceAR_setCameraFeedWanted(bool wanted)
{
    g_deviceAR().setCameraFeedWanted(wanted);
}

void DeviceAR_setCameraFrameReady(void)
{
    g_deviceAR().setCameraFrameReady();
}

void IOSDeviceAR::initialize(const Variant& config)
{
    DeviceAR::initialize(config); 

    g_swiftDeviceAR()->initialize(&config);
}

void IOSDeviceAR::postInit(const Variant& config)
{
    DeviceAR::postInit(config); 
    g_swiftDeviceAR()->postInit(&config);
}

void IOSDeviceAR::preFrameUpdate(const FrameContext& frameContext)
{
    g_swiftDeviceAR()->preFrameUpdate(&frameContext);
}

void IOSDeviceAR::inFrameUpdate(const FrameContext& frameContext)
{
    g_swiftDeviceAR()->inFrameUpdate(&frameContext);
}

size_t IOSDeviceAR::createMarker(const Marker& marker)
{
    return g_swiftDeviceAR()->createMarker(&marker);
}

void IOSDeviceAR::deleteMarker(size_t id)
{
    g_swiftDeviceAR()->deleteMarker(static_cast<long>(id));
}

size_t IOSDeviceAR::createAnchor(const Transform& transform)
{
    return g_swiftDeviceAR()->createAnchor(&transform);
}

TrackingResult IOSDeviceAR::getAnchorTracking(size_t anchorId)
{
    TrackingResult result;
    g_swiftDeviceAR()->getAnchorTracking(static_cast<long>(anchorId), &result);
    return result;
}

void IOSDeviceAR::deleteAnchor(size_t id)
{
    g_swiftDeviceAR()->deleteAnchor(static_cast<long>(id));
}

void IOSDeviceAR::setQRScanEnabled(bool enabled)
{
    DeviceAR::setQRScanEnabled(enabled);
    g_swiftDeviceAR()->setQRScanEnabled(enabled);
}

bool IOSDeviceAR::cameraFrame(CameraFrame& out)
{
    if (!g_swiftDeviceAR()->cameraFrame) {
        return false;
    }
    SwiftCameraFrame frame{};
    if (!g_swiftDeviceAR()->cameraFrame(&frame) || !frame.data) {
        return false;
    }
    out.image.width = frame.width;
    out.image.height = frame.height;
    out.image.rowStride = frame.rowStride;
    out.image.format = 0;
    out.image.data = frame.data;
    out.fx = frame.fx; out.fy = frame.fy; out.cx = frame.cx; out.cy = frame.cy;
    for (int c = 0; c < 4; ++c) {
        for (int r = 0; r < 4; ++r) {
            out.poseGl[c][r] = frame.pose[c * 4 + r];
        }
    }
    out.timestamp = frame.timestamp;
    out.tracking = frame.tracking;
    if (frame.cbcr && frame.chromaRowStride > 0) {
        out.image.cb = frame.cbcr;
        out.image.cr = static_cast<const uint8_t*>(frame.cbcr) + 1;
        out.image.chromaRowStride = frame.chromaRowStride;
        out.image.chromaPixelStride = 2;
    }
    if (frame.depth && frame.depthWidth > 0 && frame.depthHeight > 0) {
        // The scene depth is the frame's own: its pose and its moment.
        out.depth.data = frame.depth;
        out.depth.width = frame.depthWidth;
        out.depth.height = frame.depthHeight;
        out.depth.rowStride = frame.depthRowStride;
        out.depth.fx = frame.depthFx; out.depth.fy = frame.depthFy; out.depth.cx = frame.depthCx; out.depth.cy = frame.depthCy;
        out.depth.poseGl = out.poseGl;
        out.depth.timestamp = frame.timestamp;
    }
    return true;
}

RaycastResult IOSDeviceAR::raycast(const Ray& ray, uint64_t flags)
{
    RaycastResult result;
    g_swiftDeviceAR()->raycast(ray.origin.x,
                               ray.origin.y,
                               ray.origin.z,
                               ray.direction.x,
                               ray.direction.y,
                               ray.direction.z,
                               flags,
                               &result);
    return result;
}
