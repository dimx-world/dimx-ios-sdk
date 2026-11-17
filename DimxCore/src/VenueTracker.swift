import CoreLocation
import Foundation
import UIKit
import UserNotifications

/// Venue tracking: while a visitor who asked for it is at a venue, the phone records what it
/// observes of the visit - fixes, the venue's beacons, and the stretches it observed nothing in -
/// as a session the page later takes (VenueSessionFile). The iOS twin of android-app's
/// VenueTracker and VenueTrackingService, behind the same bridge and writing the same records;
/// VenueVisit.Judge, shared with Android by its scenarios, says when a visit began and when it
/// is over. What iOS gives a background app shapes the rest:
///
/// 1. A session begins in front of the visitor. With the app opened and a venue tracked, the
///    tracker looks for it - a fix, and a few seconds of ranging the venue's beacons - and, the
///    venue found, starts the location manager's standard updates, never paused - from iOS 17
///    under a CLBackgroundActivitySession, with Core Location's live updates beside them. That is
///    what iOS lets go on once the app leaves the screen and the phone is locked, under "While
///    Using" as under "Always", with the system's own indicator on the status bar - and, the
///    updates going on while the phone is still, what keeps the app from being suspended under a
///    visitor who stands. A new session is never begun from the background.
/// 2. A session a dead process left is taken up again by the next one - the app opened, or
///    relaunched by iOS for the location updates or a region - while it is still the visitor's
///    choice, the location is still allowed and the recording stopped less than the venue's
///    resume window ago; the stretch in between is written as a gap. Past that it is closed as
///    interrupted, with nothing claimed after its last record.
/// 3. For a visitor who also allowed location all the time and asked for it, a circular region
///    round the venue and a beacon region for its beacons wake the app as the phone arrives. In
///    the seconds iOS gives it there the arrival is noted - when, by what, one fix, the beacons
///    heard - for the session's header, and a kept session is taken up; the fence's exit goes to
///    the judge of a running session and closes a kept one nothing is recording.
/// 4. The venue's beacons are ranged for the length of the session. Ranging answers once a
///    second while it runs, and the answers are what is written: a window exists only where
///    ranging answered, and says whether the app was in front and the phone unlocked. Whether
///    iOS goes on answering with the screen off is for a device to say (the windows marked `bg`
///    of a session are the answer); until it has, an answer with nothing in it counts as
///    "listened and heard nothing" for the judge only while the app is in front.
/// 5. Once the judge confirmed the visit, what has been written of it goes to the backend every
///    `upload_interval_s` while it goes on (VenueUploader.kickLive), and the rest when it is over;
///    nothing of a session the judge never confirmed leaves the phone.
///
/// What it does not do: keep the phone awake by itself, or start anything iOS did not allow.
/// A stretch in which nothing reached it is a gap in the record, which is the truth of it.
/// Main thread only: CLLocationManager belongs to the thread that made it.
public final class VenueTracker: NSObject, CLLocationManagerDelegate {
    public static let shared = VenueTracker()

    static let fencePrefix = "dimx-venue-"
    static let beaconsPrefix = "dimx-venue-beacons-"
    /// Of the twenty regions iOS monitors for an app (RegionBudget), what this takes at most: a
    /// fence and a beacon region for four venues - the nearest ones, when more are watched.
    static let maxWatchedVenues = 4

    /// How long one look ranges the tracked venues' beacons and waits for a fix.
    private static let lookS: TimeInterval = 12
    /// Between looks, while the app stays in front and no venue was found.
    private static let lookEveryS: TimeInterval = 90
    /// A fix at a look counts when it is this accurate or better, and within the site widened by its accuracy.
    private static let lookAccuracyM = 150.0
    private static let tickS: TimeInterval = 5
    private static let tickMs: Int64 = 5_000
    private static let heartbeatMs: Int64 = 60_000
    private static let persistMs: Int64 = 30_000
    /// Nothing reached the tracker for this long - no fix, no ranging answer, no timer: written as a gap.
    private static let silenceGapMs: Int64 = 120_000
    /// A fix older than this when it arrives is where the phone was, not where it is.
    private static let staleFixMs: Int64 = 30_000
    /// Ranging answers every second while it runs; this long without an answer and it is not running, whatever was asked of it.
    private static let rangingSilentMs: Int64 = 10_000
    /// What a region event in the background is given to note the arrival, of the seconds iOS allows.
    private static let arrivalSampleS: TimeInterval = 8
    /// The key of the app's NSLocationTemporaryUsageDescriptionDictionary a visitor on approximate location is asked under.
    private static let purposeKey = "VenueTracking"

    /// One session's recording: its config, its file, its judge, and the counts the end reports.
    private final class Session {
        let config: VenueTrackingConfig
        let reason: String
        let judge: VenueVisit.Judge
        let gate: VenueVisit.FixGate
        let windows: VenueVisit.BleWindows
        let sampler: VenueVisit.FixSampler
        var id = ""
        var account = ""
        var writer: VenueSessionFile.Writer?
        var startedAt: Int64 = 0
        var fixes = 0
        var fixesSeen = 0
        /// Fixes the gate turned away: positions the phone could not have reached.
        var fixesImplausible = 0
        var bleWindows = 0
        var adverts = 0
        var gapsMs: Int64 = 0
        var restarts = 0
        var lastRecordAt: Int64 = 0
        var lastEventElapsed: Int64 = -1
        var lastEventAt: Int64 = 0
        var lastHeartbeatElapsed: Int64 = 0
        var lastPersistElapsed: Int64 = 0
        var fixesSinceHeartbeat = 0
        var staleSinceHeartbeat = 0
        var implausibleSinceHeartbeat = 0
        var updatesSinceHeartbeat = 0
        var advertsSinceHeartbeat = 0
        var rangesSinceHeartbeat = 0
        var batteryAtStart = -1
        /// When what was recorded was last sent while the visit goes on; -1 for not yet in this process.
        var lastLiveElapsed: Int64 = -1
        /// Core Location's word that the phone is not moving, which is when it stops sending fixes.
        var stationary = false
        var diagnostics = ""

        init(config: VenueTrackingConfig, reason: String, judge: VenueVisit.Judge, gate: VenueVisit.FixGate) {
            self.config = config
            self.reason = reason
            self.judge = judge
            self.gate = gate
            self.windows = VenueVisit.BleWindows(windowMs: Int64(config.sampling.bleWindowS) * 1000)
            self.sampler = VenueVisit.FixSampler(intervalMs: Int64(config.sampling.fixIntervalS) * 1000)
        }
    }

    /// What a region event in the background gathers of an arrival.
    private final class ArrivalSample {
        let config: VenueTrackingConfig
        var task = UIBackgroundTaskIdentifier.invalid
        var fix: CLLocation?
        var beacons: [Int: Int] = [:]
        var ranging = false

        init(config: VenueTrackingConfig) {
            self.config = config
        }
    }

    private let store = VenueTrackingStore()
    private var manager: CLLocationManager?
    private var started = false
    private var observers: [NSObjectProtocol] = []
    private var appActive = false
    private var locked = false
    private var locationServicesOn = true
    private var notificationsAllowed = false
    private var lastFix: CLLocation?
    private var permissionsCompletion: (() -> Void)?

    // The look for a venue
    private var looking = false
    private var lookVenues: [VenueTrackingConfig] = []
    private var lookRanging: [UUID] = []
    /// What the look under way has learnt, for the line it leaves when it finds no venue.
    private var lookSaw = ""
    private var looks = 0
    private var lookEndTimer: Timer?
    private var lookAgainTimer: Timer?

    // The session being recorded
    private var session: Session?
    private var tickTimer: Timer?
    private var lastTickElapsed: Int64 = 0
    private var backgroundSession: Any?          // CLBackgroundActivitySession, from iOS 17
    private var updatesTask: Task<Void, Never>?
    private var streamGeneration = 0
    private var streamName = "none"
    /// Whether the location manager's standard updates were started for the session: they carry its fixes.
    private var standardStream = false
    private var rangingUuid: UUID?
    private var lastRangeElapsed: Int64 = -1
    private var lastRangeWall: Int64 = 0
    private var bleStatus = "none"
    private var batteryMonitoringWas = false

    // A passive arrival being noted
    private var arrivalSample: ArrivalSample?
    private var arrivalTimer: Timer?

    /// The page hears every change of the standing through this, as `statusJson()`.
    var pageListener: ((String) -> Void)?

    private override init() {
        super.init()
    }

    // MARK: - The host's entry points

    /// From the host's `application(_:didFinishLaunchingWithOptions:)`, before anything else. iOS
    /// relaunches the app in the background - for the location updates of a session a dead process
    /// held, for a venue's region - with no scene and no `Context.initialize`, and hands what it
    /// has to the location manager made here, or to nobody; and a session to be taken up has to
    /// be taken up as the process starts. Not the switch: that is `AppConfig.setVenueTrackingEnabled`,
    /// read as the context initializes and kept for this call, which does nothing while the config
    /// has not turned the tracking on. The DimensionX app calls it; an SDK host that wants the
    /// feature does the same, and declares what stands behind it - the location usage strings, the
    /// `location` background mode, and Always location for the arrivals.
    public static func launch(_ launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        shared.start(launchOptions?[.location] != nil ? "launched for a location event" : "launch")
    }

    /// The context's word (AppConfig.setVenueTrackingEnabled) and who this install is: on, kept
    /// for the next launch and started now; off, every region let go and a running session ended.
    static func applyConfig(enabled: Bool, appInstance: String) {
        shared.applyHostConfig(enabled, appInstance)
    }

    private func applyHostConfig(_ enabled: Bool, _ appInstance: String) {
        var desired = store.desired()
        let was = VenueTrackingStore.hostEnabled(desired)
        if !enabled && !was && VenueTrackingStore.dimensions(desired).isEmpty {
            return   // never used on this install: nothing to write
        }
        let info = Bundle.main.infoDictionary
        desired["host_enabled"] = enabled
        desired["app_instance"] = appInstance
        desired["app"] = [
            "version": (info?["CFBundleShortVersionString"] as? String) ?? "",
            "build": (info?["CFBundleVersion"] as? String) ?? "",
        ]
        store.writeDesired(desired)
        if enabled != was {
            store.log("the host turned the tracking \(enabled ? "on" : "off")")
        }
        if enabled {
            start("the host's config")
            sync("app start")
        } else {
            stop()
        }
    }

