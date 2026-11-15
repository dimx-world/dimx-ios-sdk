import Foundation
import UIKit

/// Hands the sessions to the backend: each file to the generic service the session's own gateway
/// names, in pieces by offset (LOYALTY_UPLOAD_VISIT_SESSION, core-ts services/loyalty
/// VisitTypes), by the tracker itself - no page, no engine. The same loop as android-app's
/// VenueUpload, which has the reasoning spelled out.
///
/// A piece is whole lines and goes at the offset the service is believed to stand at; the answer
/// says where it stands, and the next piece goes from there - so an answer that was lost, a run
/// iOS cut short and a service that lost what it had are all the same loop. What stands of each
/// upload is kept between runs (`uploads.json`): how far it got, that it is whole there, or that
/// the service refused it for good, which ends the trying.
///
/// Two ways a session goes: while a visit the judge confirmed goes on, what has been written of
/// it every `upload_interval_s` (`live`) - every whole line so far, never the end, a failure
/// tried again at the next interval and counted toward nothing; and when it is over, the rest
/// with the last piece saying so (`run`), which is when the service makes the visit of it. Both
/// run on VenueUploader's queue, one at a time.
///
/// Who the session is of is the account in its own header, named in the request and taken at its
/// word for now: the tracker holds nothing to sign in with (the sign-in is the page's).
protocol VenueUploadTransport {
    /// The body of a 200; anything else throws, naming the status and what the service said.
    func get(_ url: String) throws -> String
    func post(_ url: String, json: String) throws -> String
}

struct VenueUploadError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// The generic service each gateway named, kept so that a sending every minute is one request,
/// not two; asked again only after a sending through it failed. Used on VenueUploader's queue.
final class VenueGenerics {
    private var byGateway: [String: String] = [:]

    func of(_ transport: VenueUploadTransport, _ gateway: String, _ device: String) throws -> String {
        if let generic = byGateway[gateway] {
            return generic
        }
        let generic = try VenueUpload.locate(transport, gateway, device)
        byGateway[gateway] = generic
        return generic
    }

    func forget(_ gateway: String) {
        byGateway.removeValue(forKey: gateway)
    }
}

enum VenueUpload {
    static let request = "LOYALTY_UPLOAD_VISIT_SESSION"
    /// One piece: small enough for a poor connection to carry, large enough that a long visit is a handful.
    static let pieceBytes = 64 * 1024
    /// A session the network or the service failed this many runs is left alone.
    static let maxTries = 40
    private static let maxRounds = 4096

    struct Outcome: CustomStringConvertible {
        var sent = 0
        var refused = 0
        var waiting = 0
        var description: String { "\(sent) sent, \(waiting) waiting, \(refused) refused" }
    }

    /// What one live sending did.
    struct Live {
        /// Bytes the service took this time.
        var sent: Int64 = 0
        /// Why the service will never take the session; nil when it may.
        var refused: String?
        /// Why this sending failed - to be tried again at the next interval; nil when it did not.
        var error: String?
    }

    /// Whether what has been written of the session being recorded is due to go: only once the
    /// judge confirmed the visit (`confirmedAt` above 0) - nothing of a phone never shown to be at
    /// the venue leaves it - and then at once, and every `intervalS` from the last try
    /// (`lastTryElapsed`, -1 for none yet).
    static func liveDue(confirmedAt: Int64, lastTryElapsed: Int64, elapsed: Int64, intervalS: Int) -> Bool {
        confirmedAt > 0 && (lastTryElapsed < 0 || elapsed - lastTryElapsed >= Int64(intervalS) * 1000)
    }

    /// Whether a session's upload is settled: whole at the service, refused for good, or given up on.
    static func settled(_ uploads: [String: Any], _ id: String) -> Bool {
        guard let entry = uploads[id] as? [String: Any] else { return false }
        return VenueVisit.bool(entry, "done") || !VenueVisit.string(entry, "refused").isEmpty
            || VenueVisit.number(entry, "tries", 0) >= Double(maxTries)
    }

    static func uploaded(_ uploads: [String: Any], _ id: String) -> Bool {
        VenueVisit.bool((uploads[id] as? [String: Any]) ?? [:], "done")
    }

