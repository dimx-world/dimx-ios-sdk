import CoreLocation
import CoreMotion
import Foundation
import UIKit
import UserNotifications

/// The parking detection: knows when a visitor's car trip ends inside a venue and records where.
/// The iOS twin of android-app's ParkingWatcher, on what iOS gives a background app:
///
/// 1. A circular region round the venue, and a beacon region for its parking levels, wake the app
///    - relaunching it when it is not running - as the car arrives. The host calls `launch` from
///    `application(_:didFinishLaunchingWithOptions:)` so the watcher exists to take the event.
/// 2. Woken, the watcher starts location updates with background updates allowed, which is what
///    keeps the app running with the screen off, ranges the venue's beacons, and asks Core Motion
///    for the activity: automotive and then walking is the drive's end. iOS offers no word of the
///    car's Bluetooth to third parties, so motion is the one signal here.
/// 3. Twelve seconds after the end, with the person out of the car, ParkingFix turns what was heard
///    into a place and a floor, the record is kept, told as a notification whose tap opens the
///    parking page, and told to the page when one is up. Everything stops until the next drive.
///
/// Main thread only: CLLocationManager belongs to the thread that made it, and every callback here
/// is delivered there. Whether Core Location ranging keeps delivering with the screen off on iOS 18
/// is the open question the module's own log answers - see `ranging` lines.
public final class ParkingWatcher: NSObject, CLLocationManagerDelegate, UNUserNotificationCenterDelegate {
    public static let shared = ParkingWatcher()

    static let notificationIdentifier = "dimx-parking-saved"
    static let appUrlKey = "dimx_app_url"
    /// Walking this long after the vehicle activity ended still counts as stepping out of the car.
    static let walkAfterVehicle: TimeInterval = 150
    /// A second drive end within this of the first is the same one said twice.
    static let driveEndDedupe: TimeInterval = 60
    /// Scanning past the drive's end: the person steps out and walks a few metres meanwhile.
    static let settle: TimeInterval = 12
    /// A session with no drive end in it: the person is shopping, and the scan would only cost battery.
    static let maxRun: TimeInterval = 45 * 60
    /// At the fence's entry, an automotive activity within this long says the device drove in.
    static let recentActivity: TimeInterval = 300
    /// A GPS fix older than this is not where the car is.
    static let fixFresh: TimeInterval = 120
    /// iOS monitors 20 regions per app and a venue takes two.
    static let maxVenues = 9

    private let manager = CLLocationManager()
    private let motion = CMMotionActivityManager()
    private let store = ParkingStore()
    private var enabled = false
    private var session: ParkingConfig?
    private var observations = ParkingFix.Observations()
    private var lastFix: CLLocation?
    private var settling = false
    private var settleTimer: Timer?
    private var runTimer: Timer?
    private var rangingUuid: UUID?
    private var activityOn = false
    private var rangingHeard = 0
    private var rangingLoggedAt: TimeInterval = 0
    private var notificationsAllowed: Bool?
    private var pendingOpenUrl: String?
    private var permissionsCompletion: (() -> Void)?
    /// The page hears every change of the record through this, as {"record": ...}.
    var pageListener: ((String) -> Void)?

    private override init() {
        super.init()
    }

    // MARK: - The host's entry points

    /// Whether the host's AppConfig turned the detection on at the last run that reached the
    /// context - what a relaunch for a region event, which connects no scene and runs no
    /// `Context.initialize`, goes by.
    private static let enabledKey = "dimx.parking.enabled"

    /// From the host's `application(_:didFinishLaunchingWithOptions:)`, before anything else, so a
    /// launch for a region event finds the watcher's delegate in place; iOS relaunches the app
    /// for the car arriving at a venue with no scene, and hands the event to the location manager
    /// made here or to nobody. Not the switch: the switch is `AppConfig.setParkingEnabled`, read
    /// as the context initializes and remembered for this call, which does nothing while the
    /// config has not turned the detection on. The DimensionX app calls it; an SDK host that wants
    /// the feature does the same and declares the permissions behind it (Always location, Motion,
    /// the location background mode, notifications).
    public static func launch(_ launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        guard UserDefaults.standard.bool(forKey: enabledKey) else {
            return
        }
        shared.enable(launchedForLocation: launchOptions?[.location] != nil)
    }

