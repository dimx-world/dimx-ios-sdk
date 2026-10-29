import Foundation

/// What the parking detection knows of one venue, what it keeps of the car, how a fix is made,
/// and where all of it is stored - the iOS twin of android-app's ParkingConfig, ParkingRecord,
/// ParkingFix and ParkingStore, in one file. ParkingWatcher is the chain over them.

enum ParkingError: Error, CustomStringConvertible {
    case invalid(String)

    var description: String {
        switch self {
        case .invalid(let what): return what
        }
    }
}

/// One beacon of a venue's parking levels, as the config names it. A major of -1 matches any.
struct ParkingBeacon: Hashable {
    let major: Int
    let minor: Int
    /// The venue floor the beacon stands on; empty for outdoors or unknown.
    let floor: String
    let lat: Double
    let lng: Double

    var key: String { (major < 0 ? "*" : String(major)) + ":" + String(minor) }
}

struct ParkingFence {
    let lat: Double
    let lng: Double
    let radius: Double
}

/// The fence round the venue that wakes the app, the beacons that place the car, and the page
/// the saved spot opens on. The web page hands it over as JSON (WebViewCtrl's SET_PARKING_CONFIG)
/// and ParkingStore keeps it, so a process the system wakes for a region crossing reads it back
/// with no page up.
final class ParkingConfig: CustomStringConvertible {
    static let minFenceRadius = 100.0
    static let maxFenceRadius = 5000.0
    static let defaultMeasuredPower = -59
    private static let appUrlPrefix = "https://go.dimx.world/?dim="

    let dimension: String
    let name: String
    let fence: ParkingFence
    /// Nil when the config names no beacons: the fix is GPS alone (an open-air lot).
    let uuid: UUID?
    let measuredPower: Int
    let beacons: [ParkingBeacon]
    let appUrl: String

    private init(dimension: String, name: String, fence: ParkingFence, uuid: UUID?, measuredPower: Int,
                 beacons: [ParkingBeacon], appUrl: String) {
        self.dimension = dimension
        self.name = name
        self.fence = fence
        self.uuid = uuid
        self.measuredPower = measuredPower
        self.beacons = beacons
        self.appUrl = appUrl
    }

    /// The identifier of the circular region this config registers.
    var fenceIdentifier: String { "dimx-parking-" + dimension }
    /// The identifier of the beacon region, which wakes the app as the car enters the garage.
    var beaconsIdentifier: String { "dimx-parking-beacons-" + dimension }

    /// The configured beacon an advertisement names, or nil for one the config does not know.
    func find(major: Int, minor: Int) -> ParkingBeacon? {
        var wildcard: ParkingBeacon?
        for beacon in beacons where beacon.minor == minor {
            if beacon.major == major {
                return beacon
            }
            if beacon.major < 0 && wildcard == nil {
                wildcard = beacon
            }
        }
        return wildcard
    }

    static func parse(_ json: String) throws -> ParkingConfig {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else {
            throw ParkingError.invalid("not a JSON object")
        }
        return try from(root)
    }

    static func from(_ root: [String: Any]) throws -> ParkingConfig {
        let dimension = string(root, "dimension")
        guard !dimension.isEmpty, dimension.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw ParkingError.invalid("dimension must be an id of digits, not [\(dimension)]")
        }
        var name = string(root, "name")
        if name.isEmpty {
            name = "dimension " + dimension
        }

        guard let fenceJson = root["fence"] as? [String: Any] else {
            throw ParkingError.invalid("no fence")
        }
        let fenceLat = number(fenceJson, "lat", .nan)
        let fenceLng = number(fenceJson, "lng", .nan)
        guard validCoordinate(fenceLat, fenceLng) else {
            throw ParkingError.invalid("the fence needs a lat and a lng")
        }
        var radius = number(fenceJson, "radius", 300)
        guard radius > 0 else {
            throw ParkingError.invalid("the fence radius must be positive")
        }
        radius = max(minFenceRadius, min(maxFenceRadius, radius))