    /// The sessions that are over and whose upload is not settled, oldest first.
    static func pending(_ dir: URL, _ uploads: [String: Any], activeId: String?) -> [URL] {
        VenueSessionFile.files(dir).filter { file in
            let id = VenueSessionFile.idOf(file)
            return id != activeId && !settled(uploads, id) && VenueSessionFile.end(file) != nil
        }
    }

    /// The gateway the session's venue was configured with: the config in its header carries it (`upload.gateway`).
    static func gatewayOf(_ header: [String: Any]?) -> String {
        let upload = ((header?["config"] as? [String: Any])?["upload"] as? [String: Any]) ?? [:]
        var gateway = VenueVisit.string(upload, "gateway")
        guard gateway.hasPrefix("https://") || gateway.hasPrefix("http://") else { return "" }
        while gateway.hasSuffix("/") { gateway.removeLast() }
        return gateway
    }

    /// One run over what is pending. `uploads` is changed in place - the caller writes it - and is
    /// held to the sessions the directory still has.
    static func run(_ dir: URL, uploads: inout [String: Any], activeId: String?, transport: VenueUploadTransport,
                    generics: VenueGenerics, now: Int64, log: (String) -> Void) -> Outcome {
        var outcome = Outcome()
        for id in uploads.keys where !FileManager.default.fileExists(atPath: VenueSessionFile.file(dir, id).path) {
            uploads.removeValue(forKey: id)
        }
        var unreachable = false
        for file in pending(dir, uploads, activeId: activeId) {
            let id = VenueSessionFile.idOf(file)
            var entry = (uploads[id] as? [String: Any]) ?? [:]
            defer { uploads[id] = entry }
            if unreachable {
                // The network failed a moment ago: the rest wait for the next run untried.
                outcome.waiting += 1
                continue
            }
            func refuse(_ reason: String) {
                entry["refused"] = reason
                log("upload: session \(id) is not sent: \(reason)")
                outcome.refused += 1
            }
            guard let header = VenueSessionFile.header(file), VenueVisit.string(header, "id") == id else {
                refuse("the file has no header of its own")
                continue
            }
            let account = VenueVisit.string(header, "account")
            let gateway = gatewayOf(header)
            if account.isEmpty {
                refuse("recorded with nobody signed in")
                continue
            }
            if gateway.isEmpty {
                refuse("the venue's config named no gateway to send it through")
                continue
            }
            let device = VenueVisit.string(header, "app_instance")
            do {
                let generic = try generics.of(transport, gateway, device)
                if let refused = try send(file, id: id, dimension: VenueVisit.string(header, "venue"), account: account, device: device,
                                          generic: generic, entry: &entry, transport: transport, end: fileLength(file), finishing: true) {
                    refuse(refused)
                } else {
                    entry["done"] = true
                    entry["at"] = now
                    entry.removeValue(forKey: "error")
                    outcome.sent += 1
                    log("upload: session \(id) is whole at the service - \(VenueVisit.int64(entry, "sent")) bytes through \(generic)")
                }
            } catch {
                generics.forget(gateway)
                let tries = Int(VenueVisit.number(entry, "tries", 0)) + 1
                entry["tries"] = tries
                entry["error"] = "\(error)"
                entry["tried_at"] = now
                outcome.waiting += 1
                unreachable = true
                log("upload: session \(id) not sent (try \(tries)\(tries >= maxTries ? ", the last" : "")): \(error)")
            }
        }
        return outcome
    }

