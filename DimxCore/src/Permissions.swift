import AVFoundation
import CoreLocation
import CoreMotion
import Foundation
import Photos
import UIKit
import UserNotifications

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
    /// The microphone, for a video recording with sound (the engine's
    /// requestPermission): the system prompt when undecided, the standing
    /// answer otherwise. Main thread; answers on the main queue.
    static func requestMicrophone(_ completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                completion(true)
                return
            case .denied:
                completion(false)
                return
            default:
                break
            }
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted:
                completion(true)
                return
            case .denied:
                completion(false)
                return
            default:
                break
            }
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    private struct Request {
        let camera: Bool
        let completion: (PermissionOutcome) -> Void
    }

    private let mLocation: LocationManager
    private var mPending: [Request] = []
    private var mRunning = false
    // Whether the host posts notifications - the parking finder's saved spot, the venue tracking -
    // and so whether the page's Permissions section lists them (pageStatus).
    private let mUsesNotifications: Bool

    init(_ locationManager: LocationManager, usesNotifications: Bool) {
        mLocation = locationManager
        mUsesNotifications = usesNotifications
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
        if feature == "parking" {
            // The parking detection's opt-in: Always location, Motion, notifications - asked in that
            // order by the watcher, which registers its regions with whatever is granted.
            ParkingWatcher.shared.requestPermissions {
                Logger.info("Permissions: parking asked for; status \(ParkingWatcher.shared.statusJson())")
            }
            return
        }
        if feature == "venue_tracking" || feature == "venue_tracking_background" {
            // The venue tracking's opt-in: the precise location while the app is in use, and - for
            // a visitor who asked for arrivals to be noticed by themselves - the location all the
            // time, as iOS's one-time upgrade. The tracker tells the page what the phone now allows.
            VenueTracker.shared.requestPermissions(background: feature == "venue_tracking_background") {
                Logger.info("Permissions: \(feature) asked for")
            }
            return
        }
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

    // MARK: - The page's Permissions section

    /// Posted when a location authorization changes, for the page's Permissions section to hear it
    /// at once (WebViewCtrl).
    static let changedNotification = Notification.Name("DimxPermissionsChanged")

    // Whether the page has asked for Always - iOS puts the upgrade to the user once, and never says
    // whether it did, so after this the section sends the user to Settings for it.
    private static let askedAlwaysKey = "world.dimx.permissions.asked_always"

    /// What the page's Permissions section shows, as JSON - every permission this app asks for (its
    /// Info.plist names a purpose for it) by the id the page knows it by, whether it is held and
    /// whether iOS would still ask, and the phone's location and Bluetooth:
    /// `{"platform": "ios", "os": 18, "permissions": {"location": {"state": "approximate",
    /// "can_ask": false}, ...}, "services": {"location": "on", "bluetooth": "on"}}`.
    /// A state is `granted`, `approximate` (location without Precise Location), `not_asked`,
    /// `denied` or `restricted` (Screen Time or a profile: no one on the phone can change it);
    /// `can_ask` is true only while iOS has never asked - after that, Settings alone changes it.
    /// Answers on the main queue: the notification settings and the location switch are read off it.
    public func pageStatus(_ completion: @escaping (String) -> Void) {
        let info = Bundle.main.infoDictionary ?? [:]
        var permissions: [String: Any] = [:]

        let status = mLocation.authorizationStatus()
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            permissions["location"] = Self.entry(mLocation.accuracyReduced() ? "approximate" : "granted", false)
        case .notDetermined:
            permissions["location"] = Self.entry("not_asked", true)
        case .restricted:
            permissions["location"] = Self.entry("restricted", false)
        default:
            permissions["location"] = Self.entry("denied", false)
        }

        if info["NSLocationAlwaysAndWhenInUseUsageDescription"] != nil {
            switch status {
            case .authorizedAlways:
                permissions["background_location"] = Self.entry("granted", false)
            case .authorizedWhenInUse:
                let asked = UserDefaults.standard.bool(forKey: Self.askedAlwaysKey)
                permissions["background_location"] = Self.entry(asked ? "denied" : "not_asked", !asked)
            case .notDetermined:
                permissions["background_location"] = Self.entry("not_asked", true)
            case .restricted:
                permissions["background_location"] = Self.entry("restricted", false)
            default:
                permissions["background_location"] = Self.entry("denied", false)
            }
        }

        if info["NSCameraUsageDescription"] != nil {
            permissions["camera"] = Self.entry(AVCaptureDevice.authorizationStatus(for: .video))
        }

        if info["NSMicrophoneUsageDescription"] != nil {
            if #available(iOS 17.0, *) {
                switch AVAudioApplication.shared.recordPermission {
                case .granted: permissions["microphone"] = Self.entry("granted", false)
                case .denied: permissions["microphone"] = Self.entry("denied", false)
                default: permissions["microphone"] = Self.entry("not_asked", true)
                }
            } else {
                switch AVAudioSession.sharedInstance().recordPermission {
                case .granted: permissions["microphone"] = Self.entry("granted", false)
                case .denied: permissions["microphone"] = Self.entry("denied", false)
                default: permissions["microphone"] = Self.entry("not_asked", true)
                }
            }
        }

        if info["NSMotionUsageDescription"] != nil && CMMotionActivityManager.isActivityAvailable() {
            switch CMMotionActivityManager.authorizationStatus() {
            case .authorized: permissions["activity"] = Self.entry("granted", false)
            case .notDetermined: permissions["activity"] = Self.entry("not_asked", true)
            case .restricted: permissions["activity"] = Self.entry("restricted", false)
            default: permissions["activity"] = Self.entry("denied", false)
            }
        }

        if let level = Self.photosLevel() {
            switch PHPhotoLibrary.authorizationStatus(for: level) {
            case .authorized, .limited: permissions["photos"] = Self.entry("granted", false)
            case .notDetermined: permissions["photos"] = Self.entry("not_asked", true)
            case .restricted: permissions["photos"] = Self.entry("restricted", false)
            default: permissions["photos"] = Self.entry("denied", false)
            }
        }

        // Withdrawn while Bluetooth is off (BeaconScanner): the one word on it short of CoreBluetooth.
        let bluetooth = CLLocationManager.isRangingAvailable() ? "on" : "off"
        let usesNotifications = mUsesNotifications

        let group = DispatchGroup()
        var notifications: [String: Any]?
        if usesNotifications {
            group.enter()
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral: notifications = Self.entry("granted", false)
                case .notDetermined: notifications = Self.entry("not_asked", true)
                default: notifications = Self.entry("denied", false)
                }
                group.leave()
            }
        }
        // Off the main queue: iOS warns that the switch's answer can keep it waiting.
        var locationOn = true
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            locationOn = CLLocationManager.locationServicesEnabled()
            group.leave()
        }
        group.notify(queue: .main) {
            if let notifications = notifications {
                permissions["notifications"] = notifications
            }
            let root: [String: Any] = [
                "platform": "ios",
                "os": ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
                "permissions": permissions,
                "services": ["location": locationOn ? "on" : "off", "bluetooth": bluetooth],
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: root),
                  let json = String(data: data, encoding: .utf8) else {
                Logger.error("Permissions: the page's standing does not serialize")
                completion("{}")
                return
            }
            completion(json)
        }
    }

    /// One permission of the page's Permissions section, asked the way iOS asks for it; `done` runs on
    /// the main queue once the user has answered - or at once where iOS shows nothing. Settings is the
    /// page's own way for what iOS no longer asks (openSettings).
    public func request(pagePermission id: String, _ done: @escaping () -> Void) {
        Logger.info("Permissions: [\(id)] asked for from the page")
        switch id {
        case "location":
            requestLocation { _ in done() }
        case "background_location":
            // The upgrade from While Using is iOS's one-time question, and keeping While Using answers
            // nothing: the page hears the standing again as the app becomes active after the question,
            // and from here a moment on, for when iOS shows none.
            UserDefaults.standard.set(true, forKey: Self.askedAlwaysKey)
            mLocation.requestAlways()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: done)
        case "camera":
            AVCaptureDevice.requestAccess(for: .video) { _ in DispatchQueue.main.async(execute: done) }
        case "microphone":
            PermissionsManager.requestMicrophone { _ in done() }
        case "notifications":
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                DispatchQueue.main.async(execute: done)
            }
        case "activity":
            guard CMMotionActivityManager.isActivityAvailable() else {
                done()
                return
            }
            // Motion has no request of its own: its first query is the question.
            let manager = CMMotionActivityManager()
            let now = Date()
            manager.queryActivityStarting(from: now, to: now, to: .main) { _, _ in
                withExtendedLifetime(manager) { done() }
            }
        case "photos":
            guard let level = Self.photosLevel() else {
                done()
                return
            }
            PHPhotoLibrary.requestAuthorization(for: level) { _ in DispatchQueue.main.async(execute: done) }
        default:
            Logger.warn("Permissions: no permission [\(id)] to ask for")
            done()
        }
    }

    /// Where the page sends the user for what iOS no longer asks: the app's page in the Settings app -
    /// its notification settings for `notifications`. iOS opens nothing deeper for anyone else, so the
    /// phone's location switch and Bluetooth are steps the page spells out from there.
    public static func openSettings(_ target: String) {
        let address = target == "notifications"
            ? UIApplication.openNotificationSettingsURLString
            : UIApplication.openSettingsURLString
        guard let url = URL(string: address) else {
            return
        }
        UIApplication.shared.open(url)
    }

    private static func entry(_ state: String, _ canAsk: Bool) -> [String: Any] {
        return ["state": state, "can_ask": canAsk]
    }

    private static func entry(_ status: AVAuthorizationStatus) -> [String: Any] {
        switch status {
        case .authorized: return entry("granted", false)
        case .notDetermined: return entry("not_asked", true)
        case .restricted: return entry("restricted", false)
        default: return entry("denied", false)
        }
    }

    /// The photo library access the app's purpose strings ask for (ExtMediaStore.saveToPhotos), or nil for none.
    private static func photosLevel() -> PHAccessLevel? {
        let info = Bundle.main.infoDictionary ?? [:]
        if info["NSPhotoLibraryAddUsageDescription"] != nil {
            return .addOnly
        }
        if info["NSPhotoLibraryUsageDescription"] != nil {
            return .readWrite
        }
        return nil
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
