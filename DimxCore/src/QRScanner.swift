import Foundation
import ARKit
import Vision
import DimxNative

// Passive, long-distance QR recognition that runs alongside an active ARKit session.
//
// Design (see plan):
//   • Frames arrive on ARKit's delegate thread via handle(frame:interfaceOrientation:) and are stashed
//     into a single latest-only slot (older frames are dropped, never queued).
//   • A serial background queue runs at most one VNDetectBarcodesRequest at a time (busy guard),
//     restricted to .qr, cycling the regionOfInterest center -> wide -> full.
//   • Distance headroom comes from the high-resolution streaming video format selected in
//     DeviceAR.initialize() (see recommendedVideoFormatFor4KResolution). We deliberately do NOT
//     use ARSession.captureHighResolutionFrame -- it performs a still capture that plays the
//     system camera shutter sound, which is unwanted during a passive AR session.
//   • A payload is only emitted after it is seen in 2 near-consecutive detections, and each
//     unique code is emitted once. On emit we call processQRCode(code) which pushes an engine
//     event -> AppDimension::onQRCode(code).
final class QRScanner {

    private let queue = DispatchQueue(label: "com.dimx.qrscanner", qos: .userInitiated)
    private let lock  = NSLock()

    // Latest-only frame slot (drop-old). Retains at most one capturedImage past the delegate.
    private var latest: (pixel: CVPixelBuffer, orient: CGImagePropertyOrientation)?
    private var busy = false
    private var enabled = false
    private var frameCounter = 0

    // Run Vision at ~10 Hz on a 60 fps stream.
    private let runEveryNFrames = 6

    // Confirmation + dedupe. Each unique payload is emitted at most once for the lifetime of
    // this scanner (cleared only by resetDedupe()).
    private var pendingPayload: String?
    private var pendingCount = 0
    private var emittedPayloads = Set<String>()
    private let confirmNeeded = 2

    private let request: VNDetectBarcodesRequest = {
        let r = VNDetectBarcodesRequest()
        r.symbologies = [.qr]
        if #available(iOS 16.0, *) { r.revision = VNDetectBarcodesRequestRevision3 }
        return r
    }()

    // MARK: - Configuration

    func setEnabled(_ on: Bool) {
        lock.lock()
        enabled = on
        if !on {
            latest = nil
            pendingPayload = nil
            pendingCount = 0
        }
        lock.unlock()
        Logger.info("QRScanner enabled = \(on)")
    }

    // Drop any buffered frame / in-progress confirmation without changing the enabled state.
    // Used on session pause: no frames arrive while paused, so scanning halts naturally and
    // resumes (with the same enabled state) once frames flow again.
    func clearPending() {
        lock.lock()
        latest = nil
        pendingPayload = nil
        pendingCount = 0
        lock.unlock()
    }

    // Forget already-emitted payloads so they can be reported again (e.g. on a fresh AR session).
    func resetDedupe() {
        lock.lock()
        emittedPayloads.removeAll()
        lock.unlock()
    }

    // MARK: - Frame intake (called on ARKit's delegate thread -- keep cheap)

    func handle(frame: ARFrame, interfaceOrientation: UIInterfaceOrientation) {
        let orientation = QRScanner.visionOrientation(interfaceOrientation)
        lock.lock()
        guard enabled else { lock.unlock(); return }
        frameCounter &+= 1
        let shouldRunStream = (frameCounter % runEveryNFrames == 0) && !busy
        latest = (frame.capturedImage, orientation)
        if shouldRunStream { busy = true }
        lock.unlock()

        if shouldRunStream {
            queue.async { [weak self] in self?.drain() }
        }
    }

    // ARKit's capturedImage is delivered in the camera's native landscape-right sensor
    // orientation; map the current interface orientation to the EXIF orientation Vision needs
    // to interpret the image upright. NOTE: verify on-device for landscape orientations.
    static func visionOrientation(_ o: UIInterfaceOrientation) -> CGImagePropertyOrientation {
        switch o {
        case .portrait:            return .right
        case .portraitUpsideDown:  return .left
        case .landscapeLeft:       return .down
        case .landscapeRight:      return .up
        default:                   return .right
        }
    }

    // MARK: - Streaming detection

    private func drain() {
        lock.lock()
        guard let job = latest else { busy = false; lock.unlock(); return }
        latest = nil
        let n = frameCounter
        lock.unlock()

        request.regionOfInterest = QRScanner.roi(forPass: n / runEveryNFrames)
        scan(pixel: job.pixel, orientation: job.orient)

        lock.lock()
        busy = false
        let more = latest != nil
        if more { busy = true }
        lock.unlock()
        if more { queue.async { [weak self] in self?.drain() } }
    }

    // regionOfInterest is normalized (origin bottom-left) in the *oriented* image space.
    // Mostly-central (cheap), one wide and one full pass per 8 passes.
    static func roi(forPass pass: Int) -> CGRect {
        switch pass % 8 {
        case 3: return CGRect(x: 0.15, y: 0.15, width: 0.70, height: 0.70) // wide
        case 7: return CGRect(x: 0.0,  y: 0.0,  width: 1.0,  height: 1.0)  // full (rare)
        default: return CGRect(x: 0.30, y: 0.30, width: 0.40, height: 0.40) // center (common)
        }
    }

    // MARK: - Vision request + result handling (runs on `queue`)

    private func scan(pixel: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixel, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            Logger.info("QRScanner Vision request failed: \(error)")
            return
        }
        guard let observations = request.results as? [VNBarcodeObservation] else { return }
        consume(observations)
    }

    private func consume(_ observations: [VNBarcodeObservation]) {
        guard let best = observations.first(where: { $0.symbology == .qr }),
              let payload = best.payloadStringValue, !payload.isEmpty else {
            lock.lock(); pendingPayload = nil; pendingCount = 0; lock.unlock()
            return
        }

        // pendingPayload / pendingCount / emittedPayloads may also be touched by
        // setEnabled/clearPending/resetDedupe on other threads, so guard them with the lock.
        lock.lock()
        if payload == pendingPayload {
            pendingCount += 1
        } else {
            pendingPayload = payload
            pendingCount = 1
        }
        // Confirm across 2 near-consecutive frames, then emit each unique code only once.
        let shouldEmit = pendingCount >= confirmNeeded && emittedPayloads.insert(payload).inserted
        lock.unlock()

        guard shouldEmit else { return }
        Logger.info("QRScanner detected QR bbox=\(best.boundingBox) payload=[\(payload)]")
        payload.withCString { processQRCode($0) }
    }
}