        var uuid: UUID?
        var measuredPower = defaultMeasuredPower
        var beacons: [ParkingBeacon] = []
        if let beaconsJson = root["beacons"] as? [String: Any] {
            let uuidText = string(beaconsJson, "uuid")
            if !uuidText.isEmpty {
                guard let parsed = UUID(uuidString: uuidText) else {
                    throw ParkingError.invalid("malformed beacon UUID [\(uuidText)]")
                }
                uuid = parsed
            }
            measuredPower = Int(number(beaconsJson, "measured_power", Double(defaultMeasuredPower)))
            guard measuredPower <= -20 && measuredPower >= -120 else {
                throw ParkingError.invalid("measured_power out of range [\(measuredPower)]")
            }
            for case let item as [String: Any] in (beaconsJson["items"] as? [Any]) ?? [] {
                let minor = Int(number(item, "minor", -1))
                let major = Int(number(item, "major", -1))
                let lat = number(item, "lat", .nan)
                let lng = number(item, "lng", .nan)
                guard minor >= 0 && minor <= 0xFFFF && major <= 0xFFFF else {
                    throw ParkingError.invalid("a beacon needs a minor (and an optional major) in 0..65535")
                }
                guard validCoordinate(lat, lng) else {
                    throw ParkingError.invalid("beacon \(major):\(minor) needs a lat and a lng")
                }
                beacons.append(ParkingBeacon(major: major, minor: minor, floor: string(item, "floor"), lat: lat, lng: lng))
            }
            if uuid == nil && !beacons.isEmpty {
                throw ParkingError.invalid("beacons without a uuid")
            }
        }

        var appUrl = string(root, "app_url")
        if appUrl.isEmpty {
            appUrl = appUrlPrefix + dimension + "&route=parking"
        } else if !appUrl.hasPrefix("https://") && !appUrl.hasPrefix("http://") {
            throw ParkingError.invalid("app_url must be an http(s) url")
        }

        return ParkingConfig(dimension: dimension, name: name, fence: ParkingFence(lat: fenceLat, lng: fenceLng, radius: radius),
                             uuid: uuid, measuredPower: measuredPower, beacons: beacons, appUrl: appUrl)
    }

    func toJson() -> [String: Any] {
        var root: [String: Any] = [
            "dimension": dimension,
            "name": name,
            "fence": ["lat": fence.lat, "lng": fence.lng, "radius": fence.radius],
            "app_url": appUrl,
        ]
        if let uuid = uuid {
            root["beacons"] = [
                "uuid": uuid.uuidString.lowercased(),
                "measured_power": measuredPower,
                "items": beacons.map { beacon -> [String: Any] in
                    var item: [String: Any] = ["minor": beacon.minor, "floor": beacon.floor, "lat": beacon.lat, "lng": beacon.lng]
                    if beacon.major >= 0 {
                        item["major"] = beacon.major
                    }
                    return item
                },
            ]
        }
        return root
    }

    var description: String {
        "\(name) [\(dimension)] fence \(Int(fence.radius)) m, \(beacons.count) beacon(s)" + (uuid != nil ? " under \(uuid!.uuidString.lowercased())" : "")
    }

    // MARK: - JSON helpers, shared by the record and the state

    static func validCoordinate(_ lat: Double, _ lng: Double) -> Bool {
        !lat.isNaN && !lng.isNaN && abs(lat) <= 90 && abs(lng) <= 180
    }

    static func string(_ object: [String: Any], _ key: String) -> String {
        if let value = object[key] as? String {
            return value
        }
        if let value = object[key] as? NSNumber {
            return value.stringValue
        }
        return ""
    }

    static func number(_ object: [String: Any], _ key: String, _ fallback: Double) -> Double {
        if let value = object[key] as? NSNumber {
            return value.doubleValue
        }
        if let value = object[key] as? String, let parsed = Double(value) {
            return parsed
        }
        return fallback
    }

    static func bool(_ object: [String: Any], _ key: String) -> Bool {
        (object[key] as? Bool) ?? ((object[key] as? NSNumber)?.boolValue ?? false)
    }

    static func jsonText(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    static func jsonObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return object as? [String: Any]
    }
}

/// Where the car was left: the one record the phone keeps, replaced by the next save and cleared
/// when the car drives out of the fence.
struct ParkingRecord: CustomStringConvertible {
    static let sourceBeacons = "beacons"
    static let sourceGps = "gps"

