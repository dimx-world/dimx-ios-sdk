import Foundation

/// What the venue tracking knows of a venue, what it keeps on the device and how a session's
/// file is written - the iOS twin of android-app's VenueTrackingConfig, VenueTrackingStore and
/// VenueSessionFile, in one file, with the same JSON throughout: a config the page hands either
/// phone, a session either phone wrote, read alike. VenueTracker is the chain over them, and
/// VenueVisit the judgement.

enum VenueTrackingError: Error, CustomStringConvertible {
    case invalid(String)

    var description: String {
        switch self {
        case .invalid(let what): return what
        }
    }
}

struct VenueCircle: Equatable {
    let lat: Double
    let lng: Double
    let radius: Double

    func distance(toLat otherLat: Double, lng otherLng: Double) -> Double {
        VenueVisit.distanceM(lat, lng, otherLat, otherLng)
    }

    func toJson() -> [String: Any] {
        ["lat": lat, "lng": lng, "radius": radius]
    }
}

/// How densely a visit is sampled; every value has a default and is held to a sane range.
struct VenueSampling {
    /// Seconds between fixes for the whole of a session. Android's request to its provider; Core
    /// Location gives fixes at its own pace - about one a second while moving - and this is recorded only.
    var fixIntervalS = 5
    var bleWindowS = 5
    /// Android's scan mode; iOS ranges at the rate Core Location gives.
    var bleMode = "low_latency"
    /// Seconds between the sendings of what has been recorded of a confirmed visit while it goes on (VenueUpload.live).
    var uploadIntervalS = 60

    static func from(_ json: [String: Any]?) -> VenueSampling {
        var sampling = VenueSampling()
        guard let json = json else { return sampling }
        sampling.fixIntervalS = clamp(VenueVisit.number(json, "fix_interval_s", Double(sampling.fixIntervalS)), 2, 300)
        sampling.bleWindowS = clamp(VenueVisit.number(json, "ble_window_s", Double(sampling.bleWindowS)), 2, 60)
        let mode = VenueVisit.string(json, "ble_mode").lowercased()
        if ["balanced", "low_power", "low_latency"].contains(mode) {
            sampling.bleMode = mode
        }
        sampling.uploadIntervalS = clamp(VenueVisit.number(json, "upload_interval_s", Double(sampling.uploadIntervalS)), 15, 600)
        return sampling
    }

    func toJson() -> [String: Any] {
        ["fix_interval_s": fixIntervalS, "ble_window_s": bleWindowS, "ble_mode": bleMode, "upload_interval_s": uploadIntervalS]
    }

    private static func clamp(_ value: Double, _ low: Int, _ high: Int) -> Int {
        Int(max(Double(low), min(Double(high), VenueVisit.roundHalfUp(value))))
    }
}

/// The fence that says the phone may be at the venue, the site that says it is (the circle the
/// venue's beacons cover, as the page makes it; the fence without one), the UUID its beacons
/// advertise under, how a visit is sampled and how long the judge waits. The page hands it over
/// as JSON (WebViewCtrl's SET_VENUE_TRACKING_CONFIG); only the dimension and the fence are
/// required. Every venue may start a visit by itself at its fence - whether this phone does is
/// the visitor's choice (VenueTrackingStore).
/// android-app's VenueTrackingConfig has the JSON spelled out.
final class VenueTrackingConfig: CustomStringConvertible {
    static let minFenceRadius = 100.0
    static let maxFenceRadius = 5000.0
    static let minSiteRadius = 20.0
    /// A dimension's app url is its path on the link host, /d/<id> (the engine's Url).
    private static let appUrlPrefix = "https://go.dimx.world/d/"

