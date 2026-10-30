import Foundation
import ARKit
import DimxNative

var g_colors: [simd_float4] = [
    simd_float4(0.0, 0.0, 1.0, 1),
    simd_float4(0.0, 1.0, 0.0, 1),
    simd_float4(0.0, 1.0, 1.0, 1),
    simd_float4(1.0, 0.0, 0.0, 1),
    simd_float4(1.0, 0.0, 1.0, 1),
    simd_float4(1.0, 1.0, 0.0, 1),
    simd_float4(0.0, 0.0, 0.5, 1),
    simd_float4(0.0, 0.5, 0.0, 1),
    simd_float4(0.0, 0.5, 0.5, 1),
    simd_float4(0.5, 0.0, 0.0, 1),
    simd_float4(0.5, 0.0, 0.5, 1),
    simd_float4(0.5, 0.5, 0.0, 1)
]

class AnchorInfo {
    var image: ARReferenceImage?
    var imageAnchor: ARImageAnchor?
    var anchor: ARAnchor?
    var isTracked = false
    var transform = simd_float4x4()
    var width: Float =  1.0
    var height: Float = 1.0
}

class PlaneInfo {
    var anchor : ARPlaneAnchor?
    var color = simd_float4(1, 1, 1, 1)
}

class DeviceAR: NSObject, ARSessionDelegate
{
    static /*private*/ let instance = DeviceAR()
    override private init() {}
    
    private let session = ARSession()
    private let configuration = ARWorldTrackingConfiguration()
    private let qrScanner = QRScanner()

    // The engine no longer runs on the main thread, so everything shared with it
    // needs a lock: frames and anchor updates arrive on ARKit's delegate queue
    // (the main queue), while the engine thread reads them every frame and
    // creates and deletes anchors from its own event handlers.
    private let mSessionLock = NSLock()
    // Whether this session's first frame has been reported to the engine, for the
    // Live View cover; under mSessionLock, set from the ARKit delegate thread.
    private var mFirstFrameReported = false

    private var mCurrentFrame: ARFrame?
    // The ARKit frame this engine frame is built on: taken off mCurrentFrame once, in
    // preFrameUpdate, and what every reader on the engine thread uses until the next -
    // the camera pose, the background image, the depth, the recorders' image, the
    // debug drawing. Reading mCurrentFrame twice in a frame gave the content one
    // frame's pose and the background the next frame's image whenever ARKit
    // delivered in between - which, with the renderer's drawable wait sitting
    // between the two reads, was nearly every frame: the content trailed the camera
    // feed by a camera frame (2026-10-30). Engine thread only.
    private var mFrameInUse: ARFrame?
    private var anchors = [AnchorInfo?]()
    // The frame whose capturedImage plane is locked for the engine (cameraFrame): the
    // engine thread's alone, unlocked there at the next frame or the next preFrameUpdate.
    // The pause - main thread - leaves it be: unlocking it there raced the engine thread's
    // own unlock (a pixel buffer unlocked twice, the frame released once too often) and could
    // land while the engine still read the plane. A paused session holds that one frame until
    // frames come again.
    private var mLockedFrame: ARFrame?

    private var mCameraMinZ: Float = 0.0
    private var mCameraMaxZ: Float = 0.0