    private func start(_ why: String) {
        guard !started, VenueTrackingStore.hostEnabled(store.desired()) else { return }
        started = true
        let manager = CLLocationManager()
        manager.delegate = self
        self.manager = manager
        observeApp()
        appActive = UIApplication.shared.applicationState == .active
        locked = !UIApplication.shared.isProtectedDataAvailable
        refreshStanding()
        store.log("started (\(why)), app \(VenueTracker.appStateName()), \(manager.monitoredRegions.count) region(s) monitored for the app")
        restoreOrClose(appActive ? "app_open" : "restart")
        syncRegions()
        sweep()
        if appActive && session == nil {
            look()
        }
    }

    private func stop() {
        guard started else { return }
        endByRequest("disabled", "host")
        stopLooking()
        endArrivalSample()
        if let manager = manager {
            for region in manager.monitoredRegions where VenueTracker.venue(of: region) != nil {
                manager.stopMonitoring(for: region)
            }
            manager.delegate = nil
        }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        manager = nil
        started = false
        store.log("stopped: the host's config turned the tracking off")
        notifyChanged()
    }

    // MARK: - What the page asks

    /// The page hands over a venue's config. Kept beside the visitor's choice for that venue,
    /// which it does not touch. Answers an empty string, or what was wrong with the config.
    public func configure(_ json: String) -> String {
        let config: VenueTrackingConfig
        do {
            config = try VenueTrackingConfig.parse(json)
        } catch {
            Logger.warn("VenueTracking: config refused: \(error)")
            return "\(error)"
        }
        var desired = store.desired()
        var venues = (desired["venues"] as? [String: Any]) ?? [:]
        var venue = (venues[config.dimension] as? [String: Any]) ?? [:]
        let now = config.toJson()
        if let old = venue["config"] as? [String: Any], VenueVisit.Records.line(old) == VenueVisit.Records.line(now) {
            return ""
        }
        venue["config"] = now
        venues[config.dimension] = venue
        desired["venues"] = venues
        store.writeDesired(desired)
        store.log("configured \(config)")
        sync("config")
        return ""
    }

    /// The page takes a venue's config back: the venue is tracked no more, a running session of it ends.
    public func remove(_ dimension: String) {
        var desired = store.desired()
        var venues = (desired["venues"] as? [String: Any]) ?? [:]
        guard venues.removeValue(forKey: dimension) != nil else { return }
        desired["venues"] = venues
        store.writeDesired(desired)
        store.log("config removed for [\(dimension)]")
        sync("config removed")
    }

