#ifndef IOS_DEVICE_AR_H_INCLUDED
#define IOS_DEVICE_AR_H_INCLUDED

//---------------------------------------------------------------
#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

const unsigned long SWIFT_AR_RAYCAST_FURTHEST_FIRST  = 1 << 0;

// The camera's frame as Swift hands it to the engine (DeviceAR::cameraFrame):
// the luminance plane of ARKit's capturedImage, locked until the next frame,
// that image's intrinsics, the camera's own transform (world from camera, GL
// convention, in the image's sensor orientation), ARKit's timestamp and
// whether tracking is normal. With them the image's chroma plane - Cb and Cr
// interleaved, half the size, full range - and, while a recording asks for it
// (DeviceAR_captureDepthWanted) on a device with LiDAR, the frame's scene depth:
// millimetres along the camera's axis, 0 where unknown or unsure, held until the
// next call, covering the captured image at its own size, with that size's
// intrinsics. Null where there is none.
struct SwiftCameraFrame
{
    const void* data;
    int width;
    int height;
    int rowStride;
    float fx, fy, cx, cy;
    float pose[16];       // column major
    double timestamp;
    bool tracking;
    const void* cbcr;
    int chromaRowStride;
    const unsigned short* depth;
    int depthWidth;
    int depthHeight;
    int depthRowStride;   // bytes
    float depthFx, depthFy, depthCx, depthCy;
};

struct SwiftDeviceAR
{
    void (*initialize)(const void*);
    void (*postInit)(const void*);
    void (*preFrameUpdate)(const void*);
    void (*inFrameUpdate)(const void*);
    long (*createMarker)(const void*);
    void (*deleteMarker)(long);
    long (*createAnchor)(const void*);
    void (*getAnchorTracking)(long, void*);
    void (*deleteAnchor)(long);
    void (*setQRScanEnabled)(bool);
    void (*raycast)(float, float, float, float, float, float, unsigned long, void*);
    bool (*cameraFrame)(struct SwiftCameraFrame*);
};
struct SwiftDeviceAR* g_swiftDeviceAR();

// Swift-side query for the engine's passive-QR-scan gate (DeviceAR::qrScanEnabled()).
bool DeviceAR_qrScanEnabled();
// Whether the engine wants the camera's depth this frame - the user's Depth
// Occlusion setting on a device that supports it (DeviceAR::depthWanted).
bool DeviceAR_depthWanted();
// Whether a recording wants the depth with the frames (DeviceAR::captureDepthWanted):
// a scan of the map, from which the server fuses the place's surface.
bool DeviceAR_captureDepthWanted();
// The camera feed behind the AR screen, for the engine's Live View cover
// (DeviceAR::setCameraFeedWanted, setCameraFrameReady): asked for when the
// screen starts the session, its first frame as ARKit delivers it.
void DeviceAR_setCameraFeedWanted(bool wanted);
void DeviceAR_setCameraFrameReady(void);
#ifdef __cplusplus
} // extern "C"
#endif // __cplusplus
//---------------------------------------------------------------

#ifdef __cplusplus
#include <DeviceAR.h>

class IOSDeviceAR: public DeviceAR
{
public:
    void initialize(const Variant& config) override;
    void postInit(const Variant& config) override;
    void preFrameUpdate(const FrameContext& frameContext) override;
    void inFrameUpdate(const FrameContext& frameContext) override;

    size_t createMarker(const Marker& marker) override;
    void deleteMarker(size_t id) override;
    size_t createAnchor(const Transform& transform) override;
    TrackingResult getAnchorTracking(size_t anchorId) override;
    void deleteAnchor(size_t id) override;

    void setQRScanEnabled(bool enabled) override;

    RaycastResult raycast(const Ray& ray, uint64_t flags = 0) override;

    bool cameraFrame(CameraFrame& out) override;
};
#endif // __cplusplus

#endif // #ifndef IOS_DEVICE_AR_H_INCLUDED