    let dimension: String
    let name: String
    /// The venue floor; empty for an open-air lot or an unknown level.
    let floor: String
    let lat: Double
    let lng: Double
    /// Metres: the radius of the circle the map draws.
    let accuracy: Double
    /// Milliseconds since the epoch, as the page and Android keep it.
    let savedAt: Int64
    let source: String
    /// What said the drive had ended: activity, test.
    let reason: String
    let beaconsUsed: Int
    let appUrl: String
    let detail: String

    func toJson() -> [String: Any] {
        [
            "dimension": dimension, "name": name, "floor": floor, "lat": lat, "lng": lng, "accuracy": accuracy,
            "saved_at": savedAt, "source": source, "reason": reason, "beacons_used": beaconsUsed, "app_url": appUrl,
            "detail": detail,
        ]
    }

    static func parse(_ root: [String: Any]?) -> ParkingRecord? {
        guard let root = root else { return nil }
        let dimension = ParkingConfig.string(root, "dimension")
        let lat = ParkingConfig.number(root, "lat", .nan)
        let lng = ParkingConfig.number(root, "lng", .nan)
        guard !dimension.isEmpty, ParkingConfig.validCoordinate(lat, lng) else {
            return nil
        }
        return ParkingRecord(dimension: dimension, name: ParkingConfig.string(root, "name"), floor: ParkingConfig.string(root, "floor"),
                             lat: lat, lng: lng, accuracy: ParkingConfig.number(root, "accuracy", 10),
                             savedAt: Int64(ParkingConfig.number(root, "saved_at", 0)), source: ParkingConfig.string(root, "source"),
                             reason: ParkingConfig.string(root, "reason"), beaconsUsed: Int(ParkingConfig.number(root, "beacons_used", 0)),
                             appUrl: ParkingConfig.string(root, "app_url"), detail: ParkingConfig.string(root, "detail"))
    }

    var description: String {
        "\(name)\(floor.isEmpty ? "" : " level \(floor)") at \(lat),\(lng) +-\(Int(accuracy.rounded())) m (\(source), \(beaconsUsed) beacon(s), \(reason))"
    }
}

/// Turns the beacon signals heard round the end of a drive into one place on one floor: the
/// strongest beacons, filtered, weighted into a centre, with a circle round it that says how sure.
/// The same arithmetic as Android's ParkingFix, so both phones answer alike. Times are seconds
/// since the epoch.
enum ParkingFix {
    static let window: TimeInterval = 15
    static let wideWindow: TimeInterval = 30
    static let minSamples = 3
    static let keep: TimeInterval = 60
    /// Path-loss exponent: free space is 2, a concrete garage with cars and pillars more.
    static let pathLoss = 2.5
    static let beaconsInFix = 3
    static let minAccuracy = 4.0
    static let maxAccuracy = 40.0

    struct Sample {
        let at: TimeInterval
        let rssi: Int
    }

    struct Heard {
        let beacon: ParkingBeacon
        let rssi: Double
        let samples: Int
        var distance: Double = 0
    }

    struct Result {
        let lat: Double
        let lng: Double
        let accuracy: Double
        let floor: String
        let beaconsUsed: Int
        let detail: String
    }

    /// What was heard, per configured beacon, over the last `keep` seconds. Main thread.
    final class Observations {
        private var byBeacon: [ParkingBeacon: [Sample]] = [:]
        private(set) var count = 0

        var isEmpty: Bool { byBeacon.isEmpty }
        var beacons: Int { byBeacon.count }

        func add(_ beacon: ParkingBeacon, at: TimeInterval, rssi: Int) {
            byBeacon[beacon, default: []].append(Sample(at: at, rssi: rssi))
            count += 1
            prune(at)
        }

        func prune(_ now: TimeInterval) {
            for (beacon, samples) in byBeacon {
                let kept = samples.filter { now - $0.at <= ParkingFix.keep }
                count -= samples.count - kept.count
                if kept.isEmpty {
                    byBeacon.removeValue(forKey: beacon)
                } else {
                    byBeacon[beacon] = kept
                }
            }
        }