    /// The context's word (AppConfig.setParkingEnabled): on, remembered for the next launch and
    /// enabled now; off, forgotten and every region let go.
    static func applyConfig(enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        if enabled {
            shared.enable(launchedForLocation: false)
        } else {
            shared.disable()
        }
    }

    private func disable() {
        guard enabled else { return }
        for region in manager.monitoredRegions where region.identifier.hasPrefix("dimx-parking-") {
            manager.stopMonitoring(for: region)
        }
        stopSession("the host turned the detection off")
        enabled = false
        store.log("stopped: the host's config turned the detection off")
    }

    private func enable(launchedForLocation: Bool) {
        if enabled {
            return
        }
        enabled = true
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
        let center = UNUserNotificationCenter.current()
        if center.delegate == nil {
            center.delegate = self
        }
        refreshNotificationSettings()
        store.log("started" + (launchedForLocation ? " for a location event" : "") + ", monitoring \(manager.monitoredRegions.count) region(s)")
    }

    /// The page hands over a venue's config: kept, its regions registered. Answers an empty string,
    /// or what was wrong with the config.
    public func configure(_ json: String) -> String {
        let config: ParkingConfig
        do {
            config = try ParkingConfig.parse(json)
        } catch {
            Logger.warn("Parking: config refused: \(error)")
            return "\(error)"
        }
        store.put(config)
        store.log("configured \(config)")
        register(config)
        return ""
    }

    /// The page takes a venue's config back: its regions go, and a record of it with it.
    public func remove(_ dimension: String) {
        store.removeConfig(dimension)
        for region in manager.monitoredRegions where region.identifier == "dimx-parking-" + dimension
            || region.identifier == "dimx-parking-beacons-" + dimension {
            manager.stopMonitoring(for: region)
        }
        if let record = store.record(), record.dimension == dimension {
            clearRecord("the venue's config was removed")
        }
        store.log("config removed for [\(dimension)]")
    }

    /// {"record": <the record or null>} - what the page reads.
    public func recordJson() -> String {
        ParkingWatcher.recordJson(store.record())
    }

    private static func recordJson(_ record: ParkingRecord?) -> String {
        ParkingConfig.jsonText(["record": record?.toJson() ?? NSNull()])
    }

    /// The feature's standing, for the page's opt-in: enabled, the permissions held, the venues configured, the record.
    public func statusJson() -> String {
        let status = manager.authorizationStatus
        let always = status == .authorizedAlways
        let location = always || status == .authorizedWhenInUse
        let motionStatus = CMMotionActivityManager.authorizationStatus()
        var root: [String: Any] = [
            "enabled": enabled,
            "permissions": [
                "location": location,
                "background_location": always,
                "activity": motionStatus == .authorized,
                "bluetooth_scan": CLLocationManager.isRangingAvailable(),
                "bluetooth_connect": true,
                "notifications": notificationsAllowed ?? false,
            ],
            "ready": always && motionStatus == .authorized,
            "configured": store.configs().map { $0.dimension },
            "service_running": session != nil,
        ]
        let state = store.state()
        root["inside"] = state.inside
        root["vehicle_active"] = state.vehicleActive
        root["record"] = store.record()?.toJson() ?? NSNull()
        refreshNotificationSettings()
        return ParkingConfig.jsonText(root)
    }