    let dimension: String
    let name: String
    let fence: VenueCircle
    let site: VenueCircle
    /// Nil when the venue has no beacons: fixes alone say where the phone is.
    let uuid: UUID?
    /// Where the beacons stand, as the page handed it (`beacons.places`): carried as it came into
    /// every session's header, so that the backend places what the phone heard by the layout the
    /// visit was recorded under; nothing here reads it. Nil for none.
    let beaconPlaces: [Any]?
    let sampling: VenueSampling
    let rules: VenueVisit.Rules
    /// The page's own gateway, through which a session is sent (VenueUpload) - what a confirmed
    /// visit has recorded every `upload_interval_s` while it goes on, and the rest when it is over;
    /// empty when the page named none - a visit is recorded as ever and nothing is sent. It goes
    /// into the session's header with the rest, so a session is sent to the environment it was recorded under.
    let uploadGateway: String

    private init(dimension: String, name: String, fence: VenueCircle, site: VenueCircle, uuid: UUID?, beaconPlaces: [Any]?,
                 sampling: VenueSampling, rules: VenueVisit.Rules, uploadGateway: String) {
        self.uploadGateway = uploadGateway
        self.dimension = dimension
        self.name = name
        self.fence = fence
        self.site = site
        self.uuid = uuid
        self.beaconPlaces = beaconPlaces
        self.sampling = sampling
        self.rules = rules
    }

    /// What the tap on the visit's notice opens: the dimension.
    var appUrl: String { VenueTrackingConfig.appUrlPrefix + dimension }

    /// The identifier of the circular region this venue registers, and of its beacon region.
    var fenceIdentifier: String { VenueTracker.fencePrefix + dimension }
    var beaconsIdentifier: String { VenueTracker.beaconsPrefix + dimension }

    static func parse(_ json: String) throws -> VenueTrackingConfig {
        guard let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw VenueTrackingError.invalid("not a JSON object")
        }
        return try from(root)
    }

    static func from(_ root: [String: Any]) throws -> VenueTrackingConfig {
        let dimension = VenueVisit.string(root, "dimension")
        guard !dimension.isEmpty, dimension.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw VenueTrackingError.invalid("dimension must be an id of digits, not [\(dimension)]")
        }
        var name = VenueVisit.string(root, "name")
        if name.isEmpty {
            name = "dimension " + dimension
        }
        guard let fence = try circle(root["fence"] as? [String: Any], "fence", minFenceRadius, maxFenceRadius) else {
            throw VenueTrackingError.invalid("no fence")
        }
        let site = try circle(root["site"] as? [String: Any], "site", minSiteRadius, maxFenceRadius) ?? fence

        var uuid: UUID?
        var places: [Any]?
        if let beacons = root["beacons"] as? [String: Any] {
            let text = VenueVisit.string(beacons, "uuid")
            if !text.isEmpty {
                guard let parsed = UUID(uuidString: text) else {
                    throw VenueTrackingError.invalid("malformed beacon UUID [\(text)]")
                }
                uuid = parsed
            }
            if uuid != nil, let placed = beacons["places"] as? [Any] {
                places = placed
            }
        }

        let gateway = VenueVisit.string((root["upload"] as? [String: Any]) ?? [:], "gateway")
        if !gateway.isEmpty && !gateway.hasPrefix("https://") && !gateway.hasPrefix("http://") {
            throw VenueTrackingError.invalid("upload.gateway must be an http(s) url")
        }
        return VenueTrackingConfig(dimension: dimension, name: name, fence: fence, site: site, uuid: uuid, beaconPlaces: places,
                                   sampling: VenueSampling.from(root["sampling"] as? [String: Any]),
                                   rules: VenueVisit.Rules.from(root["rules"] as? [String: Any]), uploadGateway: gateway)
    }

    private static func circle(_ json: [String: Any]?, _ what: String, _ minRadius: Double, _ maxRadius: Double) throws -> VenueCircle? {
        guard let json = json else { return nil }
        let lat = VenueVisit.number(json, "lat", .nan)
        let lng = VenueVisit.number(json, "lng", .nan)
        guard !lat.isNaN, !lng.isNaN, abs(lat) <= 90, abs(lng) <= 180 else {
            throw VenueTrackingError.invalid("the \(what) needs a lat and a lng")
        }
        let radius = VenueVisit.number(json, "radius", .nan)
        guard !radius.isNaN, radius > 0 else {
            throw VenueTrackingError.invalid("the \(what) needs a positive radius")
        }
        return VenueCircle(lat: lat, lng: lng, radius: max(minRadius, min(maxRadius, radius)))
    }

    func toJson() -> [String: Any] {
        var root: [String: Any] = [
            "dimension": dimension, "name": name, "fence": fence.toJson(), "site": site.toJson(),
            "sampling": sampling.toJson(), "rules": rules.toJson(),
        ]
        if let uuid = uuid {
            var beacons: [String: Any] = ["uuid": uuid.uuidString.lowercased()]
            if let places = beaconPlaces {
                beacons["places"] = places
            }
            root["beacons"] = beacons
        }
        if !uploadGateway.isEmpty {
            root["upload"] = ["gateway": uploadGateway]
        }
        return root
    }

    var description: String {
        "\(name) [\(dimension)] fence \(Int(fence.radius.rounded())) m, site \(Int(site.radius.rounded())) m"
            + (uuid != nil ? ", beacons under \(uuid!.uuidString.lowercased())" : ", no beacons")
    }
}