    // Occlusion by the real world, while the user's Depth Occlusion setting is on
    // (DeviceAR_depthWanted): ARKit's smoothed scene depth on a device with
    // LiDAR - the room occludes, as ARCore's depth does on Android - and people
    // segmentation with depth on the other A12-and-later devices - people do.
    // The renderer takes whichever the frames carry (Renderer.updateDepthOcclusion).
    private static let depthSemantics: ARConfiguration.FrameSemantics? = {
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            return .smoothedSceneDepth
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            return .personSegmentationWithDepth
        }
        return nil
    }()
    // The scene depth a recording keeps (DeviceAR_captureDepthWanted): LiDAR's own, frame by
    // frame - the fusion on the server does the averaging the smoothed depth would.
    private static let captureDepthSupported = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    // Engine thread: the depth semantics last asked of the session.
    private var mDepthRequested: ARConfiguration.FrameSemantics = []
    private var mOcclusionRefusalLogged = false
    private var mCaptureDepthRefusalLogged = false
    // Engine thread: the frame's scene depth in millimetres for a recording (cameraFrame), held
    // until the next call, and the frame it was converted for.
    private var mDepthMm: UnsafeMutablePointer<UInt16>?
    private var mDepthMmCount = 0
    private var mDepthMmTimestamp: TimeInterval = -1
    // Main thread: whether an AR screen is running the session, and whether ARKit
    // refused the depth semantics in this configuration.
    private var mSessionRunning = false
    private var mDepthRefused = false

    static func initCallbacks() {
        g_swiftDeviceAR().pointee.initialize = {
            (configPtr: Optional<UnsafeRawPointer>) -> () in
            DeviceAR.instance.initialize(configPtr: configPtr!)
        }
        g_swiftDeviceAR().pointee.postInit = {
            (configPtr: Optional<UnsafeRawPointer>) -> () in
            DeviceAR.instance.postInit(configPtr: configPtr!)
        }
        g_swiftDeviceAR().pointee.preFrameUpdate = {
            (frameContextPtr: Optional<UnsafeRawPointer>) -> () in
            DeviceAR.instance.preFrameUpdate(frameContextPtr: frameContextPtr!)
        }
        g_swiftDeviceAR().pointee.inFrameUpdate = {
            (frameContextPtr: Optional<UnsafeRawPointer>) -> () in
            DeviceAR.instance.inFrameUpdate(frameContextPtr: frameContextPtr!)
        }
        g_swiftDeviceAR().pointee.createMarker = {
            (markerPtr: Optional<UnsafeRawPointer>) -> Int in
            DeviceAR.instance.createMarker(markerPtr: markerPtr!)
        }
        g_swiftDeviceAR().pointee.deleteMarker = {
            (id: Int) -> () in
             DeviceAR.instance.deleteMarker(id: id)
        }
        g_swiftDeviceAR().pointee.createAnchor = {
            (transformPtr: Optional<UnsafeRawPointer>) -> Int in
            DeviceAR.instance.createAnchor(transformPtr!)
        }
        g_swiftDeviceAR().pointee.getAnchorTracking = {
            (id: Int, outPtr: Optional<UnsafeMutableRawPointer>) -> () in
            DeviceAR.instance.getAnchorTracking(id, outPtr!)
        }
        g_swiftDeviceAR().pointee.deleteAnchor = {
            (id: Int) -> () in
             DeviceAR.instance.deleteAnchor(id)
        }
        g_swiftDeviceAR().pointee.setQRScanEnabled = {
            (enabled: Bool) -> () in
            DeviceAR.instance.qrScanner.setEnabled(enabled)
        }
        g_swiftDeviceAR().pointee.raycast = {
            (origX: Float, origY: Float, origZ: Float, dirX: Float, dirY: Float, dirZ: Float, flags: UInt, outPtr: Optional<UnsafeMutableRawPointer>) -> () in
            DeviceAR.instance.raycast(simd_float3(origX, origY, origZ), simd_float3(dirX, dirY, dirZ), flags, outPtr!)
        }
        g_swiftDeviceAR().pointee.cameraFrame = {
            (outPtr: Optional<UnsafeMutablePointer<SwiftCameraFrame>>) -> Bool in
            DeviceAR.instance.cameraFrame(outPtr!)
        }
    }

    // Engine thread. The frame in use's luminance plane, its intrinsics and the
    // camera's own transform, for the scan tracker and the capture recorder - the
    // image the frame is drawn with, posed as its content is. The pixel buffer
    // stays locked - and the frame retained - until a preFrameUpdate takes another
    // frame, which is as long as the engine reads it.
    func cameraFrame(_ outPtr: UnsafeMutablePointer<SwiftCameraFrame>) -> Bool {
        guard let frame = mFrameInUse else { return false }
        let pixel = frame.capturedImage
        if CVPixelBufferGetPlaneCount(pixel) < 1 {
            return false
        }
        // Locked once per frame: a second reader in the same engine frame - the
        // recorder after the tracker - finds the plane locked and reads the same bytes.
        if mLockedFrame !== frame {
            unlockHeldFrame()
            CVPixelBufferLockBaseAddress(pixel, .readOnly)
            mLockedFrame = frame
        }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixel, 0) else {
            unlockHeldFrame()
            return false
        }
        outPtr.pointee.data = UnsafeRawPointer(base)
        outPtr.pointee.width = Int32(CVPixelBufferGetWidthOfPlane(pixel, 0))
        outPtr.pointee.height = Int32(CVPixelBufferGetHeightOfPlane(pixel, 0))
        outPtr.pointee.rowStride = Int32(CVPixelBufferGetBytesPerRowOfPlane(pixel, 0))
        // The intrinsics of the captured image at its own resolution; simd is
        // column major, so the principal point sits in the third column.
        let K = frame.camera.intrinsics
        outPtr.pointee.fx = K[0][0]
        outPtr.pointee.fy = K[1][1]
        outPtr.pointee.cx = K[2][0]
        outPtr.pointee.cy = K[2][1]
        // The chroma plane, Cb and Cr interleaved at half the size: a recording in colour.
        if CVPixelBufferGetPlaneCount(pixel) >= 2, let chroma = CVPixelBufferGetBaseAddressOfPlane(pixel, 1) {
            outPtr.pointee.cbcr = UnsafeRawPointer(chroma)
            outPtr.pointee.chromaRowStride = Int32(CVPixelBufferGetBytesPerRowOfPlane(pixel, 1))
        } else {
            outPtr.pointee.cbcr = nil
            outPtr.pointee.chromaRowStride = 0
        }
        // The scene depth while a recording asks: it covers the captured image, so the image's
        // intrinsics scaled to its size are its own.
        outPtr.pointee.depth = nil
        if DeviceAR_captureDepthWanted(), let depth = depthMillimetres(frame) {
            let (mm, dw, dh) = depth
            let imageWidth = Float(CVPixelBufferGetWidthOfPlane(pixel, 0))
            let imageHeight = Float(CVPixelBufferGetHeightOfPlane(pixel, 0))
            let sx = Float(dw) / imageWidth, sy = Float(dh) / imageHeight
            outPtr.pointee.depth = mm
            outPtr.pointee.depthWidth = Int32(dw)
            outPtr.pointee.depthHeight = Int32(dh)
            outPtr.pointee.depthRowStride = Int32(dw * 2)
            outPtr.pointee.depthFx = K[0][0] * sx
            outPtr.pointee.depthFy = K[1][1] * sy
            outPtr.pointee.depthCx = K[2][0] * sx
            outPtr.pointee.depthCy = K[2][1] * sy
        }
        let m = frame.camera.transform
        withUnsafeMutablePointer(to: &outPtr.pointee.pose) { tuple in
            tuple.withMemoryRebound(to: Float.self, capacity: 16) { p in
                for c in 0..<4 {
                    for r in 0..<4 {
                        p[c * 4 + r] = m[c][r]
                    }
                }
            }
        }
        outPtr.pointee.timestamp = frame.timestamp
        if case .normal = frame.camera.trackingState {
            outPtr.pointee.tracking = true
        } else {
            outPtr.pointee.tracking = false
        }
        return true
    }

    // Engine thread only (cameraFrame, preFrameUpdate).
    private func unlockHeldFrame() {
        if let held = mLockedFrame {
            CVPixelBufferUnlockBaseAddress(held.capturedImage, .readOnly)
            mLockedFrame = nil
        }
    }

    func initialize(configPtr: UnsafeRawPointer) {
        Logger.info("DeviceAR initalize")
        mCameraMinZ = Variant_getFloat(getEngineConfig(), "camera.minz")
        mCameraMaxZ = Variant_getFloat(getEngineConfig(), "camera.maxz")
        
        configuration.maximumNumberOfTrackedImages = 10
        if Settings_iosPlaneDetection() {
            configuration.planeDetection = [.horizontal, .vertical]
        }
        configuration.automaticImageScaleEstimationEnabled = true
//        configuration.isLightEstimationEnabled = true

        // Prefer a high-resolution streaming video format so distant/small QR codes carry enough
        // pixels-per-module for Vision to decode. This streams silently (unlike
        // captureHighResolutionFrame, which plays the camera shutter sound).
        // Try the dedicated 4K format first; otherwise fall back to the highest-resolution format
        // this device offers.
        for fmt in ARWorldTrackingConfiguration.supportedVideoFormats {
            Logger.info("DeviceAR supported video format \(fmt.imageResolution) @ \(fmt.framesPerSecond)fps")
        }
        if #available(iOS 16.0, *), let hiRes = ARWorldTrackingConfiguration.recommendedVideoFormatFor4KResolution {
            configuration.videoFormat = hiRes
        } else if let best = ARWorldTrackingConfiguration.supportedVideoFormats.max(by: {
            $0.imageResolution.width * $0.imageResolution.height < $1.imageResolution.width * $1.imageResolution.height
        }) {
            configuration.videoFormat = best
        }
        Logger.info("DeviceAR selected video format \(configuration.videoFormat.imageResolution) @ \(configuration.videoFormat.framesPerSecond)fps")

        session.delegate = self

        // Deliberately not run here. The engine is initialized with the app now,
        // long before any AR screen exists; starting ARKit at that point would
        // raise the camera permission prompt at launch and hold the camera open
        // for a screen nobody has asked for. The AR screen starts the session
        // when it appears, the same way Android resumes ARCore from
        // onActivityResume.

        qrScanner.setEnabled(DeviceAR_qrScanEnabled())
    }

    func postInit(configPtr: UnsafeRawPointer) {
    }

    // Session control. Main thread only - it is driven by the AR screen's
    // appearance and by Context.reloadARSession.
    func pauseSession() {
        session.pause()
        mSessionRunning = false
        DeviceAR_setCameraFeedWanted(false)
        // The frame the engine holds is the engine thread's to unlock (mLockedFrame).

        mSessionLock.lock()
        mCurrentFrame = nil
        mSessionLock.unlock()

        qrScanner.clearPending()
        if (Renderer.instance.backgroundPass != nil) {
            Renderer.instance.backgroundPass.requestReset()
        }
    }

    func restartSession() {
        pauseSession()
        qrScanner.resetDedupe()
        configuration.detectionImages.removeAll()
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        mSessionRunning = true

        // The Live View cover is up from here until this session's first frame.
        mSessionLock.lock()
        mFirstFrameReported = false
        mSessionLock.unlock()
        DeviceAR_setCameraFeedWanted(true)
    }

    // A failed or interrupted session delivers no frames: the screen holds its
    // last image. Said in the log, which is otherwise silent about it. Main
    // queue, as every delegate call.
    func session(_ session: ARSession, didFailWithError error: Error) {
        Logger.error("DeviceAR: the AR session failed: \(error)")

        // A configuration ARKit refuses with the depth semantics in it - a video
        // format they do not go with, say - runs again without them rather than
        // leaving the screen without a camera.
        let managed = DeviceAR.managedDepthSemantics
        if !configuration.frameSemantics.intersection(managed).isEmpty {
            configuration.frameSemantics.subtract(managed)
            mDepthRefused = true
            Logger.warn("DeviceAR: depth off - ARKit refused the configuration with it")
            if mSessionRunning {
                session.run(configuration)
            }
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        Logger.warn("DeviceAR: the AR session was interrupted")
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        Logger.info("DeviceAR: the AR session interruption ended")
    }

    func preFrameUpdate(frameContextPtr: UnsafeRawPointer) {
        applyDepthSemantics()

        // The one ARKit read of the engine frame. The display has a drawable for the
        // frame by now (IOSDisplay::beginFrame waits for it ahead of this), so the
        // newest frame here is the newest the screen can show, and the pose set below
        // and the image the background pass draws at the end of the frame are the
        // same frame's.
        let frame = currentFrame()
        if frame !== mFrameInUse {
            // The plane the engine read off the last frame is done with.
            unlockHeldFrame()
            mFrameInUse = frame
        }
        guard let frame = frame else { return }

        let orientation = Context.inst().getInterfaceOrientation()
        var projMat = frame.camera.projectionMatrix(for: orientation, viewportSize: Renderer.instance.viewportSize, zNear: CGFloat(mCameraMinZ), zFar: CGFloat(mCameraMaxZ))
        Camera_setProjectionMat(&projMat)
        var viewMat = frame.camera.viewMatrix(for: orientation)
        Camera_setViewMat(&viewMat)
    }

    // Every depth semantics this class puts into the configuration and takes out of it.
    private static let managedDepthSemantics: ARConfiguration.FrameSemantics = [.sceneDepth, .smoothedSceneDepth, .personSegmentationWithDepth]

    // Engine thread. Puts the depth semantics into the configuration when the
    // engine starts wanting them - the occlusion's, and the scene depth a
    // recording keeps - and takes them out when it stops; the session
    // mutation is the main thread's, like every other.
    private func applyDepthSemantics() {
        var wanted: ARConfiguration.FrameSemantics = []
        if DeviceAR_depthWanted() {
            if let semantics = DeviceAR.depthSemantics {
                wanted.insert(semantics)
            } else if !mOcclusionRefusalLogged {
                mOcclusionRefusalLogged = true
                Logger.info("DeviceAR: depth occlusion wanted, but this device has neither LiDAR nor people segmentation")
            }
        }
        if DeviceAR_captureDepthWanted() {
            if DeviceAR.captureDepthSupported {
                wanted.insert(.sceneDepth)
            } else if !mCaptureDepthRefusalLogged {
                mCaptureDepthRefusalLogged = true
                Logger.info("DeviceAR: a recording wants depth, but this device has no LiDAR - the scan is recorded without its surface")
            }
        }
        if wanted == mDepthRequested {
            return
        }
        mDepthRequested = wanted
        if wanted.isEmpty {
            releaseDepthMm()
        }

        runSessionOnMain { [self] session, configuration in
            var semantics = configuration.frameSemantics.subtracting(DeviceAR.managedDepthSemantics)
            if !mDepthRefused {
                semantics.formUnion(wanted)
            }
            if semantics == configuration.frameSemantics {
                return
            }
            configuration.frameSemantics = semantics
            Logger.info("DeviceAR: depth \(wanted.isEmpty ? "off" : "on") -\(wanted.contains(.smoothedSceneDepth) ? " scene depth for the occlusion (LiDAR)" : "")\(wanted.contains(.personSegmentationWithDepth) ? " people segmentation" : "")\(wanted.contains(.sceneDepth) ? " scene depth for the recording (LiDAR)" : "")")
            // A running session takes the change now and keeps its tracking; a
            // paused one starts with it at the next screen's run.
            if mSessionRunning {
                session.run(configuration)
            }
        }
    }

    private func releaseDepthMm() {
        mDepthMm?.deallocate()
        mDepthMm = nil
        mDepthMmCount = 0
        mDepthMmTimestamp = -1
    }

    // Engine thread. The frame's scene depth in millimetres, for a recording: LiDAR's metres
    // where ARKit is at least medium sure of them, 0 elsewhere. Converted once a frame and
    // held until the next call.
    private func depthMillimetres(_ frame: ARFrame) -> (UnsafePointer<UInt16>, Int, Int)? {
        guard let depth = frame.sceneDepth else { return nil }
        let map = depth.depthMap
        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        if width <= 0 || height <= 0 || CVPixelBufferGetPixelFormatType(map) != kCVPixelFormatType_DepthFloat32 {
            return nil
        }
        if mDepthMmTimestamp == frame.timestamp, let held = mDepthMm, mDepthMmCount == width * height {
            return (UnsafePointer(held), width, height)
        }
        if mDepthMmCount != width * height {
            releaseDepthMm()
            mDepthMm = UnsafeMutablePointer<UInt16>.allocate(capacity: width * height)
            mDepthMmCount = width * height
        }
        guard let out = mDepthMm else { return nil }
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(map)
        var confidenceBase: UnsafeMutableRawPointer?
        var confidenceRowBytes = 0
        if let confidence = depth.confidenceMap, CVPixelBufferGetWidth(confidence) == width, CVPixelBufferGetHeight(confidence) == height {
            CVPixelBufferLockBaseAddress(confidence, .readOnly)
            confidenceBase = CVPixelBufferGetBaseAddress(confidence)
            confidenceRowBytes = CVPixelBufferGetBytesPerRow(confidence)
        }
        defer {
            if let confidence = depth.confidenceMap, confidenceBase != nil {
                CVPixelBufferUnlockBaseAddress(confidence, .readOnly)
            }
        }
        for y in 0..<height {
            let row = (base + y * rowBytes).assumingMemoryBound(to: Float32.self)
            let sure = confidenceBase.map { ($0 + y * confidenceRowBytes).assumingMemoryBound(to: UInt8.self) }
            for x in 0..<width {
                let metres = row[x]
                let confident = sure.map { $0[x] >= UInt8(ARConfidenceLevel.medium.rawValue) } ?? true
                if confident && metres.isFinite && metres > 0 && metres < 65.0 {
                    out[y * width + x] = UInt16(metres * 1000)
                } else {
                    out[y * width + x] = 0
                }
            }
        }
        mDepthMmTimestamp = frame.timestamp
        return (UnsafePointer(out), width, height)
    }

    func inFrameUpdate(frameContextPtr: UnsafeRawPointer) {
        guard let frame = mFrameInUse else {
            return
        }
        if Settings_displayDebugLines() {
            for anchor in frame.anchors {
                if anchor.isKind(of: ARImageAnchor.self) {
                    let img = anchor as! ARImageAnchor
                    Renderer.instance.debugPass.drawRect(Float(img.referenceImage.physicalSize.width),
                                                         Float(img.referenceImage.physicalSize.height),
                                                         img.transform,
                                                         img.isTracked ? simd_float4(0, 1, 0, 1) : simd_float4(1, 0, 0, 1))
                }
            }

            if Settings_displayPointCloud() {
                if frame.rawFeaturePoints != nil {
                    for point in frame.rawFeaturePoints!.points {
                        Renderer.instance.debugPass.drawPoint(point, 0.03, simd_float4(1.0, 1.0, 0.0, 1))
                    }
                }
            }

            if Settings_displayDebugPlanes() {
                var planeColorIdx = 0
                for anchor in frame.anchors {
                    if anchor.isKind(of: ARPlaneAnchor.self) {
                        let plane = anchor as! ARPlaneAnchor
                        var color = g_colors[planeColorIdx % g_colors.count]
                        color.w = 0.4
                        Renderer.instance.debugPass.drawPlane(plane.geometry, plane.transform, color)
                        planeColorIdx += 1
                    }
                }
            }
        }
    }

    // The newest frame ARKit has delivered - a snapshot, since ARKit replaces it on
    // its delegate queue. preFrameUpdate is its one reader on the engine thread;
    // everything else there reads frameInUse(), so that an engine frame is one
    // ARKit frame.
    private func currentFrame() -> ARFrame? {
        mSessionLock.lock()
        defer { mSessionLock.unlock() }
        return mCurrentFrame
    }

    // The ARKit frame this engine frame is built on, from preFrameUpdate to the
    // next; nil while the session delivers none. Engine thread only - the
    // background pass, the depth occlusion, the debug drawing and the anchor
    // session read it there.
    func frameInUse() -> ARFrame? {
        return mFrameInUse
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        mSessionLock.lock()
        mCurrentFrame = frame
        let firstFrame = !mFirstFrameReported
        mFirstFrameReported = true
        mSessionLock.unlock()
        if firstFrame {
            DeviceAR_setCameraFrameReady()
        }

        qrScanner.handle(frame: frame, interfaceOrientation: Context.inst().getInterfaceOrientation())
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        Logger.info("TRACKING STATE CHANGED: \(camera.trackingState)")
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            let imageAnchor = anchor as? ARImageAnchor
            if imageAnchor != nil {
                processDetectedImage(imageAnchor: imageAnchor!)
                continue
            }
        }
    }
    
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            let imageAnchor = anchor as? ARImageAnchor
            if imageAnchor != nil {
                Logger.info("Added image anchor [\(imageAnchor!.referenceImage.name!)]")
                processDetectedImage(imageAnchor: imageAnchor!)
                continue
            }
        }
    }
    
    func processDetectedImage(imageAnchor: ARImageAnchor) {
        mSessionLock.lock()
        defer { mSessionLock.unlock() }

        for info in anchors {
            if info?.image?.hash == imageAnchor.referenceImage.hash {
                info!.imageAnchor = imageAnchor
                info!.isTracked = imageAnchor.isTracked
                info!.transform = imageAnchor.transform
                break
            }
        }
    }

    // ARSession mutation is main-thread work; these are all called from the
    // engine thread, so the session call is handed over and only our own anchor
    // bookkeeping - which is what the caller gets an id for - happens inline.
    private func runSessionOnMain(_ body: @escaping (ARSession, ARWorldTrackingConfiguration) -> Void) {
        DispatchQueue.main.async { [self] in
            body(session, configuration)
        }
    }

    func createMarker(markerPtr: UnsafeRawPointer) -> Int {
        let texPtr = Marker_image(markerPtr)
/*
        let texWidth = Texture_width(texPtr)
        let texHeight = Texture_height(texPtr)
        let data = UnsafeMutableRawPointer(mutating: Texture_imageData(texPtr)!)

        var pixelBuffer: CVPixelBuffer?

        // For 32RGBA: error -6680 which means "The buffer does not support the specified pixel format."
        //let cvResult = CVPixelBufferCreateWithBytes(nil, texWidth, texHeight, kCVPixelFormatType_32RGBA, data, texWidth * 4, nil, nil, nil, &pixelBuffer)
         
        let cvResult = CVPixelBufferCreate(nil, texWidth, texHeight, kCVPixelFormatType_32ARGB, nil, &pixelBuffer)
        if (cvResult != 0) {
            fatalError("CVPixelBufferCreate failed: \(cvResult)")
        }

        CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer!)!
        // RGBA -> ARGB + vertical flip
        for row in 0 ..< texHeight {
            for col in 0 ..< texWidth {
                let srcPixel = data + (texHeight-1 - row) * texWidth * 4 + col * 4
                let destPixel = baseAddress + row * texWidth * 4 + col * 4
                destPixel.copyMemory(from: srcPixel + 3, byteCount: 1) // copy Alpha
                (destPixel+1).copyMemory(from: srcPixel, byteCount: 3) // copy RGB
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))

        let image = ARReferenceImage(pixelBuffer!, orientation: .up, physicalWidth: CGFloat(Marker_width(markerPtr)))
*/
        let fileData = Data(bytes: Texture_fileData(texPtr), count: Texture_fileDataSize(texPtr))
        //let uiimage = UIImage(named: "marker-stones.png")!
        let uiimage = UIImage(data: fileData)!
        
        let cgimage = uiimage.cgImage

        let image = ARReferenceImage.init(cgimage!, orientation: .up, physicalWidth: CGFloat(Marker_width(markerPtr)))

        image.name = String(cString: Marker_name(markerPtr))

        mSessionLock.lock()
        let id = anchors.count
        anchors.append(AnchorInfo())
        anchors[id]?.image = image
        anchors[id]?.width = Marker_width(markerPtr)
        anchors[id]?.height = Marker_height(markerPtr)
        mSessionLock.unlock()

        runSessionOnMain { session, configuration in
            configuration.detectionImages.insert(image)
            session.pause()
            session.run(configuration/*, options: [.resetTracking, .removeExistingAnchors]*/)
        }

        return id
    }

    func deleteMarker(id: Int) {
        mSessionLock.lock()
        if id >= anchors.count {
            mSessionLock.unlock()
            fatalError("Invalid image id - out of bounds")
        }
        guard let image = anchors[id]?.image else {
            mSessionLock.unlock()
            fatalError("Marker already deleted")
        }
        anchors[id] = nil
        mSessionLock.unlock()

        runSessionOnMain { session, configuration in
            configuration.detectionImages.remove(image)
            session.run(configuration)
        }
    }

    func createAnchor(_ transformPtr: UnsafeRawPointer) -> Int {
        var mat = simd_float4x4()
        Transform_matrix(transformPtr, &mat)
        let anchor = ARAnchor(transform: mat)

        mSessionLock.lock()
        let id = anchors.count
        anchors.append(AnchorInfo())
        anchors[id]!.anchor = anchor
        mSessionLock.unlock()

        runSessionOnMain { session, _ in session.add(anchor: anchor) }
        return id
    }

    func getAnchor(_ id: Int) -> AnchorInfo? {
        mSessionLock.lock()
        defer { mSessionLock.unlock() }
        return id < anchors.count ? anchors[id] : nil
    }

    func getAnchorTracking(_ id: Int, _ outPtr: UnsafeMutableRawPointer) {
        mSessionLock.lock()
        defer { mSessionLock.unlock() }

        if id >= anchors.count {
            fatalError("Invalid image id - out of bounds")
        }
        if anchors[id]!.imageAnchor != nil {
            var tmp = anchors[id]!.transform
            TrackingResult_assign(outPtr, anchors[id]!.isTracked, &tmp)
            return
        }
        if anchors[id]!.image != nil {
            return // the marker was created but not detected yet
        }
        if anchors[id]!.anchor != nil {
            var tmp = anchors[id]!.anchor!.transform
            TrackingResult_assign(outPtr, true, &tmp)
            return
        }
        //fatalError("Invalid anchor id")
    }

    func deleteAnchor(_ id: Int) {
        mSessionLock.lock()
        if id >= anchors.count {
            mSessionLock.unlock()
            fatalError("Invalid image id - out of bounds")
        }
        let anchor = anchors[id]!.anchor!
        anchors[id] = nil
        mSessionLock.unlock()

        runSessionOnMain { session, _ in session.remove(anchor: anchor) }
    }

    // The one ARSession call still made straight from the engine thread. It is a
    // read-only query and has to return a result to the caller, so it cannot be
    // handed to the main queue the way the mutations above are. See the note in
    // the port write-up.
    func raycast(_ orig: simd_float3, _ dir: simd_float3, _ flags: UInt, _ outPtr: UnsafeMutableRawPointer) {
        let target = raycastStrategyFromCore(Settings_iosRaycastStrategy())
        let query = ARRaycastQuery(origin: orig, direction: dir, allowing: target, alignment: .any)
        let results = session.raycast(query)
        if (results.count > 0) {
            let idx = 0 //(flags & SWIFT_AR_RAYCAST_FURTHEST_FIRST == 0) ? 0 : results.count - 1
            var pos = simd_float3(results[idx].worldTransform.columns.3.x,
                                  results[idx].worldTransform.columns.3.y,
                                  results[idx].worldTransform.columns.3.z)
            var norm = simd_float3(results[idx].worldTransform.columns.1.x,
                                   results[idx].worldTransform.columns.1.y,
                                   results[idx].worldTransform.columns.1.z)
            RaycastResult_assign(outPtr, true, &pos, &norm)
        }
    }
    
}