    /// Sends what has been written so far of the session being recorded, `id`: every whole line on
    /// the disk, from where the service stands, and never the last piece - the visit goes on, and
    /// only `run` says a session is over. Reaching the end of what is written is success. A
    /// failure is noted in the session's entry and tried again at the next interval, counted
    /// toward no limit; a refusal for good is kept as `run` keeps it, which ends the trying both ways.
    static func live(_ dir: URL, uploads: inout [String: Any], id: String, transport: VenueUploadTransport,
                     generics: VenueGenerics, now: Int64, log: (String) -> Void) -> Live {
        var live = Live()
        let file = VenueSessionFile.file(dir, id)
        guard FileManager.default.fileExists(atPath: file.path), !settled(uploads, id) else { return live }
        var entry = (uploads[id] as? [String: Any]) ?? [:]
        defer { uploads[id] = entry }
        let header = VenueSessionFile.header(file)
        let account = VenueVisit.string(header ?? [:], "account")
        let gateway = gatewayOf(header)
        if header == nil || VenueVisit.string(header ?? [:], "id") != id {
            live.refused = "the file has no header of its own"
        } else if account.isEmpty {
            live.refused = "recorded with nobody signed in"
        } else if gateway.isEmpty {
            live.refused = "the venue's config named no gateway to send it through"
        }
        if let refused = live.refused {
            entry["refused"] = refused
            log("upload: session \(id) is not sent: \(refused)")
            return live
        }
        let device = VenueVisit.string(header ?? [:], "app_instance")
        let before = VenueVisit.int64(entry, "sent")
        do {
            let written = try lineEnd(file)
            if before >= written {
                return live
            }
            let generic = try generics.of(transport, gateway, device)
            if let refused = try send(file, id: id, dimension: VenueVisit.string(header ?? [:], "venue"), account: account, device: device,
                                      generic: generic, entry: &entry, transport: transport, end: written, finishing: false) {
                live.refused = refused
                entry["refused"] = refused
                log("upload: session \(id) is not sent: \(refused)")
                return live
            }
            entry.removeValue(forKey: "error")
            let held = VenueVisit.int64(entry, "sent")
            live.sent = max(0, held - before)
            log("upload: session \(id) as it goes - the service holds \(held) bytes (\(live.sent) sent now) through \(generic)")
        } catch {
            generics.forget(gateway)
            let said = "\(error)"
            live.error = said
            // Said once while it keeps failing the same way: the next interval tries again.
            if said != VenueVisit.string(entry, "error") {
                log("upload: session \(id) as it goes not sent, tried again in a while: \(said)")
            }
            entry["error"] = said
            entry["tried_at"] = now
        }
        return live
    }