/// What the venue tracking keeps on the device, in files under Application Support/world.dimx -
/// excluded from backups, since where a visitor has been is not something a backup or a new
/// phone should carry, and readable from the first unlock on, since a session is written with
/// the phone locked. Two documents, as on Android: `desired` is what is wanted - the host's
/// switch, per venue its config and the visitor's choice - and `state` is what is: the running
/// session, an arrival noticed, a venue turned off. Read afresh at every use; nothing is held in
/// memory between the events, each of which may arrive in a process just launched for it.
final class VenueTrackingStore {
    static let logFileName = "venue-tracking.log"
    private static let logMaxBytes = 512 * 1024
    private static let logKeepBytes = 256 * 1024
    private static let logTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    let directory: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var dir = support.appendingPathComponent("world.dimx", isDirectory: true).appendingPathComponent("venue-tracking", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try dir.setResourceValues(values)
        } catch {
            Logger.warn("VenueTracking: the directory could not be made at [\(dir.path)]: \(error)")
        }
        directory = dir
    }

    var sessionsDirectory: URL {
        let dir = directory.appendingPathComponent("sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return dir
    }

    // MARK: desired

    func desired() -> [String: Any] { read("desired.json") }
    func writeDesired(_ desired: [String: Any]) { write("desired.json", desired) }

    static func hostEnabled(_ desired: [String: Any]) -> Bool {
        VenueVisit.bool(desired, "host_enabled")
    }

    /// One venue's entry of `desired`: {config, enabled, auto_start, account, since}.
    static func venue(_ desired: [String: Any], _ dimension: String) -> [String: Any]? {
        (desired["venues"] as? [String: Any])?[dimension] as? [String: Any]
    }

    static func dimensions(_ desired: [String: Any]) -> [String] {
        ((desired["venues"] as? [String: Any]) ?? [:]).filter { $0.value is [String: Any] }.keys.sorted()
    }

    static func config(_ desired: [String: Any], _ dimension: String) -> VenueTrackingConfig? {
        guard let json = venue(desired, dimension)?["config"] as? [String: Any] else { return nil }
        return try? VenueTrackingConfig.from(json)
    }

    /// Whether the venue is tracked: the host has the feature, the page configured the venue, the
    /// visitor enabled it - and has not turned it off since.
    static func tracked(_ desired: [String: Any], _ state: [String: Any], _ dimension: String) -> Bool {
        guard hostEnabled(desired), let venue = venue(desired, dimension), VenueVisit.bool(venue, "enabled"),
              config(desired, dimension) != nil else {
            return false
        }
        let offAt = VenueVisit.number((state["turned_off"] as? [String: Any]) ?? [:], dimension, 0)
        return offAt < VenueVisit.number(venue, "since", 0)
    }

    /// Whether the visitor asked for the venue to be watched for an arrival.
    static func autoStart(_ desired: [String: Any], _ dimension: String) -> Bool {
        guard let venue = venue(desired, dimension), config(desired, dimension) != nil else { return false }
        return VenueVisit.bool(venue, "auto_start")
    }

    // MARK: state

    func state() -> [String: Any] { read("state.json") }
    func writeState(_ state: [String: Any]) { write("state.json", state) }

    // MARK: uploads - what stands of each session's sending (VenueUpload)

    func uploads() -> [String: Any] { read("uploads.json") }
    func writeUploads(_ uploads: [String: Any]) { write("uploads.json", uploads) }

    // MARK: files

    private func read(_ name: String) -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: directory.appendingPathComponent(name).path),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return [:]
        }
        return object
    }

    /// Whole or not at all, and writable with the phone locked.
    private func write(_ name: String, _ json: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            try data.write(to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Logger.warn("VenueTracking: [\(name)] could not be written: \(error)")
        }
    }

    // MARK: the log

    var logFile: URL { directory.appendingPathComponent(VenueTrackingStore.logFileName) }

    /// A line into the module's own log and the app's: stamped, kept to logMaxBytes.
    func log(_ line: String) {
        Logger.info("VenueTracking: " + line)
        let file = logFile
        let stamped = VenueTrackingStore.logTime.string(from: Date()) + " " + line + "\n"
        guard let bytes = stamped.data(using: .utf8) else { return }
        let path = file.path
        if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attributes[.size] as? NSNumber, size.intValue > VenueTrackingStore.logMaxBytes,
           let whole = FileManager.default.contents(atPath: path) {
            // Keep the newest logKeepBytes, from the first whole line.
            var tail = whole.suffix(VenueTrackingStore.logKeepBytes)
            if let newline = tail.firstIndex(of: UInt8(ascii: "\n")) {
                tail = tail[tail.index(after: newline)...]
            }
            try? Data(tail).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(bytes)
            try? handle.close()
        } else {
            try? bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}

/// A session's file: one visit to one venue as the phone observed it, a JSON object per line,
/// appended as things happen and never rewritten - so whatever ends the process, what was
/// written stands, and at worst the last line is cut short and dropped by the reader. The first
/// line is the session's header (`k: "session"`), the last, once the visit is over, its end
/// (`k: "end"`). The format is env/venue-tracking/README.md's, the same as Android's.
enum VenueSessionFile {
    static let ext = ".jsonl"
    static let maxSessions = 40
    static let maxBytes: Int64 = 48 * 1024 * 1024
    static let maxAgeMs: Int64 = 30 * 24 * 3_600_000
    /// What one read hands the page: it crosses the bridge as a string.
    static let chunkBytes = 192 * 1024
    private static let tailBytes = 8 * 1024

    /// `<dimension>-<UTC time>-<four hex digits>`: sorts by venue and time, and is safe as a file name.
    static func newId(dimension: String, now: Int64) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "UTC")
        format.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return dimension + "-" + format.string(from: Date(timeIntervalSince1970: Double(now) / 1000)) + "-"
            + String(format: "%04x", Int.random(in: 0..<0x10000))
    }

    static func validId(_ id: String?) -> Bool {
        guard let id = id else { return false }
        return id.range(of: "^[0-9]{1,20}-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{4}$", options: .regularExpression) != nil
    }

    static func file(_ dir: URL, _ id: String) -> URL {
        dir.appendingPathComponent(id + ext)
    }

    /// Appends a session's records. One writer per file, on the main thread.
    final class Writer {
        private let handle: FileHandle
        private var buffer = Data()
        private(set) var written: Int64

        init(dir: URL, id: String) throws {
            let url = VenueSessionFile.file(dir, id)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil,
                                               attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            }
            handle = try FileHandle(forWritingTo: url)
            written = Int64(try handle.seekToEnd())
            // A process that died mid-line left the file without its last newline: the next record
            // starts on a line of its own, and the reader drops the torn one.
            if written > 0, let reader = try? FileHandle(forReadingFrom: url) {
                defer { try? reader.close() }
                if (try? reader.seek(toOffset: UInt64(written - 1))) != nil, let last = try? reader.read(upToCount: 1),
                   last.first != UInt8(ascii: "\n") {
                    buffer.append(UInt8(ascii: "\n"))
                }
            }
        }

        func write(_ record: [String: Any]) {
            buffer.append(contentsOf: VenueVisit.Records.line(record).utf8)
            buffer.append(UInt8(ascii: "\n"))
        }

        /// What was written since the last flush goes to the system; a process killed after this loses nothing.
        func flush() throws {
            if buffer.isEmpty {
                return
            }
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
            buffer.removeAll(keepingCapacity: true)
        }

        /// To the disk itself, against the phone losing power.
        func sync() throws {
            try flush()
            try handle.synchronize()
        }

        var bytes: Int64 { written + Int64(buffer.count) }

        func close() throws {
            defer { try? handle.close() }
            try sync()
        }
    }

    private static func parse(_ line: Substring) -> [String: Any]? {
        guard !line.isEmpty, let data = String(line).data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// The session's header, or nil for a file that has none.
    static func header(_ file: URL) -> [String: Any]? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 64 * 1024), let text = String(data: head, encoding: .utf8),
              let first = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first,
              let record = parse(first), VenueVisit.string(record, "k") == "session" else {
            return nil
        }
        return record
    }

    /// The last whole record of the file, or nil.
    static func lastRecord(_ file: URL) -> [String: Any]? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let length = try? handle.seekToEnd() else { return nil }
        let from = length > UInt64(tailBytes) ? length - UInt64(tailBytes) : 0
        guard (try? handle.seek(toOffset: from)) != nil, let tail = try? handle.readToEnd() else { return nil }
        let lines = String(decoding: tail, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
        // The first piece may be the tail of a line, the last a line cut short: only whole ones parse.
        var index = lines.count - 1
        while index >= (from > 0 ? 1 : 0) {
            if let record = parse(lines[index]) {
                return record
            }
            index -= 1
        }
        return nil
    }

    /// The session's end record, or nil while it has none.
    static func end(_ file: URL) -> [String: Any]? {
        guard let last = lastRecord(file), VenueVisit.string(last, "k") == "end" else { return nil }
        return last
    }

    /// When a record speaks of: a window's end for a beacon window, `t` otherwise.
    static func lastTime(_ record: [String: Any]) -> Int64 {
        var t = VenueVisit.int64(record, "t")
        if VenueVisit.string(record, "k") == "ble" {
            t += VenueVisit.int64(record, "w")
        }
        return t
    }

    /// Closes a session nothing is writing any more with an end that says so, stamped with the
    /// last record's time: nothing was observed after it, so nothing is claimed past it.
    static func finish(_ dir: URL, _ id: String, why: String, by: String) {
        let url = file(dir, id)
        guard FileManager.default.fileExists(atPath: url.path), end(url) == nil else { return }
        let at = lastRecord(url).map(lastTime) ?? 0
        guard let writer = try? Writer(dir: dir, id: id) else { return }
        writer.write(["k": "end", "t": at, "why": why, "by": by, "closed_at": Int64(Date().timeIntervalSince1970 * 1000)])
        try? writer.close()
    }

    /// The session files of the directory, oldest first.
    static func files(_ dir: URL) -> [URL] {
        let found = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        return found.filter { $0.lastPathComponent.hasSuffix(ext) && validId(idOf($0)) }
            .sorted { modified($0) < modified($1) }
    }

    static func idOf(_ file: URL) -> String {
        String(file.lastPathComponent.dropLast(ext.count))
    }

    private static func modified(_ file: URL) -> Date {
        (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static func size(_ file: URL) -> Int64 {
        Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    /// How many sessions the device keeps, and their bytes together.
    static func stored(_ dir: URL) -> (count: Int, bytes: Int64) {
        let all = files(dir)
        return (all.count, all.reduce(Int64(0)) { $0 + size($1) })
    }

    /// {"sessions": [...]}: what is on the device, oldest first, for the page.
    static func list(_ dir: URL, activeId: String?) -> [String: Any] {
        var sessions: [[String: Any]] = []
        for url in files(dir) {
            guard let header = header(url) else { continue }
            let id = idOf(url)
            let ended = end(url)
            sessions.append([
                "id": id,
                "dimension": VenueVisit.string(header, "venue"),
                "name": VenueVisit.string(header, "name"),
                "account": VenueVisit.string(header, "account"),
                "started_at": VenueVisit.int64(header, "t"),
                "ended_at": ended.map { VenueVisit.int64($0, "t") } ?? 0,
                "end": ended.map { VenueVisit.string($0, "why") } ?? "",
                "active": id == activeId,
                "bytes": size(url),
            ])
        }
        return ["sessions": sessions]
    }

    /// A piece of a session's file from `offset`, cut at a line's end: {id, offset, next, eof, text}.
    /// `eof` is true once the piece reaches the end of a session that is over.
    static func chunk(_ dir: URL, _ id: String, offset: Int64, activeId: String?) -> [String: Any] {
        let url = file(dir, id)
        guard validId(id), offset >= 0, let handle = try? FileHandle(forReadingFrom: url) else {
            return ["id": id, "offset": offset, "next": offset, "eof": true, "text": "", "error": "no such session"]
        }
        defer { try? handle.close() }
        var text = ""
        var next = offset
        let length = Int64((try? handle.seekToEnd()) ?? 0)
        if offset < length, (try? handle.seek(toOffset: UInt64(offset))) != nil,
           let bytes = try? handle.read(upToCount: Int(min(Int64(chunkBytes), length - offset))) {
            var end = bytes.count
            while end > 0 && bytes[bytes.startIndex + end - 1] != UInt8(ascii: "\n") {
                end -= 1
            }
            text = String(decoding: bytes.prefix(end), as: UTF8.self)
            next = offset + Int64(end)
        }
        let active = id == activeId
        // A torn last line never ends in a newline: a finished session whose remainder holds none is at its end.
        return ["id": id, "offset": offset, "next": next, "eof": !active && (next >= length || next == offset), "active": active, "text": text]
    }

    static func remove(_ dir: URL, _ id: String) -> Bool {
        guard validId(id) else { return false }
        return (try? FileManager.default.removeItem(at: file(dir, id))) != nil
    }

    /// Holds the directory to the limits: the oldest sessions go first, never the one being
    /// written. Answers what it removed, for the log.
    static func sweep(_ dir: URL, activeId: String?, now: Int64) -> [String] {
        var removed: [String] = []
        let all = files(dir)
        var bytes = all.reduce(Int64(0)) { $0 + size($1) }
        var count = all.count
        for url in all {
            let id = idOf(url)
            if id == activeId {
                continue
            }
            let old = now - Int64(modified(url).timeIntervalSince1970 * 1000) > maxAgeMs
            if !old && count <= maxSessions && bytes <= maxBytes {
                continue
            }
            let length = size(url)
            if (try? FileManager.default.removeItem(at: url)) != nil {
                removed.append(id + (old ? " (older than \(maxAgeMs / 86_400_000) days)" : " (over the device's limit)"))
                bytes -= length
                count -= 1
            }
        }
        return removed
    }
}