        /// The beacons heard since `since`, each with the median RSSI of its samples in that time.
        func heard(since: TimeInterval) -> [Heard] {
            var heard: [Heard] = []
            for (beacon, samples) in byBeacon {
                let values = samples.filter { $0.at >= since }.map { $0.rssi }.sorted()
                if values.isEmpty {
                    continue
                }
                let n = values.count
                let median = n % 2 == 1 ? Double(values[n / 2]) : Double(values[n / 2 - 1] + values[n / 2]) / 2.0
                heard.append(Heard(beacon: beacon, rssi: median, samples: n))
            }
            return heard
        }
    }

    /// The log-distance path-loss model: metres from the calibrated RSSI at one metre and the RSSI heard.
    static func distance(measuredPower: Int, rssi: Double) -> Double {
        pow(10.0, (Double(measuredPower) - rssi) / (10.0 * pathLoss))
    }

    static func compute(_ config: ParkingConfig, _ observations: Observations, now: TimeInterval) -> Result? {
        var heard = observations.heard(since: now - window)
        if heard.reduce(0, { $0 + $1.samples }) < minSamples {
            heard = observations.heard(since: now - wideWindow)
        }
        if heard.isEmpty {
            return nil
        }
        for i in heard.indices {
            heard[i].distance = distance(measuredPower: config.measuredPower, rssi: heard[i].rssi)
        }
        heard.sort { $0.distance < $1.distance }
        let nearest = heard[0]
        let floor = nearest.beacon.floor
        var used: [Heard] = []
        for h in heard where h.beacon.floor == floor {
            used.append(h)
            if used.count == beaconsInFix {
                break
            }
        }

        // Local metres round the nearest beacon, so the weighting is Euclidean.
        let originLat = nearest.beacon.lat
        let originLng = nearest.beacon.lng
        let metresPerLat = 111_320.0
        let metresPerLng = 111_320.0 * cos(originLat * .pi / 180)
        var sumWeight = 0.0, east = 0.0, north = 0.0
        for h in used {
            let d = max(1.0, h.distance)
            let weight = 1.0 / (d * d)
            east += weight * (h.beacon.lng - originLng) * metresPerLng
            north += weight * (h.beacon.lat - originLat) * metresPerLat
            sumWeight += weight
        }
        east /= sumWeight
        north /= sumWeight

        var spread = 0.0
        for h in used {
            let d = max(1.0, h.distance)
            let weight = 1.0 / (d * d)
            let dx = (h.beacon.lng - originLng) * metresPerLng - east
            let dy = (h.beacon.lat - originLat) * metresPerLat - north
            spread += weight * (dx * dx + dy * dy)
        }
        spread = (spread / sumWeight).squareRoot()
        let accuracy = max(minAccuracy, min(maxAccuracy, nearest.distance + 0.5 * spread))

        let detail = used.map { String(format: "%@ %.0f dBm x%d ~%.1f m", $0.beacon.key, $0.rssi, $0.samples, $0.distance) }
            .joined(separator: ", ")
        return Result(lat: originLat + north / metresPerLat, lng: originLng + east / metresPerLng, accuracy: accuracy,
                      floor: floor, beaconsUsed: used.count, detail: detail)
    }
}

/// What the parking detection keeps on the device, in UserDefaults and a log file of its own under
/// Application Support/world.dimx: every event arrives in a process that may have just been
/// launched for it, so nothing lives in memory between them.
final class ParkingStore {
    private static let configsKey = "dimx.parking.configs"
    private static let recordKey = "dimx.parking.record"
    private static let stateKey = "dimx.parking.state"
    static let logFileName = "parking.log"
    private static let logMaxBytes = 256 * 1024
    private static let logKeepBytes = 128 * 1024
    private static let logTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    /// The chain's state between events.
    struct State {
        /// The dimension whose fence the device is inside, or empty.
        var inside = ""
        var enteredAt: TimeInterval = 0
        var vehicleActive = false
        var vehicleSince: TimeInterval = 0
        var vehicleExitAt: TimeInterval = 0
        /// A drive began after the save: the car is leaving, and the fence's exit clears the record.
        var leaving = false
        var lastSavedAt: TimeInterval = 0
        var lastDriveEndAt: TimeInterval = 0

        func toJson() -> [String: Any] {
            [
                "inside": inside, "entered_at": enteredAt, "vehicle_active": vehicleActive, "vehicle_since": vehicleSince,
                "vehicle_exit_at": vehicleExitAt, "leaving": leaving, "last_saved_at": lastSavedAt, "last_drive_end_at": lastDriveEndAt,
            ]
        }