    /// The generic service the gateway hands this device: its address of the gateway's own scheme, as the page takes it.
    static func locate(_ transport: VenueUploadTransport, _ gateway: String, _ device: String) throws -> String {
        var url = gateway + "/?header.type=GET_GENERIC_SERVICE"
        if !device.isEmpty, let encoded = device.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            url += "&header.app_instance=" + encoded
        }
        let answer = try object(transport.get(url))
        let generic = VenueVisit.string(answer, gateway.hasPrefix("https://") ? "https_url" : "http_url")
        guard generic.hasPrefix("http") else { throw VenueUploadError("the gateway named no generic service") }
        return generic
    }

    /// Sends what the service lacks of one file, up to `end`. Finishing - the visit over, `end` the
    /// file's length - the last piece says so (`done`) and the answer has to call the session
    /// whole; otherwise reaching `end` is all. Nil when that is done, the reason when the service
    /// refuses the session for good.
    private static func send(_ file: URL, id: String, dimension: String, account: String, device: String, generic: String,
                             entry: inout [String: Any], transport: VenueUploadTransport, end: Int64, finishing: Bool) throws -> String? {
        var offset = max(0, min(end, VenueVisit.int64(entry, "sent")))
        for _ in 0..<maxRounds {
            let piece = try self.piece(file, offset: offset, max: pieceBytes, end: end)
            let last = offset + Int64(piece.count) >= end
            var head: [String: Any] = ["type": request, "account": account]
            if !device.isEmpty {
                head["app_instance"] = device
            }
            var body: [String: Any] = ["dimension": dimension, "session": id, "offset": offset, "text": String(decoding: piece, as: UTF8.self)]
            if last && finishing {
                body["done"] = true
            }
            let json = try JSONSerialization.data(withJSONObject: ["header": head, "body": body])
            let answer = try object(transport.post(generic, json: String(decoding: json, as: UTF8.self)))
            let refused = VenueVisit.string(answer, "refused")
            if !refused.isEmpty {
                return refused
            }
            let next = answer["next"] == nil ? -1 : VenueVisit.int64(answer, "next")
            guard next >= 0, next <= end else {
                throw VenueUploadError("the service says it holds \(next) bytes of \(end)")
            }
            entry["sent"] = next
            if VenueVisit.bool(answer, "complete") || !finishing && next >= end {
                return nil
            }
            if next == offset {
                // It stands where it stood: with nothing left to send it will not call the session
                // whole, and with a piece just sent it did not take the piece. Neither mends by asking again now.
                throw VenueUploadError(piece.isEmpty
                    ? "the service holds all \(end) bytes and does not call the session whole"
                    : "the service did not take the piece at \(offset)")
            }
            // Where the service stands is its word: behind what was believed, the next piece goes from there.
            offset = next
        }
        throw VenueUploadError("the upload did not finish in \(maxRounds) pieces")
    }

    private static func fileLength(_ file: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// The file from `offset`: at most `max` bytes cut at a line's end - or to the next line's end, or the file's, when one line
    /// is longer - of the file's first `end` bytes alone (all of them by default).
    static func piece(_ file: URL, offset: Int64, max: Int, end: Int64 = Int64.max) throws -> Data {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let length = min(end, Int64(handle.seekToEndOfFile()))
        if offset >= length {
            return Data()
        }
        handle.seek(toFileOffset: UInt64(offset))
        var bytes = handle.readData(ofLength: Int(min(Int64(max), length - offset)))
        if offset + Int64(bytes.count) >= length {
            return bytes
        }
        if let newline = bytes.lastIndex(of: UInt8(ascii: "\n")) {
            return bytes.prefix(through: newline)
        }
        while offset + Int64(bytes.count) < length {
            let more = handle.readData(ofLength: Int(min(4096, length - offset - Int64(bytes.count))))
            if more.isEmpty {
                return bytes
            }
            if let newline = more.firstIndex(of: UInt8(ascii: "\n")) {
                bytes.append(more.prefix(through: newline))
                return bytes
            }
            bytes.append(more)
        }
        return bytes
    }

    /// How much of the file is whole lines: the bytes up to and with its last line's end. A file still being written ends in one being written.
    static func lineEnd(_ file: URL) throws -> Int64 {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var position = Int64(handle.seekToEndOfFile())
        while position > 0 {
            let size = min(Int64(4096), position)
            position -= size
            handle.seek(toFileOffset: UInt64(position))
            let block = handle.readData(ofLength: Int(size))
            if let newline = block.lastIndex(of: UInt8(ascii: "\n")) {
                return position + Int64(block.distance(from: block.startIndex, to: newline)) + 1
            }
        }
        return 0
    }

    private static func object(_ text: String) throws -> [String: Any] {
        guard let data = text.data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw VenueUploadError("the answer is not a JSON object")
        }
        return object
    }
}

/// The transport a phone uses: a request at a time, waited for on the uploader's own queue.
final class VenueUploadHttp: VenueUploadTransport {
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    func get(_ url: String) throws -> String {
        try exchange(url, body: nil)
    }

    func post(_ url: String, json: String) throws -> String {
        try exchange(url, body: Data(json.utf8))
    }

    private func exchange(_ address: String, body: Data?) throws -> String {
        guard let url = URL(string: address) else { throw VenueUploadError("not a url: \(address)") }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let body = body {
            request.httpMethod = "POST"
            // The service reads the content type as a whole: no charset beside it.
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        var result: Result<String, VenueUploadError> = .failure(VenueUploadError("no answer"))
        let done = DispatchSemaphore(value: 0)
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                result = .failure(VenueUploadError(error.localizedDescription))
            } else if let http = response as? HTTPURLResponse {
                let text = String(decoding: data ?? Data(), as: UTF8.self)
                result = http.statusCode == 200 ? .success(text) : .failure(VenueUploadError("HTTP \(http.statusCode): \(VenueUploadHttp.firstLine(text))"))
            }
            done.signal()
        }.resume()
        done.wait()
        return try result.get()
    }

    /// What a refusal says, without the stack the service appends to it.
    private static func firstLine(_ text: String) -> String {
        var said = text
        if let data = text.data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let error = object["error"] as? String {
            said = error
        }
        return String((said.split(separator: "\n", maxSplits: 1).first ?? "").prefix(200))
    }
}