    /// The visitor's choice for one venue: {"dimension", "enabled", "auto_start", "account"}.
    /// `auto_start` asks for the venue to be watched for an arrival, which also takes the location
    /// allowed all the time; `account` is whose visits these are, written into every session so
    /// the page never sends one under another account. Answers an empty string, or why the choice
    /// was not taken.
    public func setEnabled(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let choice = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return "unreadable JSON"
        }
        let dimension = VenueVisit.string(choice, "dimension")
        var desired = store.desired()
        var venues = (desired["venues"] as? [String: Any]) ?? [:]
        guard var venue = venues[dimension] as? [String: Any], VenueTrackingStore.config(desired, dimension) != nil else {
            return "the venue [\(dimension)] has no tracking config on this device"
        }
        let enable = VenueVisit.bool(choice, "enabled")
        let was = VenueTrackingStore.tracked(desired, store.state(), dimension)
        let auto = enable && VenueVisit.bool(choice, "auto_start")
        venue["enabled"] = enable
        venue["auto_start"] = auto
        venue["account"] = VenueVisit.string(choice, "account")
        if enable && !was {
            venue["since"] = VenueTracker.wall()
        }
        venues[dimension] = venue
        desired["venues"] = venues
        store.writeDesired(desired)
        store.log("tracking of [\(dimension)] " + (enable ? "enabled" + (auto ? ", watched for an arrival" : "") : "disabled"))
        sync(enable ? "enabled" : "disabled")
        if enable && appActive && session == nil {
            // The visitor is in the app, perhaps at the venue: look now rather than at the next opening.
            look()
        }
        return ""
    }

    /// The standing, for the page: whether the feature is there, what the phone allows it, the
    /// venues with the visitor's choice for each, the running session, and what is kept. The
    /// shape is the bridge's, the same on Android.
    public func statusJson() -> String {
        let desired = store.desired()
        let state = store.state()
        let manager = self.manager ?? CLLocationManager()
        let status = manager.authorizationStatus
        let always = status == .authorizedAlways
        let location = always || status == .authorizedWhenInUse
        let precise = manager.accuracyAuthorization == .fullAccuracy
        let ranging = CLLocationManager.isRangingAvailable()

        var root: [String: Any] = [
            "available": VenueTrackingStore.hostEnabled(desired),
            "platform": "ios",
            // What "start by itself" comes to here: the arrival is noticed and noted, and the
            // recording begins when the app is opened. On Android the session itself starts.
            "auto_start_mode": "arrival",
            "permissions": [
                "location": location,
                "precise": location && precise,
                "background_location": always,
                // Ranging goes by the location's permission; it needs Bluetooth on, and none of its own.
                "bluetooth_scan": true,
                "notifications": notificationsAllowed,
            ],
            "bluetooth": ranging ? "on" : "off",
            "location_services": locationServicesOn,
            "ready": location && precise && locationServicesOn,
            "auto_start_ready": always && precise && locationServicesOn,
            "restrictions": [
                // With Background App Refresh off iOS does not wake the app for a region.
                "background_restricted": UIApplication.shared.backgroundRefreshStatus != .available,
                "power_save": ProcessInfo.processInfo.isLowPowerModeEnabled,
                "battery_unrestricted": true,
                "background_mode_missing": !VenueTracker.hasLocationBackgroundMode(),
            ],
        ]

        let watched = Set(manager.monitoredRegions.map { $0.identifier })
        var venues: [[String: Any]] = []
        for dimension in VenueTrackingStore.dimensions(desired) {
            guard let venue = VenueTrackingStore.venue(desired, dimension),
                  let config = VenueTrackingStore.config(desired, dimension) else { continue }
            venues.append([
                "dimension": dimension,
                "name": config.name,
                "enabled": VenueTrackingStore.tracked(desired, state, dimension),
                "auto_start": VenueTrackingStore.autoStart(desired, dimension),
                "beacons": config.uuid != nil,
                "account": VenueVisit.string(venue, "account"),
                "fence_watched": watched.contains(config.fenceIdentifier),
            ])
        }
        root["venues"] = venues

        if let session = session {
            var summary = sessionRecord(session)
            summary.removeValue(forKey: "judge")
            summary["state"] = session.judge.state
            summary["recording"] = true
            root["session"] = summary
        } else if var kept = state["session"] as? [String: Any] {
            // A session no process is recording: it waits to be taken up, or closed.
            let judge = kept["judge"] as? [String: Any]
            kept.removeValue(forKey: "judge")
            kept["state"] = judge.map { VenueVisit.string($0, "state") } ?? ""
            kept["recording"] = false
            root["session"] = kept
        } else {
            root["session"] = NSNull()
        }
        if let refused = state["refused"] as? [String: Any] {
            root["refused"] = refused
        }
        if let arrival = state["arrival"] as? [String: Any] {
            root["arrival"] = VenueTracker.arrivalAsWritten(arrival)
        }
        let stored = VenueSessionFile.stored(store.sessionsDirectory)
        root["stored"] = ["sessions": stored.count, "bytes": stored.bytes] as [String: Any]
        refreshStanding()
        return VenueVisit.Records.line(root)
    }

    /// {"sessions": [...]}: the sessions on the device, for the page to take.
    public func sessionsJson() -> String {
        var list = VenueSessionFile.list(store.sessionsDirectory, activeId: activeSessionId())
        // What the uploader says of each one's sending: whole at the backend, or why not.
        let uploads = store.uploads()
        list["sessions"] = ((list["sessions"] as? [[String: Any]]) ?? []).map { session -> [String: Any] in
            var session = session
            let upload = (uploads[VenueVisit.string(session, "id")] as? [String: Any]) ?? [:]
            session["uploaded"] = VenueVisit.bool(upload, "done")
            let refused = VenueVisit.string(upload, "refused")
            if !refused.isEmpty {
                session["upload_refused"] = refused
            }
            return session
        }
        return VenueVisit.Records.line(list)
    }

    /// A piece of one session's records from `offset` (VenueSessionFile.chunk).
    public func sessionChunkJson(_ id: String, offset: Int64) -> String {
        if session?.id == id {
            flush()   // what the page reads is what was observed up to now
        }
        return VenueVisit.Records.line(VenueSessionFile.chunk(store.sessionsDirectory, id, offset: offset, activeId: activeSessionId()))
    }

    /// The page has the session where it belongs: the device's copy goes. Never the one being written.
    @discardableResult
    public func removeSession(_ id: String) -> Bool {
        if id == activeSessionId() {
            return false
        }
        let removed = VenueSessionFile.remove(store.sessionsDirectory, id)
        if removed {
            store.log("session \(id) handed over and removed")
        }
        return removed
    }

    /// Debug builds: `enable`, `enable_auto` and `disable` are the visitor's choice for the first
    /// configured venue, `start` begins a session there with no evidence asked (the judge still
    /// wants some), `stop` ends the running one, `status` logs the standing. `account` is whose
    /// visits an `enable` makes them - what the sessions carry and are sent under; a session of
    /// the default goes to no real account.
    public func selfTest(_ what: String, account: String = "self-test") {
        let desired = store.desired()
        let dimension = VenueTrackingStore.dimensions(desired).first ?? ""
        switch what {
        case "enable", "enable_auto", "disable":
            let choice: [String: Any] = ["dimension": dimension, "enabled": what != "disable", "auto_start": what == "enable_auto", "account": account]
            let refused = setEnabled(VenueVisit.Records.line(choice))
            store.log("self-test \(what): " + (refused.isEmpty ? "done" : refused))
        case "start":
            if let config = VenueTrackingStore.config(desired, dimension) {
                begin(config, reason: "test", fix: nil, beacon: false)
            } else {
                store.log("self-test start: no venue is configured")
            }
        case "stop":
            endByRequest("stopped", "test")
        case "status":
            store.log("self-test status: " + statusJson())
        default:
            store.log("self-test: unknown [\(what)]")
        }
    }

    private func activeSessionId() -> String? {
        if let session = session {
            return session.id
        }
        let id = VenueVisit.string((store.state()["session"] as? [String: Any]) ?? [:], "id")
        return id.isEmpty ? nil : id
    }

    private func notifyChanged() {
        if let listener = pageListener {
            listener(statusJson())
        }
    }

    // MARK: - Permissions

    /// The opt-in. Without `background`: location while the app is in use, precise - what a
    /// session cannot do without. With it: location all the time, which is what lets iOS wake the
    /// app at a venue's region; asked of a visitor who chose that, as the one-time upgrade from
    /// "While Using". Whatever the answers, the regions are registered with what is held, the page
    /// hears the standing, and `completion` runs.
    public func requestPermissions(background: Bool, _ completion: @escaping () -> Void) {
        guard let manager = manager else {
            store.log("permissions asked for with the tracking off")
            completion()
            return
        }
        permissionsCompletion = completion
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            store.log("asking for location while the app is in use")
            manager.requestWhenInUseAuthorization()
            awaitAuthorization()
        case .authorizedWhenInUse where background:
            store.log("asking for location all the time")
            manager.requestAlwaysAuthorization()
            awaitAuthorization()
        case .denied, .restricted:
            Toast.show("Location is off for this app. To record your visits, allow it in Settings.")
            finishPermissions()
        default:
            finishPermissions()
        }
    }

    /// locationManagerDidChangeAuthorization carries on; a visitor who dismisses the upgrade
    /// prompt changes nothing and would leave the chain hanging, so a timer carries on too.
    private func awaitAuthorization() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) { [weak self] in self?.finishPermissions() }
    }

    private func finishPermissions() {
        guard let completion = permissionsCompletion, let manager = manager else { return }
        permissionsCompletion = nil
        let status = manager.authorizationStatus
        let held = status == .authorizedWhenInUse || status == .authorizedAlways
        let done = { [weak self] in
            guard let self = self else { return }
            self.syncRegions()
            if self.appActive && self.session == nil {
                self.look()
            }
            self.notifyChanged()
            completion()
        }
        if held && manager.accuracyAuthorization != .fullAccuracy {
            // Approximate location is kilometres wide and takes the beacons away with it. iOS lends
            // the precise one for as long as the app stays in use, on the app's stated purpose.
            guard VenueTracker.hasPurposeKey() else {
                store.log("the location is approximate, and the app's Info.plist has no purpose [\(VenueTracker.purposeKey)] to ask for the precise one under")
                done()
                return
            }
            store.log("the location is approximate: asking for the precise one")
            manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: VenueTracker.purposeKey) { [weak self] error in
                DispatchQueue.main.async {
                    if let error = error {
                        self?.store.log("the precise location was not asked for: \(error.localizedDescription)")
                    }
                    done()
                }
            }
        } else {
            done()
        }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        store.log("location authorization is now \(VenueTracker.name(of: status)), \(manager.accuracyAuthorization == .fullAccuracy ? "precise" : "approximate")")
        refreshStanding()
        if session != nil {
            write(event("authorization", ["status": VenueTracker.name(of: status), "precise": manager.accuracyAuthorization == .fullAccuracy]))
            if status != .authorizedWhenInUse && status != .authorizedAlways {
                endByRequest("permission", "location")
            } else if manager.accuracyAuthorization != .fullAccuracy {
                endByRequest("permission", "precise_location")
            } else {
                flush()
            }
        }
        syncRegions()
        if permissionsCompletion != nil && status != .notDetermined {
            finishPermissions()
        } else {
            notifyChanged()
        }
    }

    /// What is read off the main thread or answered later: whether location is on for the phone
    /// at all, and whether the app may post notifications.
    private func refreshStanding() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let on = CLLocationManager.locationServicesEnabled()
            DispatchQueue.main.async { self?.locationServicesOn = on }
        }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            DispatchQueue.main.async { self?.notificationsAllowed = allowed }
        }
    }

    // MARK: - What is wanted against what is

    /// Brings what is in line with what is wanted: a session whose venue is no longer tracked
    /// ends, one nothing is recording is closed when it stopped too long ago, and the regions
    /// follow the venues watched.
    private func sync(_ why: String) {
        guard started else {
            notifyChanged()
            return
        }
        let desired = store.desired()
        var state = store.state()
        if let session = session {
            let dimension = session.config.dimension
            if !VenueTrackingStore.tracked(desired, state, dimension) {
                endByRequest(VenueTrackingStore.config(desired, dimension) == nil ? "config_removed" : "disabled", "visitor")
            }
        } else if let kept = state["session"] as? [String: Any] {
            let id = VenueVisit.string(kept, "id")
            let dimension = VenueVisit.string(kept, "dimension")
            let silent = VenueTracker.wall() - VenueVisit.int64(kept, "last_record_at")
            let config = VenueTrackingStore.config(desired, dimension)
            var close: String?
            if config == nil || !VenueTrackingStore.tracked(desired, state, dimension) {
                close = config == nil ? "config_removed" : "disabled"
            } else if let config = config, silent > config.rules.resumeWindowMs {
                close = "interrupted"
            }
            if let close = close {
                closeStale(&state, id, why: close, detail: "nothing recorded for \(silent / 1000) s (\(why))")
                store.writeState(state)
            }
        }
        if let arrival = state["arrival"] as? [String: Any],
           !VenueTrackingStore.tracked(desired, state, VenueVisit.string(arrival, "dimension")) {
            state = store.state()
            state.removeValue(forKey: "arrival")
            store.writeState(state)
        }
        syncRegions()
        sweep()
        notifyChanged()
    }

    private func sweep() {
        let uploads = store.uploads()
        for removed in VenueSessionFile.sweep(store.sessionsDirectory, activeId: activeSessionId(), now: VenueTracker.wall()) {
            let id = String(removed.prefix { $0 != " " })
            store.log("session removed\(VenueUpload.uploaded(uploads, id) ? "" : " unsent"): \(removed)")
        }
        // Sessions that are over and not yet with the backend - one whose sending failed, one just
        // closed - are sent now: this runs as the tracker starts in whatever process iOS launched,
        // and whenever what is wanted changes.
        VenueUploader.shared.kick("sweep", activeId: activeSessionId())
    }

    /// The session being written, which is never sent; nil for none. For the uploader's own runs.
    func currentSessionId() -> String? {
        activeSessionId()
    }

    /// The uploader's word that a session is with the backend, or never will be: the page hears of it.
    func uploadsChanged() {
        notifyChanged()
    }

    /// Closes a session nothing is writing, and forgets it in `state` (the caller writes the state).
    private func closeStale(_ state: inout [String: Any], _ id: String, why: String, detail: String) {
        VenueSessionFile.finish(store.sessionsDirectory, id, why: why, by: "unobserved")
        state.removeValue(forKey: "session")
        store.log("session \(id) closed as \(why): \(detail)")
    }

    // MARK: - Regions

    private static func venue(of region: CLRegion) -> (dimension: String, beacons: Bool)? {
        for (prefix, beacons) in [(beaconsPrefix, true), (fencePrefix, false)] where region.identifier.hasPrefix(prefix) {
            let dimension = String(region.identifier.dropFirst(prefix.count))
            if !dimension.isEmpty && dimension.allSatisfy({ $0.isASCII && $0.isNumber }) {
                return (dimension, beacons)
            }
        }
        return nil
    }

    /// The regions follow the venues the visitor asked to be watched, within what iOS allows: the
    /// location all the time and precise - a region event reaches a background app under nothing
    /// less - and the app's twenty regions, of which this takes what the rest of the app leaves,
    /// eight at most. With more venues than that, the one a session or an arrival is about comes
    /// first, then the nearest.
    private func syncRegions() {
        guard let manager = manager else { return }
        let desired = store.desired()
        let state = store.state()
        let mine = manager.monitoredRegions.filter { VenueTracker.venue(of: $0) != nil }
        var wanted: [VenueTrackingConfig] = []
        let allowed = manager.authorizationStatus == .authorizedAlways && manager.accuracyAuthorization == .fullAccuracy
            && CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self)
        if allowed {
            for dimension in VenueTrackingStore.dimensions(desired) {
                if let config = VenueTrackingStore.config(desired, dimension), VenueTrackingStore.tracked(desired, state, dimension),
                   VenueTrackingStore.autoStart(desired, dimension) {
                    wanted.append(config)
                }
            }
        }
        let first = Set([session?.config.dimension ?? VenueVisit.string((state["session"] as? [String: Any]) ?? [:], "dimension"),
                         VenueVisit.string((state["arrival"] as? [String: Any]) ?? [:], "dimension")])
        let from = lastFix ?? manager.location
        func rank(_ config: VenueTrackingConfig) -> Double {
            if first.contains(config.dimension) {
                return -1
            }
            guard let from = from else { return 0 }
            return config.fence.distance(toLat: from.coordinate.latitude, lng: from.coordinate.longitude)
        }
        wanted.sort { rank($0) < rank($1) }

        var room = min(RegionBudget.room(manager, replacing: Set(mine.map { $0.identifier })), VenueTracker.maxWatchedVenues * 2)
        var keep = Set<String>()
        var left: [String] = []
        for config in wanted {
            let need = config.uuid != nil ? 2 : 1
            if need > room {
                left.append(config.name)
                continue
            }
            room -= need
            keep.insert(config.fenceIdentifier)
            if config.uuid != nil {
                keep.insert(config.beaconsIdentifier)
            }
            register(config, manager, mine)
        }
        for region in mine where !keep.contains(region.identifier) {
            manager.stopMonitoring(for: region)
            store.log("region let go: \(region.identifier)")
        }
        if !left.isEmpty {
            store.log("not watched for an arrival, for want of regions (iOS monitors \(RegionBudget.limit) for the app, "
                      + "\(manager.monitoredRegions.count) are taken): \(left.joined(separator: ", "))")
        }
    }

    private func register(_ config: VenueTrackingConfig, _ manager: CLLocationManager, _ existing: Set<CLRegion>) {
        let radius = min(config.fence.radius, manager.maximumRegionMonitoringDistance)
        let same = existing.first { $0.identifier == config.fenceIdentifier } as? CLCircularRegion
        if same == nil || abs(same!.center.latitude - config.fence.lat) > 1e-7 || abs(same!.center.longitude - config.fence.lng) > 1e-7
            || abs(same!.radius - radius) > 0.5 {
            let fence = CLCircularRegion(center: CLLocationCoordinate2D(latitude: config.fence.lat, longitude: config.fence.lng),
                                         radius: radius, identifier: config.fenceIdentifier)
            fence.notifyOnEntry = true
            fence.notifyOnExit = true
            manager.startMonitoring(for: fence)
            store.log("fence registered: \(config.name), \(Int(radius.rounded())) m round \(config.fence.lat),\(config.fence.lng)")
        }
        if let uuid = config.uuid {
            let known = existing.first { $0.identifier == config.beaconsIdentifier } as? CLBeaconRegion
            if known?.uuid != uuid {
                let beacons = CLBeaconRegion(uuid: uuid, identifier: config.beaconsIdentifier)
                beacons.notifyOnEntry = true
                beacons.notifyOnExit = true
                beacons.notifyEntryStateOnDisplay = false
                manager.startMonitoring(for: beacons)
                store.log("beacon region registered: \(config.name), \(uuid.uuidString.lowercased())")
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        if let venue = VenueTracker.venue(of: region) {
            regionEvent(venue.dimension, beacons: venue.beacons, entered: true)
        }
    }

    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        if let venue = VenueTracker.venue(of: region) {
            regionEvent(venue.dimension, beacons: venue.beacons, entered: false)
        }
    }

    public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        if let region = region, VenueTracker.venue(of: region) != nil {
            store.log("region monitoring failed for [\(region.identifier)]: \(error.localizedDescription)")
        }
    }

    /// A venue's fence or its beacon region was crossed. A running session of that venue takes it
    /// as evidence; otherwise an entry is an arrival - noted, and a kept session taken up - and
    /// the fence's exit closes what nothing is recording.
    private func regionEvent(_ dimension: String, beacons: Bool, entered: Bool) {
        let desired = store.desired()
        var state = store.state()
        let config = VenueTrackingStore.config(desired, dimension)
        let now = VenueTracker.wall()
        store.log("\(entered ? "entered" : "left") the \(beacons ? "beacons" : "fence") of \(config?.name ?? dimension), app \(VenueTracker.appStateName())")

        if let session = session, session.config.dimension == dimension {
            alive(now)
            write(event((beacons ? "beacons_" : "fence_") + (entered ? "enter" : "exit")))
            if !beacons {
                apply(session.judge.onFence(now, entered: entered))
            } else if entered {
                // iOS heard one of the venue's beacons: the venue itself. Its going silent is nothing.
                apply(session.judge.onBeacon(now))
            }
            flush()
            return
        }
        guard let config = config, VenueTrackingStore.tracked(desired, state, dimension) else { return }

        if entered {
            let noted = (state["arrival"] as? [String: Any]) ?? [:]
            if VenueVisit.string(noted, "dimension") != dimension || now - VenueVisit.int64(noted, "at") > config.rules.maxSessionMs {
                state["arrival"] = ["dimension": dimension, "at": now, "by": beacons ? "beacons" : "fence"] as [String: Any]
                store.writeState(state)
            }
            if session == nil {
                if let kept = state["session"] as? [String: Any], VenueVisit.string(kept, "dimension") == dimension {
                    restoreOrClose("region")
                }
                if session == nil {
                    if appActive {
                        look()
                    } else {
                        sampleArrival(config)
                    }
                }
            }
            notifyChanged()
        } else if !beacons {
            var changed = false
            if VenueVisit.string((state["arrival"] as? [String: Any]) ?? [:], "dimension") == dimension {
                state.removeValue(forKey: "arrival")
                changed = true
            }
            if session == nil, let kept = state["session"] as? [String: Any], VenueVisit.string(kept, "dimension") == dimension {
                // Nothing was recording, and the phone has left: the session is over, and its end
                // says that nobody saw it end.
                closeStale(&state, VenueVisit.string(kept, "id"), why: "interrupted", detail: "the fence was left with nothing recording")
                changed = true
            }
            if changed {
                store.writeState(state)
                notifyChanged()
            }
        }
    }

    /// The seconds iOS gives a region event in the background: one fix and the venue's beacons
    /// heard meanwhile, kept with the arrival for the header of the session the visitor's opening
    /// of the app begins. Nothing goes on past them.
    private func sampleArrival(_ config: VenueTrackingConfig) {
        guard let manager = manager, arrivalSample == nil else { return }
        let sample = ArrivalSample(config: config)
        sample.task = UIApplication.shared.beginBackgroundTask(withName: "dimx-venue-arrival") { [weak self] in
            self?.endArrivalSample()
        }
        arrivalSample = sample
        manager.requestLocation()
        if let uuid = config.uuid, CLLocationManager.isRangingAvailable() {
            manager.startRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: uuid))
            sample.ranging = true
        }
        arrivalTimer?.invalidate()
        arrivalTimer = Timer.scheduledTimer(withTimeInterval: VenueTracker.arrivalSampleS, repeats: false) { [weak self] _ in
            self?.endArrivalSample()
        }
    }

    private func endArrivalSample() {
        arrivalTimer?.invalidate()
        arrivalTimer = nil
        guard let sample = arrivalSample else { return }
        arrivalSample = nil
        if sample.ranging, let uuid = sample.config.uuid, rangingUuid != uuid, !lookRanging.contains(uuid) {
            manager?.stopRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: uuid))
        }
        var state = store.state()
        if var arrival = state["arrival"] as? [String: Any], VenueVisit.string(arrival, "dimension") == sample.config.dimension {
            var said = "arrival at \(sample.config.name) noted"
            if let fix = sample.fix {
                let distance = sample.config.site.distance(toLat: fix.coordinate.latitude, lng: fix.coordinate.longitude)
                var noted: [String: Any] = [
                    "t": VenueTracker.millis(fix.timestamp),
                    "acc": VenueVisit.Records.round(fix.horizontalAccuracy, 10),
                    "d": Int(distance.rounded()),
                ]
                // Where it was only when that is within the fence: a region's event can come with
                // the phone still outside it, and no position past the fence is kept.
                if sample.config.fence.distance(toLat: fix.coordinate.latitude, lng: fix.coordinate.longitude) <= sample.config.fence.radius {
                    noted["lat"] = VenueVisit.Records.round(fix.coordinate.latitude, 1e6)
                    noted["lng"] = VenueVisit.Records.round(fix.coordinate.longitude, 1e6)
                }
                arrival["fix"] = noted
                said += ": a fix \(Int(distance.rounded())) m from its middle, +-\(Int(fix.horizontalAccuracy.rounded())) m"
            }
            if !sample.beacons.isEmpty {
                let strongest = sample.beacons.sorted { $0.value > $1.value }.prefix(3)
                arrival["beacons"] = strongest.map { [$0.key >> 16, $0.key & 0xFFFF, $0.value] }
                said += ", \(sample.beacons.count) beacon(s) heard"
            }
            state["arrival"] = arrival
            store.writeState(state)
            store.log(said)
        }
        if sample.task != .invalid {
            UIApplication.shared.endBackgroundTask(sample.task)
        }
    }

    // MARK: - The app around it

    private func observeApp() {
        let center = NotificationCenter.default
        func observe(_ name: Notification.Name, _ handler: @escaping (VenueTracker) -> Void) {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                if let self = self {
                    handler(self)
                }
            })
        }
        observe(UIApplication.didBecomeActiveNotification) { $0.appBecameActive() }
        observe(UIApplication.willResignActiveNotification) { $0.appResignedActive() }
        observe(UIApplication.didEnterBackgroundNotification) { $0.appEnteredBackground() }
        observe(UIApplication.willTerminateNotification) { $0.appTerminating() }
        observe(UIApplication.protectedDataWillBecomeUnavailableNotification) { $0.lockChanged(true) }
        observe(UIApplication.protectedDataDidBecomeAvailableNotification) { $0.lockChanged(false) }
        observe(.NSProcessInfoPowerStateDidChange) { $0.powerStateChanged() }
    }

    private func appBecameActive() {
        let was = appActive
        if session != nil {
            conditionChanged { appActive = true }
            if !was {
                write(event("app_front"))
                flush()
            }
        } else {
            appActive = true
            looks = 0
            restoreOrClose("app_open")
            if session == nil {
                look()
            }
        }
        refreshStanding()
        syncRegions()
        notifyChanged()
        // The app in front is a network as likely as it gets: what waits to be sent is tried now.
        VenueUploader.shared.kick("app in front", activeId: activeSessionId())
    }

    private func appResignedActive() {
        guard appActive else { return }
        conditionChanged { appActive = false }
        if looking && session == nil {
            store.log("stopped looking for a venue: the app left the screen" + (lookSaw.isEmpty ? "" : " (\(lookSaw))"))
        }
        stopLooking()
        if session != nil {
            write(event("app_inactive"))
            flush()
        }
    }

    private func appEnteredBackground() {
        if appActive {
            conditionChanged { appActive = false }
            stopLooking()
        }
        if session != nil {
            write(event("app_background"))
            persist()
        }
    }

    private func appTerminating() {
        guard let session = session else { return }
        // The file is left as it is: the session is taken up again or closed by whoever comes next.
        write(event("app_terminating"))
        persist()
        store.log("the app is being terminated with session \(session.id) running")
    }

    private func lockChanged(_ nowLocked: Bool) {
        guard locked != nowLocked else { return }
        conditionChanged { locked = nowLocked }
        if session != nil {
            write(event(nowLocked ? "locked" : "unlocked"))
            flush()
        }
    }

    private func powerStateChanged() {
        if session != nil {
            write(event(ProcessInfo.processInfo.isLowPowerModeEnabled ? "power_save_on" : "power_save_off"))
            flush()
        }
    }

    /// The app's place changed - in front, behind, the phone locked. The beacon windows open under
    /// the old one are closed first, so every window lies within one and says which.
    private func conditionChanged(_ change: () -> Void) {
        guard let session = session, session.windows.listening else {
            change()
            return
        }
        let now = VenueTracker.wall()
        var closed: [VenueVisit.BleWindows.Window] = []
        session.windows.stop(now, into: &closed)
        writeWindows(closed)
        change()
        session.windows.start(now)
        updateListening()
    }

    // MARK: - Looking for a venue

    /// One look, with the app in front: the tracked venues' beacons ranged for a few seconds, and a fix.
    private func look() {
        lookAgainTimer?.invalidate()
        lookAgainTimer = nil
        guard started, session == nil, appActive, let manager = manager else { return }
        let desired = store.desired()
        let state = store.state()
        let tracked = VenueTrackingStore.dimensions(desired)
            .filter { VenueTrackingStore.tracked(desired, state, $0) }
            .compactMap { VenueTrackingStore.config(desired, $0) }
        guard !tracked.isEmpty else {
            stopLooking()
            return
        }
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways, manager.accuracyAuthorization == .fullAccuracy else {
            lookAgain()
            return
        }
        stopLookRanging()
        looking = true
        lookSaw = ""
        lookVenues = tracked
        if CLLocationManager.isRangingAvailable() {
            for config in tracked {
                if let uuid = config.uuid, !lookRanging.contains(uuid) {
                    manager.startRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: uuid))
                    lookRanging.append(uuid)
                }
            }
        }
        manager.requestLocation()
        lookEndTimer?.invalidate()
        lookEndTimer = Timer.scheduledTimer(withTimeInterval: VenueTracker.lookS, repeats: false) { [weak self] _ in
            self?.endLook()
        }
    }

    private func endLook() {
        stopLookRanging()
        if looking && session == nil {
            // The first look of an opening says what it saw, and then every tenth: a venue that
            // is never found has to be explicable from the log, without the log filling with it.
            if looks % 10 == 0 {
                store.log("looked for \(lookVenues.count) venue(s), found none: "
                          + (lookSaw.isEmpty ? "no fix in \(Int(VenueTracker.lookS)) s" : lookSaw) + ", no beacon of theirs heard")
            }
            looks += 1
        }
        looking = false
        if appActive && session == nil {
            lookAgain()
        }
    }

    private func lookAgain() {
        lookAgainTimer?.invalidate()
        lookAgainTimer = Timer.scheduledTimer(withTimeInterval: VenueTracker.lookEveryS, repeats: false) { [weak self] _ in
            self?.look()
        }
    }

    private func stopLookRanging() {
        for uuid in lookRanging where rangingUuid != uuid {
            manager?.stopRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: uuid))
        }
        lookRanging = []
    }

    private func stopLooking() {
        looking = false
        lookVenues = []
        lookEndTimer?.invalidate()
        lookEndTimer = nil
        lookAgainTimer?.invalidate()
        lookAgainTimer = nil
        stopLookRanging()
    }

    /// The look found the venue: the session begins.
    private func found(_ config: VenueTrackingConfig, fix: CLLocation?, beacon: Bool) {
        if !begin(config, reason: "app_open", fix: fix, beacon: beacon) {
            stopLooking()
        }
    }

    // MARK: - Beginning, and taking up again

    /// A session no process is recording, found as this one starts or the app is opened: taken up
    /// when it is still wanted, recent enough and allowed, closed when it is not, and left to wait
    /// for the app when only the permission to go on from here is missing.
    private func restoreOrClose(_ reason: String) {
        guard session == nil, let manager = manager else { return }
        let desired = store.desired()
        var state = store.state()
        guard let kept = state["session"] as? [String: Any] else { return }
        let id = VenueVisit.string(kept, "id")
        let dimension = VenueVisit.string(kept, "dimension")
        let silent = VenueTracker.wall() - VenueVisit.int64(kept, "last_record_at")
        guard let config = VenueTrackingStore.config(desired, dimension), VenueTrackingStore.tracked(desired, state, dimension) else {
            closeStale(&state, id, why: VenueTrackingStore.config(desired, dimension) == nil ? "config_removed" : "disabled",
                       detail: "found at \(reason)")
            store.writeState(state)
            return
        }
        if silent > config.rules.resumeWindowMs {
            closeStale(&state, id, why: "interrupted", detail: "nothing recorded for \(silent / 1000) s")
            store.writeState(state)
            return
        }
        // From iOS 17 a background location session a dead process held may be made again by the
        // next one wherever it runs; before, location in the background takes "Always".
        var may = appActive || manager.authorizationStatus == .authorizedAlways
        if #available(iOS 17.0, *) {
            may = true
        }
        guard may else {
            store.log("session \(id) waits for the app to be opened: location is allowed only while the app is in use")
            return
        }
        // Only what can be taken up: a session whose file is gone or already ended is not begun
        // anew from here, with nothing yet to say the phone is at the venue - the look does that.
        let file = VenueSessionFile.file(store.sessionsDirectory, id)
        guard FileManager.default.fileExists(atPath: file.path), VenueSessionFile.end(file) == nil, kept["judge"] is [String: Any] else {
            closeStale(&state, id, why: "interrupted", detail: "its file cannot be taken up (\(reason))")
            store.writeState(state)
            return
        }
        begin(config, reason: reason, fix: nil, beacon: false)
    }

    /// Begins recording at the venue: takes up the session a dead process left when it is this
    /// venue's and recent enough, or - in front of the visitor - opens a new one, and starts the
    /// sources. `fix` or `beacon` is what the look found, handed to the judge as its first
    /// evidence. False when the location is not allowed or the file could not be opened.
    @discardableResult
    private func begin(_ config: VenueTrackingConfig, reason: String, fix: CLLocation?, beacon: Bool) -> Bool {
        guard let manager = manager, session == nil else { return false }
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            noteRefused(config, reason, "location")
            return false
        }
        guard manager.accuracyAuthorization == .fullAccuracy else {
            noteRefused(config, reason, "precise_location")
            return false
        }
        let now = VenueTracker.wall()
        let desired = store.desired()
        var state = store.state()
        let dir = store.sessionsDirectory
        let hasBeacons = config.uuid != nil
        // The battery's level is read only while its monitoring is on; put back as it was at the end.
        let monitoringWas = UIDevice.current.isBatteryMonitoringEnabled
        UIDevice.current.isBatteryMonitoringEnabled = true

        var taken: Session?
        if let kept = state["session"] as? [String: Any] {
            let keptId = VenueVisit.string(kept, "id")
            let lastRecordAt = VenueVisit.int64(kept, "last_record_at")
            let file = VenueSessionFile.file(dir, keptId)
            if VenueVisit.string(kept, "dimension") == config.dimension, FileManager.default.fileExists(atPath: file.path),
               VenueSessionFile.end(file) == nil, let judge = kept["judge"] as? [String: Any],
               now - lastRecordAt <= config.rules.resumeWindowMs {
                let startedAt = kept["started_at"] != nil ? VenueVisit.int64(kept, "started_at") : now
                let session = Session(config: config, reason: reason,
                                      judge: VenueVisit.Judge.from(judge, rules: config.rules, siteRadiusM: config.site.radius,
                                                                   fenceRadiusM: config.fence.radius, venueHasBeacons: hasBeacons),
                                      gate: VenueVisit.FixGate.from(kept["gate"] as? [String: Any], lat: config.fence.lat,
                                                                    lng: config.fence.lng, radiusM: config.fence.radius, t: startedAt))
                do {
                    session.writer = try VenueSessionFile.Writer(dir: dir, id: keptId)
                } catch {
                    store.log("session \(keptId) could not be reopened: \(error)")
                    UIDevice.current.isBatteryMonitoringEnabled = monitoringWas
                    return false
                }
                session.id = keptId
                session.account = VenueVisit.string(kept, "account")
                session.startedAt = startedAt
                session.fixes = Int(VenueVisit.number(kept, "fixes", 0))
                session.fixesSeen = Int(VenueVisit.number(kept, "fixes_seen", 0))
                session.fixesImplausible = Int(VenueVisit.number(kept, "fixes_implausible", 0))
                session.bleWindows = Int(VenueVisit.number(kept, "ble_windows", 0))
                session.adverts = Int(VenueVisit.number(kept, "adverts", 0))
                session.gapsMs = VenueVisit.int64(kept, "gaps_ms") + max(0, now - lastRecordAt)
                session.restarts = Int(VenueVisit.number(kept, "restarts", 0)) + 1
                session.batteryAtStart = Int(VenueVisit.number(kept, "battery_at_start", -1))
                session.judge.onListening(false)
                session.judge.resumed(now)
                self.session = session
                // What was not recorded is said, from the last record to now: nothing in between
                // is known, whatever the phone was doing.
                write(VenueVisit.Records.gap(now, from: lastRecordAt, to: now, sensor: "all", why: "process_restart"))
                write(event("resumed", ["reason": reason, "app_front": appActive]))
                store.log("session \(keptId) taken up again at \(config.name) (\(reason)) after \((now - lastRecordAt) / 1000) s unrecorded")
                taken = session
            } else {
                closeStale(&state, keptId, why: "interrupted", detail: "another start came (\(reason))")
                store.writeState(state)
            }
        }
        if taken == nil {
            // iOS lets a background location session begin in front of its user, and nowhere else.
            guard appActive || reason == "test" else {
                store.log("no new session of \(config.name) (\(reason)): one begins with the app in front")
                UIDevice.current.isBatteryMonitoringEnabled = monitoringWas
                return false
            }
            let session = Session(config: config, reason: reason,
                                  judge: VenueVisit.Judge(rules: config.rules, siteRadiusM: config.site.radius, fenceRadiusM: config.fence.radius,
                                                          venueHasBeacons: hasBeacons, startedAt: now),
                                  gate: VenueVisit.FixGate(lat: config.fence.lat, lng: config.fence.lng, radiusM: config.fence.radius, t: now))
            session.id = VenueSessionFile.newId(dimension: config.dimension, now: now)
            do {
                session.writer = try VenueSessionFile.Writer(dir: dir, id: session.id)
            } catch {
                store.log("a session file could not be opened: \(error)")
                UIDevice.current.isBatteryMonitoringEnabled = monitoringWas
                return false
            }
            session.account = VenueVisit.string(VenueTrackingStore.venue(desired, config.dimension) ?? [:], "account")
            session.startedAt = now
            session.batteryAtStart = VenueTracker.batteryLevel()
            self.session = session
            write(header(session, desired, state, manager))
            store.log("session \(session.id) begun at \(config.name) (\(reason))")
            taken = session
        }
        guard let session = taken else { return false }

        batteryMonitoringWas = monitoringWas
        stopLooking()
        session.lastHeartbeatElapsed = VenueTracker.elapsed()
        startFixes()
        startBeacons()
        if beacon {
            apply(session.judge.onBeacon(now))
        }
        if let fix = fix, self.session != nil {
            onFix(fix)
        }
        if self.session != nil {
            persist()
            tickTimer?.invalidate()
            tickTimer = Timer.scheduledTimer(withTimeInterval: VenueTracker.tickS, repeats: true) { [weak self] _ in
                self?.tick()
            }
            notifyChanged()
        }
        return true
    }

    private func noteRefused(_ config: VenueTrackingConfig, _ reason: String, _ what: String) {
        store.log("no session of \(config.name) (\(reason)): the \(what == "location" ? "location is not allowed" : "location is approximate")")
        var state = store.state()
        state["refused"] = ["at": VenueTracker.wall(), "reason": reason, "error": what] as [String: Any]
        store.writeState(state)
    }

    private func header(_ session: Session, _ desired: [String: Any], _ state: [String: Any], _ manager: CLLocationManager) -> [String: Any] {
        var header: [String: Any] = [
            "k": "session",
            "v": VenueVisit.Records.version,
            "id": session.id,
            "t": session.startedAt,
            "venue": session.config.dimension,
            "name": session.config.name,
            "platform": "ios",
            "reason": session.reason,
            "account": session.account,
            "app_instance": VenueVisit.string(desired, "app_instance"),
            "device": ["model": VenueTracker.deviceModel(), "os": "iOS " + UIDevice.current.systemVersion],
            "tz_offset_min": TimeZone.current.secondsFromGMT(for: Date(timeIntervalSince1970: Double(session.startedAt) / 1000)) / 60,
            "config": session.config.toJson(),
            "standing": [
                "background_location": manager.authorizationStatus == .authorizedAlways,
                "bluetooth": CLLocationManager.isRangingAvailable() ? "on" : "off",
                "location_services": locationServicesOn,
                "notifications": notificationsAllowed,
                "power_save": ProcessInfo.processInfo.isLowPowerModeEnabled,
                "background_refresh": UIApplication.shared.backgroundRefreshStatus == .available,
                "background_mode": VenueTracker.hasLocationBackgroundMode(),
                "battery": session.batteryAtStart,
            ] as [String: Any],
        ]
        if let app = desired["app"] as? [String: Any] {
            header["app"] = app
        }
        // What iOS noticed before the app was opened: the visit began there, unrecorded until now.
        if let arrival = state["arrival"] as? [String: Any], VenueVisit.string(arrival, "dimension") == session.config.dimension {
            var noted = VenueTracker.arrivalAsWritten(arrival)
            noted.removeValue(forKey: "dimension")
            header["arrival"] = noted
        }
        return header
    }

    // MARK: - Fixes

    /// The fixes, and what keeps the app running for them: the location manager's standard
    /// updates at the GPS's accuracy, never paused. They go on while the phone is still, which is
    /// what keeps iOS from suspending the app under a visitor who stands - the live updates alone
    /// stop for a still phone, and then nothing was recorded, heard or sent for as long as the
    /// visitor stood (a quarter of an iPhone's visit on 2026-11-16, up to fourteen minutes at a
    /// time). From iOS 17 a CLBackgroundActivitySession - first, so that a process iOS relaunched
    /// in the background may start updates - and the live updates run beside them: what has iOS
    /// relaunch the app when the process is killed under a session, and Core Location's word on
    /// whether the phone is still and why fixes are not coming. Their locations are the same Core
    /// Location's, so the standard updates alone carry the fixes.
    private func startFixes() {
        guard let manager = manager, session != nil else { return }
        let background = VenueTracker.hasLocationBackgroundMode()
        if !background {
            store.log("no location background mode in the app's Info.plist: the session lives only while the app is in front")
        }
        streamGeneration += 1
        if #available(iOS 17.0, *), background {
            backgroundSession = CLBackgroundActivitySession()
        }
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        if background {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
        }
        manager.startUpdatingLocation()
        standardStream = true
        if #available(iOS 17.0, *) {
            let generation = streamGeneration
            updatesTask = Task { @MainActor [weak self] in
                do {
                    for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                        guard let self = self, self.streamGeneration == generation, self.session != nil else { break }
                        self.onLiveUpdate(update)
                    }
                } catch {
                    if let self = self, self.streamGeneration == generation {
                        self.fixesFailed("\(error)")
                    }
                }
            }
        }
        streamName = "standard"
        write(event("fix_mode", ["mode": streamName, "background": background]))
    }

    private func stopFixes() {
        streamGeneration += 1
        updatesTask?.cancel()
        updatesTask = nil
        if standardStream, let manager = manager {
            manager.stopUpdatingLocation()
            if VenueTracker.hasLocationBackgroundMode() {
                manager.allowsBackgroundLocationUpdates = false
            }
            standardStream = false
        }
        if #available(iOS 17.0, *), let held = backgroundSession as? CLBackgroundActivitySession {
            held.invalidate()
        }
        backgroundSession = nil
        streamName = "none"
    }

    private func fixesFailed(_ why: String) {
        store.log("the fixes stopped: \(why)")
        write(event("fixes_failed", ["why": why]))
        flush()
    }

    @available(iOS 17.0, *)
    private func onLiveUpdate(_ update: CLLocationUpdate) {
        guard let session = session else { return }
        let now = VenueTracker.wall()
        alive(now)
        session.updatesSinceHeartbeat += 1
        var stationary = false
        var said: [String] = []
        if #available(iOS 18.0, *) {
            stationary = update.stationary
            if update.authorizationDenied { said.append("authorization_denied") }
            if update.authorizationDeniedGlobally { said.append("authorization_denied_globally") }
            if update.authorizationRestricted { said.append("authorization_restricted") }
            if update.insufficientlyInUse { said.append("insufficiently_in_use") }
            if update.locationUnavailable { said.append("location_unavailable") }
            if update.accuracyLimited { said.append("accuracy_limited") }
            if update.serviceSessionRequired { said.append("service_session_required") }
            if update.authorizationRequestInProgress { said.append("authorization_request_in_progress") }
        } else {
            stationary = update.isStationary   // iOS 17's name for it
        }
        if stationary != session.stationary {
            // The live updates stop while the phone does not move, and say so: the phone's motion
            // sensors' word, which the tick has the judge stand on the last fix by (the standard
            // updates, which carry the fixes, go on regardless).
            session.stationary = stationary
            write(event(stationary ? "stationary" : "moving"))
        }
        let diagnostics = said.joined(separator: ",")
        if diagnostics != session.diagnostics {
            session.diagnostics = diagnostics
            write(event("fix_diagnostics", ["diag": diagnostics.isEmpty ? "ok" : diagnostics, "app_front": appActive]))
            store.log("session \(session.id): Core Location says [\(diagnostics.isEmpty ? "ok" : diagnostics)], app \(VenueTracker.appStateName())")
        }
        // Its location, if any, is the standard updates' too: they carry the fixes (startFixes).
        tickIfDue()
    }

    private func onFix(_ location: CLLocation) {
        guard let session = session else { return }
        let now = VenueTracker.wall()
        let at = VenueTracker.millis(location.timestamp)
        // Core Location hands over the fix it last had before the new ones: where the phone was.
        guard location.horizontalAccuracy >= 0, now - at <= VenueTracker.staleFixMs else {
            session.staleSinceHeartbeat += 1
            return
        }
        alive(now)
        session.fixesSeen += 1
        session.fixesSinceHeartbeat += 1
        let lat = location.coordinate.latitude
        let lng = location.coordinate.longitude
        let accuracy = location.horizontalAccuracy
        let distance = session.config.site.distance(toLat: lat, lng: lng)
        let run = session.gate.run
        let runSince = session.gate.runSince
        if !session.gate.offer(now, lat: lat, lng: lng, accuracyM: accuracy) {
            // A position the phone could not have reached: a faked satellite signal. Neither
            // written nor evidence - only said, once a run, with how far off it put the phone.
            session.fixesImplausible += 1
            session.implausibleSinceHeartbeat += 1
            session.sampler.pass()
            if run == 0 {
                write(event("fixes_implausible", ["d": Int(distance.rounded()), "acc": VenueVisit.Records.round(accuracy, 10)]))
                store.log("session \(session.id): a fix \(Int((distance / 1000).rounded())) km from the venue, +-\(Int(accuracy.rounded())) m, "
                          + "the phone could not have reached - turned away, and those after it until one can be believed")
            }
            apply(session.judge.onImplausibleFix(now))
            tickIfDue()
            return
        }
        if run > 0 {
            write(event("fixes_plausible", ["n": run, "since": runSince]))
            store.log("session \(session.id): a fix believed again after \(run) turned away over \((now - runSince) / 1000) s")
        }
        lastFix = location
        let fenceDistance = session.config.fence.distance(toLat: lat, lng: lng)
        let skipped: Int
        if fenceDistance > session.config.fence.radius {
            // Beyond the fence - past the venue's region - the judge hears of the fix and the
            // file does not: where a visitor goes once outside it is none of the visit's business.
            session.sampler.pass()
            skipped = -1
        } else {
            skipped = session.sampler.offer(now, lat: lat, lng: lng)
        }
        if skipped >= 0 {
            var record = VenueVisit.Records.fix(min(at, now), lat: lat, lng: lng, accuracyM: accuracy, skipped: skipped, source: "cl")
            record["d"] = Int(distance.rounded())
            if location.verticalAccuracy > 0 {
                record["alt"] = VenueVisit.Records.round(location.altitude, 10)
                record["vacc"] = VenueVisit.Records.round(location.verticalAccuracy, 10)
            }
            if location.speed >= 0 {
                record["spd"] = VenueVisit.Records.round(location.speed, 100)
            }
            if location.course >= 0 {
                record["brg"] = Int(location.course.rounded())
            }
            if let floor = location.floor {
                record["floor"] = floor.level   // where Apple has the building mapped
            }
            if let source = location.sourceInformation, source.isSimulatedBySoftware {
                record["mock"] = true
            }
            write(record)
            session.fixes += 1
        }
        apply(session.judge.onFix(now, distanceM: distance, fenceDistanceM: fenceDistance, accuracyM: accuracy))
        tickIfDue()
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        if session != nil {
            if standardStream {
                for location in locations {
                    onFix(location)
                }
            }
            return
        }
        guard last.horizontalAccuracy >= 0, VenueTracker.wall() - VenueTracker.millis(last.timestamp) <= VenueTracker.staleFixMs else { return }
        lastFix = last
        if let sample = arrivalSample {
            sample.fix = last
        }
        guard looking else { return }
        var nearest = ""
        var nearestDistance = Double.greatestFiniteMagnitude
        for config in lookVenues {
            let distance = config.site.distance(toLat: last.coordinate.latitude, lng: last.coordinate.longitude)
            if last.horizontalAccuracy <= VenueTracker.lookAccuracyM && distance <= config.site.radius + min(last.horizontalAccuracy, 100) {
                store.log("at \(config.name): a fix \(Int(distance.rounded())) m from its middle, +-\(Int(last.horizontalAccuracy.rounded())) m")
                found(config, fix: last, beacon: false)
                return
            }
            if distance < nearestDistance {
                nearestDistance = distance
                nearest = config.name
            }
        }
        lookSaw = "a fix +-\(Int(last.horizontalAccuracy.rounded())) m, \(Int(nearestDistance.rounded())) m from the middle of \(nearest)"
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A fix that could not be had yet (kCLErrorLocationUnknown) is no failure; the rest is worth a line.
        if (error as? CLError)?.code != .locationUnknown {
            store.log("location failed: \(error.localizedDescription)")
            if session != nil {
                write(event("fixes_failed", ["why": error.localizedDescription]))
            }
        }
    }

    // MARK: - Beacons

    /// Ranging of the venue's UUID, asked for the length of the session. Nothing is written until
    /// it answers: a window is what ranging said, never what was asked of it.
    private func startBeacons() {
        guard let manager = manager, let session = session, rangingUuid == nil else { return }
        guard let uuid = session.config.uuid else {
            bleStatus = "none"
            return
        }
        guard CLLocationManager.isRangingAvailable() else {
            setBleStatus("off")
            return
        }
        manager.startRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: uuid))
        rangingUuid = uuid
        lastRangeElapsed = -1
        if bleStatus != "on" {
            bleStatus = "starting"
        }
    }

    private func stopBeacons(_ why: String) {
        if let uuid = rangingUuid {
            manager?.stopRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: uuid))
            rangingUuid = nil
        }
        if let session = session, session.windows.listening {
            stopWindows(at: VenueTracker.wall(), status: why)
        } else {
            setBleStatus(why)
        }
        lastRangeElapsed = -1
    }

    public func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon], satisfying constraint: CLBeaconIdentityConstraint) {
        if let session = session, session.config.uuid == constraint.uuid {
            onRanged(session, beacons)
            return
        }
        if let sample = arrivalSample, sample.config.uuid == constraint.uuid {
            for beacon in beacons where beacon.rssi != 0 {
                let key = (beacon.major.intValue << 16) | (beacon.minor.intValue & 0xFFFF)
                sample.beacons[key] = max(sample.beacons[key] ?? Int.min, beacon.rssi)
            }
        }
        if looking, let config = lookVenues.first(where: { $0.uuid == constraint.uuid }),
           let heard = beacons.first(where: { $0.rssi != 0 }) {
            store.log("at \(config.name): its beacon \(heard.major):\(heard.minor) heard at \(heard.rssi) dBm")
            found(config, fix: nil, beacon: true)
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailRangingFor constraint: CLBeaconIdentityConstraint, error: Error) {
        guard let session = session, session.config.uuid == constraint.uuid else { return }
        store.log("ranging failed: \(error.localizedDescription)")
        rangingUuid = nil
        let code = (error as NSError).code
        if session.windows.listening {
            stopWindows(at: VenueTracker.wall(), status: "ranging_failed_\(code)")
        } else {
            setBleStatus("ranging_failed_\(code)")
        }
        flush()   // the heartbeat asks again
    }

    /// One answer of the ranging: the venue's beacons heard in the last second, or none.
    private func onRanged(_ session: Session, _ beacons: [CLBeacon]) {
        let now = VenueTracker.wall()
        alive(now)
        rangingAnswered(session, now)
        session.rangesSinceHeartbeat += 1
        var closed: [VenueVisit.BleWindows.Window] = []
        var heard = false
        // A beacon listed with no strength was not heard in this second; iOS keeps it listed a while.
        for beacon in beacons where beacon.rssi != 0 {
            session.windows.add(now, major: beacon.major.intValue, minor: beacon.minor.intValue, rssi: beacon.rssi, into: &closed)
            session.adverts += 1
            session.advertsSinceHeartbeat += 1
            heard = true
        }
        // The answer itself, heard or not, is the listening up to now.
        session.windows.drain(now, into: &closed)
        writeWindows(closed)
        if heard {
            apply(session.judge.onBeacon(now))
        }
        tickIfDue()
    }

    /// Ranging answered. When it had not for a while, the listening ended with its last answer
    /// and begins again with this one.
    private func rangingAnswered(_ session: Session, _ now: Int64) {
        let elapsed = VenueTracker.elapsed()
        if session.windows.listening && lastRangeElapsed >= 0 && elapsed - lastRangeElapsed > VenueTracker.rangingSilentMs {
            stopWindows(at: lastRangeWall, status: "silent")
        }
        lastRangeElapsed = elapsed
        lastRangeWall = now
        if !session.windows.listening {
            session.windows.start(now)
            setBleStatus("on")
            updateListening()
        }
    }

    private func stopWindows(at: Int64, status: String) {
        guard let session = session else { return }
        var closed: [VenueVisit.BleWindows.Window] = []
        session.windows.stop(at, into: &closed)
        writeWindows(closed)
        session.judge.onListening(false)
        setBleStatus(status)
    }

    /// Whether silence counts for the judge: ranging is answering, and the app is in front. With
    /// the app behind or the phone locked iOS may go on answering with nothing in it whatever is
    /// there - that is what the device tests are to say - so there a beacon heard is still the
    /// venue, and none heard is nothing.
    private func updateListening() {
        guard let session = session else { return }
        session.judge.onListening(session.windows.listening && appActive)
    }

    private func writeWindows(_ windows: [VenueVisit.BleWindows.Window]) {
        guard let session = session else { return }
        for window in windows {
            var record = VenueVisit.Records.ble(window)
            if !appActive {
                record["bg"] = true
            }
            if locked {
                record["locked"] = true
            }
            write(record)
            session.bleWindows += 1
        }
    }

    /// on, or why not: none (the venue has no beacons), starting (asked, not answered yet), off
    /// (Bluetooth), silent (ranging stopped answering), a failure, the session's end. Written when it changes.
    private func setBleStatus(_ status: String) {
        if status == bleStatus {
            return
        }
        bleStatus = status
        if session != nil {
            var extra: [String: Any] = ["app_front": appActive, "locked": locked]
            if status == "on" {
                extra["mode"] = "ranging"
            } else {
                extra["why"] = status
            }
            write(event(status == "on" ? "ble_on" : "ble_off", extra))
        }
    }

    // MARK: - Time

    private func tickIfDue() {
        if session != nil && VenueTracker.elapsed() - lastTickElapsed >= VenueTracker.tickMs {
            tick()
        }
    }

    /// Every few seconds while the process runs, and with every fix and ranging answer when it
    /// had been asleep: the judge is asked what time concludes, ranging that stopped answering is
    /// noticed, the heartbeat and the state go out when they are due, and what has been written of
    /// a confirmed visit is sent when that is due.
    private func tick() {
        guard let session = session else { return }
        let now = VenueTracker.wall()
        let elapsed = VenueTracker.elapsed()
        lastTickElapsed = elapsed
        let woke = alive(now)

        if session.windows.listening && lastRangeElapsed >= 0 && elapsed - lastRangeElapsed > VenueTracker.rangingSilentMs {
            stopWindows(at: lastRangeWall, status: "silent")
            store.log("session \(session.id): ranging stopped answering, app \(VenueTracker.appStateName())\(locked ? ", locked" : "")")
        }
        if session.stationary {
            // Core Location said the phone stopped moving, and sends no fixes until it moves again:
            // the last fix stands, observed again now - or a visitor sitting down would never be
            // confirmed, and one sitting long would be lost.
            apply(session.judge.onStationary(now), stationary: true)
            guard self.session != nil else { return }
        }
        if !woke {
            // After a stretch nothing was delivered in, what woke the process is still on its way
            // in: time's own conclusions wait for the next tick.
            apply(session.judge.tick(now))
            guard self.session != nil else { return }   // the judge ended it
        }

        if elapsed - session.lastHeartbeatElapsed >= VenueTracker.heartbeatMs {
            heartbeat(session, now, elapsed)
        }
        if self.session != nil && elapsed - session.lastPersistElapsed >= VenueTracker.persistMs {
            persist()
        }
        flush()
        if self.session === session {
            sendLiveIfDue(session, elapsed)
        }
    }

    /// What has been written of a visit the judge confirmed goes to the backend while the visit
    /// goes on, every `upload_interval_s` from the last try - after the tick's flush, so the file
    /// holds every record so far, and with the session and its confirmation read here on the main
    /// thread. Never before the confirmation: nothing of a phone never shown to be at the venue leaves it.
    private func sendLiveIfDue(_ session: Session, _ elapsed: Int64) {
        guard VenueUpload.liveDue(confirmedAt: session.judge.confirmedAt, lastTryElapsed: session.lastLiveElapsed,
                                  elapsed: elapsed, intervalS: session.config.sampling.uploadIntervalS) else { return }
        session.lastLiveElapsed = elapsed
        VenueUploader.shared.kickLive(session.id)
    }

    /// Something reached the tracker. When nothing had for long, that stretch is written as a gap:
    /// nothing was sampled in it. Answers whether it was.
    @discardableResult
    private func alive(_ now: Int64) -> Bool {
        guard let session = session else { return false }
        let elapsed = VenueTracker.elapsed()
        var woke = false
        if session.lastEventElapsed >= 0 && elapsed - session.lastEventElapsed > VenueTracker.silenceGapMs {
            woke = true
            let gap = elapsed - session.lastEventElapsed
            var record = VenueVisit.Records.gap(now, from: session.lastEventAt, to: now, sensor: "all", why: "nothing_delivered")
            if session.stationary {
                record["stationary"] = true   // Core Location had said the phone was not moving
            }
            write(record)
            session.gapsMs += gap
            session.sampler.reset()
            store.log("nothing was delivered for \(gap / 1000) s - the app was suspended, or the phone held the samples back"
                      + (session.stationary ? " (it had been reported stationary)" : ""))
        }
        session.lastEventElapsed = elapsed
        session.lastEventAt = now
        return woke
    }

    private func heartbeat(_ session: Session, _ now: Int64, _ elapsed: Int64) {
        guard let manager = manager else { return }
        session.lastHeartbeatElapsed = elapsed
        var record: [String: Any] = [
            "k": "hb",
            "t": now,
            "state": session.judge.state,
            "fixes": session.fixesSinceHeartbeat,
            // Fixes passed over as older than half a minute when they came, and - with the live
            // updates - how many updates came at all, with a fix in them or not.
            "stale": session.staleSinceHeartbeat,
            // Fixes the gate turned away: positions the phone could not have reached.
            "implausible": session.implausibleSinceHeartbeat,
            "updates": session.updatesSinceHeartbeat,
            "adverts": session.advertsSinceHeartbeat,
            // Ranging's answers in the minute, sixty when it runs: the count the screen-off question is read from.
            "ranges": session.rangesSinceHeartbeat,
            "ble": bleStatus,
            "fix_mode": streamName,
            "bat": VenueTracker.batteryLevel(),
            "chg": VenueTracker.charging(),
            "locked": locked,
            "power_save": ProcessInfo.processInfo.isLowPowerModeEnabled,
            "app_front": appActive,
            "stationary": session.stationary,
        ]
        if !appActive {
            // What iOS still gives the app in the background: no limit (-1) while the location session holds.
            let left = UIApplication.shared.backgroundTimeRemaining
            record["bg_left"] = left > 100_000 ? -1 : Int(left.rounded())
        }
        write(record)
        session.fixesSinceHeartbeat = 0
        session.staleSinceHeartbeat = 0
        session.implausibleSinceHeartbeat = 0
        session.updatesSinceHeartbeat = 0
        session.advertsSinceHeartbeat = 0
        session.rangesSinceHeartbeat = 0

        // What the visitor took away under a running session ends it, with the reason.
        let status = manager.authorizationStatus
        if status != .authorizedWhenInUse && status != .authorizedAlways {
            endByRequest("permission", "location")
        } else if manager.accuracyAuthorization != .fullAccuracy {
            endByRequest("permission", "precise_location")
        } else if session.config.uuid != nil {
            let available = CLLocationManager.isRangingAvailable()
            if !available && rangingUuid != nil {
                stopBeacons("off")
            } else if available && rangingUuid == nil {
                startBeacons()
            }
        }
    }

    // MARK: - The judge's word

    /// `stationary` marks a change that came of the last fix standing for a phone said to be still.
    private func apply(_ change: VenueVisit.Change?, stationary: Bool = false) {
        guard let change = change, let session = session else { return }
        if change.what == VenueVisit.Change.ended {
            endSession(change)
            return
        }
        var record = VenueVisit.Records.change(change, state: session.judge.state)
        if stationary {
            record["stationary"] = true
        }
        write(record)
        store.log("session \(session.id): \(change)")
        persist()
        notifyChanged()
    }

    /// Ends the running session for a reason that is not the judge's.
    private func endByRequest(_ why: String, _ by: String) {
        if let session = session {
            endSession(session.judge.endNow(VenueTracker.wall(), why: why, by: by))
        }
    }

    private func endSession(_ end: VenueVisit.Change) {
        guard let session = session else { return }
        tickTimer?.invalidate()
        tickTimer = nil
        stopFixes()
        if rangingUuid != nil || session.windows.listening {
            stopBeacons(end.why)
        }
        let judge = session.judge
        let batteryEnd = VenueTracker.batteryLevel()
        write([
            "k": "end",
            "t": end.at,
            "why": end.why,
            "by": end.by,
            "confirmed_at": judge.confirmedAt,
            "confirmed_by": judge.confirmedBy,
            "last_inside_at": judge.lastInsideAt,
            "last_beacon_at": judge.lastBeaconAt,
            "left_at": judge.leavingSince,
            "fixes": session.fixes,
            "fixes_seen": session.fixesSeen,
            "fixes_implausible": session.fixesImplausible,
            "ble_windows": session.bleWindows,
            "adverts": session.adverts,
            "gaps_ms": session.gapsMs,
            "restarts": session.restarts,
            "battery_start": session.batteryAtStart,
            "battery_end": batteryEnd,
        ])
        let bytes = session.writer?.bytes ?? 0
        do {
            try session.writer?.close()
        } catch {
            store.log("session \(session.id) could not be closed: \(error)")
        }
        session.writer = nil
        UIDevice.current.isBatteryMonitoringEnabled = batteryMonitoringWas

        var kept = true
        if end.why == "not_confirmed" {
            // The phone was never shown to be at the venue: nothing of where it was is kept.
            kept = !VenueSessionFile.remove(store.sessionsDirectory, session.id)
        }
        store.log("session \(session.id) ended: \(end.why) by \(end.by) after \((end.at - session.startedAt) / 1000) s - "
                  + "\(session.fixes) of \(session.fixesSeen) fix(es), "
                  + (session.fixesImplausible > 0 ? "\(session.fixesImplausible) turned away as implausible, " : "")
                  + "\(session.adverts) beacon report(s) in \(session.bleWindows) window(s), "
                  + "\(session.gapsMs / 1000) s unrecorded, \(session.restarts) restart(s), battery \(session.batteryAtStart) -> \(batteryEnd) %, "
                  + String(format: "%.1f", Double(bytes) / 1024.0) + " KB" + (kept ? "" : ", not kept"))

        var state = store.state()
        state.removeValue(forKey: "session")
        state["last_session"] = [
            "id": session.id, "dimension": session.config.dimension, "why": end.why, "by": end.by, "at": end.at, "kept": kept,
        ] as [String: Any]
        if end.why == "departed",
           VenueVisit.string((state["arrival"] as? [String: Any]) ?? [:], "dimension") == session.config.dimension {
            state.removeValue(forKey: "arrival")
        }
        store.writeState(state)

        self.session = nil
        bleStatus = "none"
        notifyChanged()
        if kept {
            // The visit is over and its file whole: sent now, while iOS still lets the process run.
            VenueUploader.shared.kick("session \(session.id) ended", activeId: nil)
        }
        // With the app still in front the look goes on - for another venue, or this one again
        // once the visitor enables it.
        if appActive && started && end.why != "disabled" {
            lookAgain()
        }
    }

    // MARK: - The file and the state

    private func event(_ name: String, _ extra: [String: Any] = [:]) -> [String: Any] {
        var record = VenueVisit.Records.event(VenueTracker.wall(), name)
        for (key, value) in extra {
            record[key] = value
        }
        return record
    }

    private func write(_ record: [String: Any]) {
        guard let session = session, let writer = session.writer else { return }
        writer.write(record)
        session.lastRecordAt = max(session.lastRecordAt, VenueSessionFile.lastTime(record))
    }

    private func flush() {
        guard let session = session, let writer = session.writer else { return }
        do {
            try writer.flush()
        } catch {
            store.log("session \(session.id) could not be written: \(error)")
        }
    }

    private func sessionRecord(_ session: Session) -> [String: Any] {
        [
            "id": session.id,
            "dimension": session.config.dimension,
            "name": session.config.name,
            "reason": session.reason,
            "account": session.account,
            "started_at": session.startedAt,
            "last_record_at": max(session.lastRecordAt, session.lastEventAt),
            "alive_at": VenueTracker.wall(),
            "fixes": session.fixes,
            "fixes_seen": session.fixesSeen,
            "fixes_implausible": session.fixesImplausible,
            "ble_windows": session.bleWindows,
            "adverts": session.adverts,
            "gaps_ms": session.gapsMs,
            "restarts": session.restarts,
            "battery_at_start": session.batteryAtStart,
            "ble": bleStatus,
            "last_evidence_at": session.judge.lastEvidenceAt,
            "last_beacon_at": session.judge.lastBeaconAt,
            "judge": session.judge.toJson(),
            "gate": session.gate.toJson(),
        ]
    }

    /// The session as the next process would need it, and the page sees it.
    private func persist() {
        guard let session = session else { return }
        session.lastPersistElapsed = VenueTracker.elapsed()
        do {
            try session.writer?.sync()
        } catch {
            store.log("session \(session.id) could not be synced: \(error)")
        }
        var state = store.state()
        state["session"] = sessionRecord(session)
        state.removeValue(forKey: "refused")
        store.writeState(state)
    }

    // MARK: - Helpers

    private static func wall() -> Int64 {
        millis(Date())
    }

    private static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    /// Milliseconds on a clock that goes on counting while the phone sleeps and the app is
    /// suspended: what a stretch nothing was delivered in is measured on.
    private static func elapsed() -> Int64 {
        Int64(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) / 1_000_000)
    }

    /// A noted arrival as it is written out: read back from the state its fix is doubles again,
    /// which JSON would spell to seventeen digits.
    private static func arrivalAsWritten(_ arrival: [String: Any]) -> [String: Any] {
        var noted = arrival
        if var fix = noted["fix"] as? [String: Any] {
            for (key, scale) in [("lat", 1e6), ("lng", 1e6), ("acc", 10.0)] where fix[key] != nil {
                fix[key] = VenueVisit.Records.round(VenueVisit.number(fix, key, 0), scale)
            }
            noted["fix"] = fix
        }
        return noted
    }

    private static func hasLocationBackgroundMode() -> Bool {
        ((Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]) ?? []).contains("location")
    }

    private static func hasPurposeKey() -> Bool {
        ((Bundle.main.object(forInfoDictionaryKey: "NSLocationTemporaryUsageDescriptionDictionary") as? [String: Any]) ?? [:])[purposeKey] != nil
    }

    private static func appStateName() -> String {
        switch UIApplication.shared.applicationState {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "in background"
        @unknown default: return "?"
        }
    }

    private static func name(of status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "not_determined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorizedAlways: return "always"
        case .authorizedWhenInUse: return "when_in_use"
        @unknown default: return "?"
        }
    }

    /// The battery's level in percent, -1 when iOS does not say (the simulator).
    private static func batteryLevel() -> Int {
        let level = UIDevice.current.batteryLevel
        return level < 0 ? -1 : Int((level * 100).rounded())
    }

    private static func charging() -> Bool {
        let state = UIDevice.current.batteryState
        return state == .charging || state == .full
    }

    private static func deviceModel() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(validatingUTF8: $0) ?? "" }
        }
    }
}