    /// The page drops the record - the user found the car, or says the spot is wrong.
    public func clearRecord(_ why: String) {
        guard store.record() != nil else { return }
        store.setRecord(nil)
        store.log("record cleared: \(why)")
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [ParkingWatcher.notificationIdentifier])
        center.removePendingNotificationRequests(withIdentifiers: [ParkingWatcher.notificationIdentifier])
        tellPage(ParkingWatcher.recordJson(nil))
    }

    /// Debug builds: `drive_end` ends a drive now, as the motion would; `clear` drops the record.
    public func selfTest(_ what: String) {
        if what == "drive_end" {
            var state = store.state()
            if state.inside.isEmpty {
                guard let first = store.configs().first else {
                    store.log("self-test: no config to end a drive in")
                    return
                }
                state.inside = first.dimension
                store.log("self-test: standing inside [\(state.inside)] for the test")
            }
            state.vehicleActive = true
            state.vehicleSince = ParkingWatcher.now()
            store.setState(state)
            driveEnded("test")
        } else if what == "clear" {
            clearRecord("self-test")
        } else {
            store.log("self-test: unknown [\(what)]")
        }
    }

    /// The app url a notification of ours carries, for a host handling the tap itself (a cold start's `connectionOptions.notificationResponse`).
    public static func appUrl(of response: UNNotificationResponse) -> String? {
        response.notification.request.content.userInfo[appUrlKey] as? String
    }

    /// A url a notification's tap asked for before a screen could open it; the host's scene opens it as it becomes active.
    public static func takePendingOpenUrl() -> String? {
        let url = shared.pendingOpenUrl
        shared.pendingOpenUrl = nil
        return url
    }

    // MARK: - Permissions

    /// The opt-in, in iOS's order: Always location (the prompt, or the one-time upgrade from While
    /// Using), Motion (its first query is the prompt), notifications. Whatever the answers, the
    /// regions are registered with what is held, and `completion` runs.
    public func requestPermissions(_ completion: @escaping () -> Void) {
        permissionsCompletion = completion
        switch manager.authorizationStatus {
        case .notDetermined, .authorizedWhenInUse:
            store.log("asking for Always location (from \(manager.authorizationStatus.rawValue))")
            manager.requestAlwaysAuthorization()
            // locationManagerDidChangeAuthorization carries on; a user who dismisses the upgrade
            // prompt changes nothing and would leave the chain hanging, so a timer carries on too.
            DispatchQueue.main.asyncAfter(deadline: .now() + 90) { [weak self] in self?.continuePermissions() }
        case .denied, .restricted:
            Toast.show("Location is off for this app. To save where you park, allow it all the time in Settings.")
            continuePermissions()
        default:
            continuePermissions()
        }
    }

    private func continuePermissions() {
        guard permissionsCompletion != nil else { return }
        let next = { [weak self] in self?.finishPermissions() }
        guard CMMotionActivityManager.isActivityAvailable() else {
            store.log("motion activity is not available on this device")
            next()
            return
        }
        if CMMotionActivityManager.authorizationStatus() == .notDetermined {
            store.log("asking for Motion")
            let now = Date()
            motion.queryActivityStarting(from: now, to: now, to: .main) { _, _ in next() }
        } else {
            next()
        }
    }

    private func finishPermissions() {
        guard let completion = permissionsCompletion else { return }
        permissionsCompletion = nil
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.notificationsAllowed = granted
                self.store.log("notifications \(granted ? "allowed" : "refused")" + (error != nil ? ": \(error!)" : ""))
                self.reregisterAll()
                completion()
            }
        }
    }

    private func refreshNotificationSettings() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.notificationsAllowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            }
        }
    }

    // MARK: - Regions

    private func reregisterAll() {
        let configs = store.configs()
        if configs.isEmpty {
            return
        }
        store.log("registering \(configs.count) venue(s) again")
        for config in configs {
            register(config)
        }
    }

    private func register(_ config: ParkingConfig) {
        guard manager.authorizationStatus == .authorizedAlways else {
            store.log("regions of \(config.name) not registered: location is not allowed all the time yet (\(manager.authorizationStatus.rawValue))")
            return
        }
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            store.log("regions of \(config.name) not registered: region monitoring is not available")
            return
        }
        let others = manager.monitoredRegions.filter {
            $0.identifier.hasPrefix("dimx-parking-") && $0.identifier != config.fenceIdentifier && $0.identifier != config.beaconsIdentifier
        }
        if others.count >= ParkingWatcher.maxVenues * 2 {
            store.log("regions of \(config.name) not registered: \(ParkingWatcher.maxVenues) venues are monitored already")
            return
        }
        let radius = min(config.fence.radius, manager.maximumRegionMonitoringDistance)
        let fence = CLCircularRegion(center: CLLocationCoordinate2D(latitude: config.fence.lat, longitude: config.fence.lng),
                                     radius: radius, identifier: config.fenceIdentifier)
        fence.notifyOnEntry = true
        fence.notifyOnExit = true
        manager.startMonitoring(for: fence)
        if let uuid = config.uuid {
            let beacons = CLBeaconRegion(uuid: uuid, identifier: config.beaconsIdentifier)
            beacons.notifyOnEntry = true
            beacons.notifyOnExit = true
            beacons.notifyEntryStateOnDisplay = false
            manager.startMonitoring(for: beacons)
        }
        store.log("regions registered: \(config.name), \(Int(radius)) m round \(config.fence.lat),\(config.fence.lng)"
                  + (config.uuid != nil ? " and its beacons" : ""))
    }

    private func dimension(of region: CLRegion) -> String? {
        for prefix in ["dimx-parking-beacons-", "dimx-parking-"] where region.identifier.hasPrefix(prefix) {
            return String(region.identifier.dropFirst(prefix.count))
        }
        return nil
    }

    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let dimension = dimension(of: region) else { return }
        let byBeacons = region is CLBeaconRegion
        guard let config = store.config(dimension) else {
            store.log("entered the region of [\(dimension)], whose config is gone")
            return
        }
        var state = store.state()
        state.inside = dimension
        state.enteredAt = ParkingWatcher.now()
        store.setState(state)
        store.log("entered the \(byBeacons ? "beacons" : "fence") of \(config.name)")
        arrived(config, byBeacons: byBeacons)
    }

    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let dimension = dimension(of: region) else { return }
        if region is CLBeaconRegion {
            store.log("left the beacons of [\(dimension)]")
            return
        }
        var state = store.state()
        let name = store.config(dimension)?.name ?? dimension
        guard state.inside == dimension else {
            store.log("left the fence of \(name) (was not inside it)")
            return
        }
        state.inside = ""
        let clear = state.leaving || state.vehicleActive
        state.leaving = false
        store.setState(state)
        store.log("left the fence of \(name)" + (clear ? " by car" : ""))
        stopSession("left the fence")
        if let record = store.record(), record.dimension == dimension, clear {
            clearRecord("the car drove out of the fence")
        }
    }

    public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        store.log("region monitoring failed for [\(region?.identifier ?? "?")]: \(error.localizedDescription)")
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        store.log("authorization is now \(manager.authorizationStatus.rawValue)")
        if manager.authorizationStatus == .authorizedAlways {
            reregisterAll()
        }
        if permissionsCompletion != nil && manager.authorizationStatus != .notDetermined {
            continuePermissions()
        }
    }

    /// The device arrived: by its beacons, it is in the garage and the session starts at once; by
    /// the fence, the recent activity decides whether it drove in - a device that walked in has no
    /// car to find.
    private func arrived(_ config: ParkingConfig, byBeacons: Bool) {
        if byBeacons {
            startSession(config, why: "the beacons are in range")
            return
        }
        guard CMMotionActivityManager.isActivityAvailable() else {
            startSession(config, why: "entered the fence, no motion activity on this device")
            return
        }
        let now = Date()
        motion.queryActivityStarting(from: now.addingTimeInterval(-ParkingWatcher.recentActivity), to: now, to: .main) { [weak self] activities, error in
            guard let self = self else { return }
            if let error = error {
                self.store.log("the recent activity could not be read: \(error.localizedDescription)")
                self.startSession(config, why: "entered the fence, activity unknown")
                return
            }
            let automotive = (activities ?? []).last { $0.automotive && $0.confidence != .low }
            if let automotive = automotive {
                var state = self.store.state()
                state.vehicleActive = true
                state.vehicleSince = automotive.startDate.timeIntervalSince1970
                self.store.setState(state)
                self.startSession(config, why: "drove into the fence")
            } else {
                self.store.log("entered the fence of \(config.name) with no recent drive: not listening")
            }
        }
    }

    // MARK: - The session: location to stay awake, ranging, motion

    private func startSession(_ config: ParkingConfig, why: String, saveAfterSettle: String? = nil) {
        if let current = session, current.dimension != config.dimension {
            stopRanging()
            observations = ParkingFix.Observations()
        }
        let fresh = session == nil
        session = config
        if fresh {
            if ParkingWatcher.hasLocationBackgroundMode() {
                manager.allowsBackgroundLocationUpdates = true
                manager.pausesLocationUpdatesAutomatically = false
            } else {
                store.log("no location background mode in the app's Info.plist: the session lives only while the app is up")
            }
            manager.startUpdatingLocation()
            store.log("session started in \(config.name) (\(why))")
        }
        startRanging(config)
        startActivityUpdates()
        runTimer?.invalidate()
        runTimer = Timer.scheduledTimer(withTimeInterval: ParkingWatcher.maxRun, repeats: false) { [weak self] _ in
            self?.store.log("no drive end in \(Int(ParkingWatcher.maxRun / 60)) min")
            self?.stopSession("no drive end")
        }
        if let reason = saveAfterSettle {
            beginSettle(reason)
        }
    }

    private func stopSession(_ why: String) {
        guard session != nil else { return }
        runTimer?.invalidate()
        runTimer = nil
        settleTimer?.invalidate()
        settleTimer = nil
        settling = false
        stopRanging()
        stopActivityUpdates()
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        store.log("session stopped (\(why)): \(observations.count) sample(s) of \(observations.beacons) beacon(s), \(rangingHeard) ranged")
        session = nil
        rangingHeard = 0
    }

    private static func hasLocationBackgroundMode() -> Bool {
        ((Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]) ?? []).contains("location")
    }

    private func startRanging(_ config: ParkingConfig) {
        guard let uuid = config.uuid else {
            store.log("the venue names no beacons; the fix is GPS alone")
            return
        }
        if rangingUuid == uuid {
            return
        }
        guard CLLocationManager.isRangingAvailable() else {
            store.log("ranging is not available (Bluetooth off?); the fix is GPS alone")
            return
        }
        manager.startRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: uuid))
        rangingUuid = uuid
        rangingLoggedAt = 0
        store.log("ranging \(config.beacons.count) beacon(s) under \(uuid.uuidString.lowercased())")
    }

    private func stopRanging() {
        if let uuid = rangingUuid {
            manager.stopRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: uuid))
            rangingUuid = nil
        }
    }

    public func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon], satisfying constraint: CLBeaconIdentityConstraint) {
        guard let config = session else { return }
        let now = ParkingWatcher.now()
        var heard = 0
        for beacon in beacons where beacon.proximity != .unknown && beacon.rssi != 0 {
            guard let known = config.find(major: beacon.major.intValue, minor: beacon.minor.intValue) else { continue }
            observations.add(known, at: now, rssi: beacon.rssi)
            heard += 1
        }
        rangingHeard += heard
        // A line a minute: whether ranging goes on delivering - with the screen off above all.
        if now - rangingLoggedAt >= 60 {
            rangingLoggedAt = now
            let screen = UIApplication.shared.applicationState == .active ? "app active" : "app in background"
            store.log("ranging: \(beacons.count) beacon(s) in the answer, \(heard) known, \(observations.count) sample(s) kept, \(screen)")
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailRangingFor constraint: CLBeaconIdentityConstraint, error: Error) {
        store.log("ranging failed: \(error.localizedDescription)")
        rangingUuid = nil
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let last = locations.last {
            lastFix = last
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        store.log("location failed: \(error.localizedDescription)")
    }

    private func startActivityUpdates() {
        if activityOn || !CMMotionActivityManager.isActivityAvailable() {
            return
        }
        activityOn = true
        motion.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self = self, let activity = activity else { return }
            self.onActivity(activity)
        }
    }

    private func stopActivityUpdates() {
        if activityOn {
            motion.stopActivityUpdates()
            activityOn = false
        }
    }

    /// Core Motion's word, while the session runs: automotive marks the drive, walking after it ends the drive.
    private func onActivity(_ activity: CMMotionActivity) {
        if activity.confidence == .low {
            return
        }
        let now = activity.startDate.timeIntervalSince1970
        var state = store.state()
        if activity.automotive {
            if !state.vehicleActive {
                state.vehicleActive = true
                state.vehicleSince = now
                if !state.inside.isEmpty, let record = store.record(), record.dimension == state.inside {
                    state.leaving = true
                    store.log("driving again after the save: the car is leaving")
                }
                store.setState(state)
                store.log("activity automotive inside [\(state.inside)]")
            }
        } else if activity.walking || activity.running {
            let fromCar = state.vehicleActive || now - state.vehicleExitAt < ParkingWatcher.walkAfterVehicle
            if state.vehicleActive {
                state.vehicleActive = false
                state.vehicleExitAt = now
                store.setState(state)
            }
            store.log("activity \(activity.walking ? "walking" : "running")" + (fromCar ? " after the drive" : "") + " inside [\(state.inside)]")
            if !state.inside.isEmpty && fromCar {
                driveEnded("activity")
            }
        }
        // Stationary says nothing by itself: a car at a light is stationary too.
    }

    // MARK: - The end of a drive

    private func driveEnded(_ reason: String) {
        var state = store.state()
        let now = ParkingWatcher.now()
        if now - state.lastDriveEndAt < ParkingWatcher.driveEndDedupe {
            store.log("drive end (\(reason)) ignored: one \(Int(now - state.lastDriveEndAt)) s ago")
            return
        }
        guard !state.inside.isEmpty else {
            store.log("drive end (\(reason)) outside any fence: nothing to save")
            return
        }
        guard let config = store.config(state.inside) else {
            store.log("drive end (\(reason)) inside [\(state.inside)], whose config is gone")
            return
        }
        state.lastDriveEndAt = now
        state.leaving = false
        store.setState(state)
        store.log("drive ended (\(reason)) inside \(config.name): settling")
        if session != nil {
            beginSettle(reason)
        } else {
            startSession(config, why: reason, saveAfterSettle: reason)
        }
    }

    private func beginSettle(_ reason: String) {
        guard !settling, let config = session else { return }
        settling = true
        runTimer?.invalidate()
        store.log("settling for \(Int(ParkingWatcher.settle)) s (\(reason)): \(observations.count) sample(s) of \(observations.beacons) beacon(s) so far")
        settleTimer = Timer.scheduledTimer(withTimeInterval: ParkingWatcher.settle, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.saveFix(config, reason: reason)
            self.stopSession("saved")
        }
    }

    private func saveFix(_ config: ParkingConfig, reason: String) {
        let now = ParkingWatcher.now()
        let record: ParkingRecord
        if let fix = ParkingFix.compute(config, observations, now: now) {
            record = ParkingRecord(dimension: config.dimension, name: config.name, floor: fix.floor, lat: fix.lat, lng: fix.lng,
                                   accuracy: fix.accuracy, savedAt: Int64(now * 1000), source: ParkingRecord.sourceBeacons, reason: reason,
                                   beaconsUsed: fix.beaconsUsed, appUrl: config.appUrl, detail: fix.detail)
        } else if let fix = lastFix, now - fix.timestamp.timeIntervalSince1970 < ParkingWatcher.fixFresh, fix.horizontalAccuracy >= 0 {
            record = ParkingRecord(dimension: config.dimension, name: config.name, floor: "", lat: fix.coordinate.latitude,
                                   lng: fix.coordinate.longitude, accuracy: max(5, fix.horizontalAccuracy), savedAt: Int64(now * 1000),
                                   source: ParkingRecord.sourceGps, reason: reason, beaconsUsed: 0, appUrl: config.appUrl,
                                   detail: "gps fix \(Int(now - fix.timestamp.timeIntervalSince1970)) s old, \(observations.count) beacon sample(s)")
        } else {
            store.log("nothing to save: no beacon heard (\(observations.count) sample(s)) and no fresh fix")
            return
        }
        store.setRecord(record)
        var state = store.state()
        state.lastSavedAt = now
        state.leaving = false
        store.setState(state)
        store.log("saved: \(record)" + (record.detail.isEmpty ? "" : " [\(record.detail)]"))
        showSavedNotification(record)
        tellPage(ParkingWatcher.recordJson(record))
    }

    private func tellPage(_ json: String) {
        pageListener?(json)
    }

    // MARK: - Notifications

    private func showSavedNotification(_ record: ParkingRecord) {
        let content = UNMutableNotificationContent()
        content.title = "Your parking location is saved"
        var whereText = record.name
        if !record.floor.isEmpty {
            whereText += ", level " + record.floor
        }
        content.body = whereText + ". Tap to see it on the map."
        content.sound = .default
        content.threadIdentifier = "dimx-parking"
        content.userInfo = [ParkingWatcher.appUrlKey: record.appUrl]
        let request = UNNotificationRequest(identifier: ParkingWatcher.notificationIdentifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                self?.store.log("the saved notification was refused: \(error.localizedDescription)")
            }
        }
    }

    /// A notification of ours while the app is in front: shown all the same.
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                       withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if notification.request.identifier == ParkingWatcher.notificationIdentifier {
            completionHandler([.banner, .list, .sound])
        } else {
            completionHandler([])
        }
    }

    /// The tap: the parking page of the venue, opened by the context when there is one and handed
    /// to the host's scene otherwise (takePendingOpenUrl).
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                       withCompletionHandler completionHandler: @escaping () -> Void) {
        if let url = ParkingWatcher.appUrl(of: response) {
            store.log("notification tapped: \(url)")
            if Context.isInitialized {
                Context.inst().showWebScreen(url)
            } else {
                pendingOpenUrl = url
            }
        }
        completionHandler()
    }

    // MARK: - Helpers

    static func now() -> TimeInterval {
        Date().timeIntervalSince1970
    }
}