/// Runs the uploads on a queue of its own. The sessions that are over go when there is something
/// to send: asked at a session's end, as the tracker starts in a process iOS launched - for the
/// app's opening, a region, a session's location updates - and when the app comes to the front.
/// iOS has no scheduler to hand this to without the host app declaring a task for it, so a run
/// that left something unsent is tried again while the process lives, and otherwise at the next
/// of those moments. What a confirmed visit has recorded while it goes on goes when the tracker
/// asks (`kickLive`, every `upload_interval_s`). Each run holds a background task, which is what
/// keeps a process that has just ended its location session alive for the seconds a visit's file
/// takes. The queue is serial: one sending at a time, and the generic services the gateways named
/// are kept on it.
final class VenueUploader {
    static let shared = VenueUploader()

    private let queue = DispatchQueue(label: "world.dimx.venue-upload", qos: .utility)
    private let store = VenueTrackingStore()
    private let generics = VenueGenerics()
    private var running = false
    private var again = false
    private var retryAfter: TimeInterval = 60
    /// Stands in for the network in a test; nil for the real one.
    var transport: VenueUploadTransport?

    /// `activeId` is the session being written, which this never sends: its own end does.
    func kick(_ why: String, activeId: String?) {
        queue.async { [self] in
            if running {
                again = true
                return
            }
            var uploads = store.uploads()
            guard !VenueUpload.pending(store.sessionsDirectory, uploads, activeId: activeId).isEmpty else { return }
            running = true
            let task = BackgroundTask()
            let outcome = VenueUpload.run(store.sessionsDirectory, uploads: &uploads, activeId: activeId,
                                          transport: transport ?? VenueUploadHttp(), generics: generics,
                                          now: Int64(Date().timeIntervalSince1970 * 1000), log: { [store] line in store.log(line) })
            store.writeUploads(uploads)
            store.log("upload (\(why)): \(outcome)")
            running = false
            task.end()
            if outcome.sent + outcome.refused > 0 {
                DispatchQueue.main.async { VenueTracker.shared.uploadsChanged() }
            }
            if outcome.waiting > 0 {
                let wait = retryAfter
                retryAfter = min(retryAfter * 2, 15 * 60)
                queue.asyncAfter(deadline: .now() + wait) { [self] in rekick("after \(Int(wait)) s") }
            } else {
                retryAfter = 60
                if again {
                    again = false
                    rekick("asked meanwhile")
                }
            }
        }
    }

    /// What has been written of the session being recorded, `id`, sent while the visit goes on -
    /// asked by the tracker when it is due, and only for a visit the judge confirmed.
    func kickLive(_ id: String) {
        queue.async { [self] in
            var uploads = store.uploads()
            let task = BackgroundTask()
            let live = VenueUpload.live(store.sessionsDirectory, uploads: &uploads, id: id, transport: transport ?? VenueUploadHttp(),
                                        generics: generics, now: Int64(Date().timeIntervalSince1970 * 1000),
                                        log: { [store] line in store.log(line) })
            store.writeUploads(uploads)
            task.end()
            if live.refused != nil {
                DispatchQueue.main.async { VenueTracker.shared.uploadsChanged() }
            }
        }
    }

    /// A run asked again from this queue: which session is being written is the tracker's to say, on the main thread.
    private func rekick(_ why: String) {
        DispatchQueue.main.async { [self] in
            kick(why, activeId: VenueTracker.shared.currentSessionId())
        }
    }

    /// The time a run asks of iOS: ended by the run, or by iOS wanting it back (what is unsent is
    /// then tried at the next run) - whichever comes first, and only once.
    private final class BackgroundTask {
        private let lock = NSLock()
        private var id = UIBackgroundTaskIdentifier.invalid

        init() {
            let id = UIApplication.shared.beginBackgroundTask(withName: "dimx-venue-upload") { [weak self] in
                self?.end()
            }
            lock.lock()
            self.id = id
            lock.unlock()
        }

        func end() {
            lock.lock()
            let id = self.id
            self.id = .invalid
            lock.unlock()
            if id != .invalid {
                UIApplication.shared.endBackgroundTask(id)
            }
        }
    }
}