        static func from(_ root: [String: Any]?) -> State {
            var state = State()
            guard let root = root else { return state }
            state.inside = ParkingConfig.string(root, "inside")
            state.enteredAt = ParkingConfig.number(root, "entered_at", 0)
            state.vehicleActive = ParkingConfig.bool(root, "vehicle_active")
            state.vehicleSince = ParkingConfig.number(root, "vehicle_since", 0)
            state.vehicleExitAt = ParkingConfig.number(root, "vehicle_exit_at", 0)
            state.leaving = ParkingConfig.bool(root, "leaving")
            state.lastSavedAt = ParkingConfig.number(root, "last_saved_at", 0)
            state.lastDriveEndAt = ParkingConfig.number(root, "last_drive_end_at", 0)
            return state
        }
    }

    private let defaults = UserDefaults.standard

    // MARK: configs

    func configs() -> [ParkingConfig] {
        var configs: [ParkingConfig] = []
        for (dimension, value) in configsJson() {
            guard let object = value as? [String: Any] else { continue }
            do {
                configs.append(try ParkingConfig.from(object))
            } catch {
                Logger.warn("Parking: dropping the stored config of [\(dimension)]: \(error)")
            }
        }
        return configs.sorted { $0.dimension < $1.dimension }
    }

    func config(_ dimension: String) -> ParkingConfig? {
        guard let object = configsJson()[dimension] as? [String: Any] else { return nil }
        return try? ParkingConfig.from(object)
    }

    func put(_ config: ParkingConfig) {
        var all = configsJson()
        all[config.dimension] = config.toJson()
        defaults.set(ParkingConfig.jsonText(all), forKey: ParkingStore.configsKey)
        defaults.synchronize()
    }

    func removeConfig(_ dimension: String) {
        var all = configsJson()
        all.removeValue(forKey: dimension)
        defaults.set(ParkingConfig.jsonText(all), forKey: ParkingStore.configsKey)
        defaults.synchronize()
    }

    private func configsJson() -> [String: Any] {
        guard let text = defaults.string(forKey: ParkingStore.configsKey), let object = ParkingConfig.jsonObject(text) else {
            return [:]
        }
        return object
    }

    // MARK: the record

    func record() -> ParkingRecord? {
        guard let text = defaults.string(forKey: ParkingStore.recordKey) else { return nil }
        return ParkingRecord.parse(ParkingConfig.jsonObject(text))
    }

    func setRecord(_ record: ParkingRecord?) {
        if let record = record {
            defaults.set(ParkingConfig.jsonText(record.toJson()), forKey: ParkingStore.recordKey)
        } else {
            defaults.removeObject(forKey: ParkingStore.recordKey)
        }
        defaults.synchronize()
    }

    // MARK: the state

    func state() -> State {
        guard let text = defaults.string(forKey: ParkingStore.stateKey) else { return State() }
        return State.from(ParkingConfig.jsonObject(text))
    }

    func setState(_ state: State) {
        defaults.set(ParkingConfig.jsonText(state.toJson()), forKey: ParkingStore.stateKey)
        defaults.synchronize()
    }

    // MARK: the log

    static func logFile() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("world.dimx", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(logFileName)
    }

    /// A line into the module's own log and the app's: stamped, kept to logMaxBytes.
    func log(_ line: String) {
        Logger.info("Parking: " + line)
        let file = ParkingStore.logFile()
        let stamped = ParkingStore.logTime.string(from: Date()) + " " + line + "\n"
        guard let bytes = stamped.data(using: .utf8) else { return }
        let path = file.path
        if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attributes[.size] as? NSNumber, size.intValue > ParkingStore.logMaxBytes,
           let whole = FileManager.default.contents(atPath: path) {
            // Keep the newest logKeepBytes, from the first whole line.
            var tail = whole.suffix(ParkingStore.logKeepBytes)
            if let newline = tail.firstIndex(of: UInt8(ascii: "\n")) {
                tail = tail[tail.index(after: newline)...]
            }
            try? Data(tail).write(to: file, options: .atomic)
        }
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(bytes)
            try? handle.close()
        } else {
            try? bytes.write(to: file, options: .atomic)
        }
    }
}
