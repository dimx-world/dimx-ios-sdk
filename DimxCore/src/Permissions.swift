import AVFoundation
import CoreLocation
import Foundation
import UIKit

/// What the app holds after a request, read off the live status. The camera
/// is the one thing the AR screen cannot do without; location and beacon
/// ranging make it find nearby content and are only reported, so a caller
/// can say what is off and carry on.
public struct PermissionOutcome {
    public let camera: Bool
    public let location: Bool
    /// Beacon ranging. On iOS this is not a permission of its own - CoreLocation
    /// ranges beacons under the location grant and only needs Bluetooth to be
    /// switched on - so it is never prompted for.
    public let bluetooth: Bool
    /// A denial Settings cannot lift - a profile or parental control restricts
    /// it. Otherwise every iOS denial is changed in Settings, since the system
    /// prompt is shown once and never again.
    public let restricted: Bool

    /// Appended to a message about something that is off.
    var settingsHint: String {
        return restricted ? "" : " You can allow it in Settings."
    }
}

/// Asks for what the screens need and reports what it got, without ever
/// remembering the answer: every request reads the live status, so a
/// permission denied once and allowed later in Settings is picked up by the
/// next tap on the camera button or the map, and a denial is a result for
/// the caller to act on rather than a dead end.
///
/// Requests coalesce. The system prompts make the scene resign and become
/// active again, and a caller reacting to that would otherwise start a second
/// pass while the first is mid-flight - which is what used to drop the deep
/// link on a first launch. A request arriving while a pass runs waits for it,
/// and is answered by it when the pass covers what it wanted, or starts the
/// next pass when it does not (a location-only pass cannot answer a request
/// that also wanted the camera).
///
/// Main thread only, like every UIKit prompt.
public final class PermissionsManager {
    private struct Request {
        let camera: Bool
        let completion: (PermissionOutcome) -> Void
    }

    private let mLocation: LocationManager
    private var mPending: [Request] = []
    private var mRunning = false

    init(_ locationManager: LocationManager) {
        mLocation = locationManager
    }

    /// Everything the AR screen wants: camera and location prompted for in
    /// that order if still undecided, beacon ranging reported. Answers once
    /// with the whole picture.
    public func requestAR(_ completion: @escaping (PermissionOutcome) -> Void) {
        enqueue(Request(camera: true, completion: completion))
    }

    /// Location alone, for the app's start: the web screen lists what is
    /// nearby, and the prompt is better tied to the app appearing than to a
    /// tap. Whatever the answer, the app goes on; the AR screen asks again for
    /// what it needs when it is opened.
    public func requestLocation(_ completion: @escaping (PermissionOutcome) -> Void) {
        enqueue(Request(camera: false, completion: completion))
    }

    /// The permissions behind a feature the web page names as the user goes
    /// there - `"map"`: location, with beacon ranging reported - another chance
    /// after a refusal at the start. Whatever the answer the page goes on; a
    /// grant shows up as geolocation updates, and a refusal iOS no longer
    /// prompts for gets a toast pointing at Settings, since the tap would
    /// otherwise do nothing visible. Unknown names are ignored, so a newer
    /// page against an older build loses nothing.
    public func request(feature: String) {
        guard feature == "map" else {
            Logger.warn("Permissions: no permissions behind [\(feature)]")
            return
        }
        requestLocation { outcome in
            if outcome.location {
                Logger.info("Permissions: map has location; beacon ranging \(outcome.bluetooth ? "available" : "unavailable (Bluetooth off?)")")
            } else {
                Toast.show("Access to your location is off for this app.\(outcome.settingsHint)")
            }
        }
    }

    /// The current standing, with no prompt.
    public func status() -> PermissionOutcome {
        return outcome()
    }

    private func enqueue(_ request: Request) {
        mPending.append(request)
        if !mRunning {
            runPass()
        }
    }

    private func runPass() {
        mRunning = true
        let wantsCamera = mPending.contains { $0.camera }

        let afterCamera = { [self] in
            requestLocationAccess { [self] in finishPass(camera: wantsCamera) }
        }
        if wantsCamera {
            requestCameraAccess(afterCamera)
        } else {
            afterCamera()
        }
    }

    private func finishPass(camera: Bool) {
        let result = outcome()
        let answered = mPending.filter { camera || !$0.camera }
        mPending.removeAll { camera || !$0.camera }
        for request in answered {
            request.completion(result)
        }

        if mPending.isEmpty {
            mRunning = false
        } else {
            runPass()
        }
    }

    private func requestLocationAccess(_ done: @escaping () -> Void) {
        mLocation.requestPermission { _ in done() }
    }

    private func requestCameraAccess(_ done: @escaping () -> Void) {
        if AVCaptureDevice.authorizationStatus(for: .video) != .notDetermined {
            done()
            return
        }
        AVCaptureDevice.requestAccess(for: .video) { _ in
            DispatchQueue.main.async(execute: done)
        }
    }

    private func outcome() -> PermissionOutcome {
        var restricted = false

        let location: Bool
        switch mLocation.authorizationStatus() {
        case .authorizedAlways, .authorizedWhenInUse:
            location = true
        case .restricted:
            location = false
            restricted = true
        default:
            location = false
        }

        let camera: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            camera = true
        case .restricted:
            camera = false
            restricted = true
        default:
            camera = false
        }

        // Withdrawn while Bluetooth is off; there is no prompt to raise for it.
        let bluetooth = CLLocationManager.isRangingAvailable()

        return PermissionOutcome(camera: camera, location: location, bluetooth: bluetooth, restricted: restricted)
    }

    /// The alert behind a refused AR screen: the camera is off, and a way to
    /// Settings when that can help. Both buttons call back, so a caller can
    /// fall through to something else - the web screen for a deep link.
    func presentCameraDeniedAlert(_ outcome: PermissionOutcome, _ dismissed: @escaping () -> Void) {
        guard let top = topMostViewController() else {
            Logger.error("Permissions: no view controller to present the alert on")
            dismissed()
            return
        }

        let alert = UIAlertController(title: "Live View unavailable",
                                      message: "Live View needs access to the camera.\(outcome.settingsHint)",
                                      preferredStyle: .alert)
        if !outcome.restricted {
            alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                dismissed()
            })
        }
        alert.addAction(UIAlertAction(title: "Not now", style: .cancel) { _ in dismissed() })
        top.present(alert, animated: true)
    }
}
