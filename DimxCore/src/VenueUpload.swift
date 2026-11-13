import Foundation
import UIKit

/// Hands the sessions that are over to the backend: each file to the generic service the
/// session's own gateway names, in pieces by offset (LOYALTY_UPLOAD_VISIT_SESSION, core-ts
/// services/loyalty VisitTypes), by the tracker itself - no page, no engine. The same loop as
/// android-app's VenueUpload, which has the reasoning spelled out.
///
/// A piece is whole lines and goes at the offset the service is believed to stand at; the answer
/// says where it stands, and the next piece goes from there - so an answer that was lost, a run
/// iOS cut short and a service that lost what it had are all the same loop. What stands of each
/// upload is kept between runs (`uploads.json`): how far it got, that it is whole there, or that
/// the service refused it for good, which ends the trying.
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
    static func run(_ dir: URL, uploads: inout [String: Any], activeId: String?, transport: VenueUploadTransport, now: Int64,
                    log: (String) -> Void) -> Outcome {
        var outcome = Outcome()
        for id in uploads.keys where !FileManager.default.fileExists(atPath: VenueSessionFile.file(dir, id).path) {
            uploads.removeValue(forKey: id)
        }
        var generics: [String: String] = [:]
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
                var generic = generics[gateway]
                if generic == nil {
                    generic = try locate(transport, gateway, device)
                    generics[gateway] = generic
                }
                if let refused = try send(file, id: id, dimension: VenueVisit.string(header, "venue"), account: account, device: device,
                                          generic: generic!, entry: &entry, transport: transport) {
                    refuse(refused)
                } else {
                    entry["done"] = true
                    entry["at"] = now
                    entry.removeValue(forKey: "error")
                    outcome.sent += 1
                    log("upload: session \(id) is whole at the service - \(VenueVisit.int64(entry, "sent")) bytes through \(generic!)")
                }
            } catch {
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

    /// The generic service the gateway hands this device: its address of the gateway's own scheme, as the page takes it.
    private static func locate(_ transport: VenueUploadTransport, _ gateway: String, _ device: String) throws -> String {
        var url = gateway + "/?header.type=GET_GENERIC_SERVICE"
        if !device.isEmpty, let encoded = device.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            url += "&header.app_instance=" + encoded
        }
        let answer = try object(transport.get(url))
        let generic = VenueVisit.string(answer, gateway.hasPrefix("https://") ? "https_url" : "http_url")
        guard generic.hasPrefix("http") else { throw VenueUploadError("the gateway named no generic service") }
        return generic
    }

    /// Sends what the service lacks of one file. Nil when it is whole there, the reason when the service refuses it for good.
    private static func send(_ file: URL, id: String, dimension: String, account: String, device: String, generic: String,
                             entry: inout [String: Any], transport: VenueUploadTransport) throws -> String? {
        let length = fileLength(file)
        var offset = max(0, min(length, VenueVisit.int64(entry, "sent")))
        for _ in 0..<maxRounds {
            let piece = try self.piece(file, offset: offset, max: pieceBytes)
            let last = offset + Int64(piece.count) >= length
            var head: [String: Any] = ["type": request, "account": account]
            if !device.isEmpty {
                head["app_instance"] = device
            }
            var body: [String: Any] = ["dimension": dimension, "session": id, "offset": offset, "text": String(decoding: piece, as: UTF8.self)]
            if last {
                body["done"] = true
            }
            let json = try JSONSerialization.data(withJSONObject: ["header": head, "body": body])
            let answer = try object(transport.post(generic, json: String(decoding: json, as: UTF8.self)))
            let refused = VenueVisit.string(answer, "refused")
            if !refused.isEmpty {
                return refused
            }
            let next = answer["next"] == nil ? -1 : VenueVisit.int64(answer, "next")
            guard next >= 0, next <= length else {
                throw VenueUploadError("the service says it holds \(next) bytes of a file of \(length)")
            }
            entry["sent"] = next
            if VenueVisit.bool(answer, "complete") {
                return nil
            }
            if next == offset {
                // It stands where it stood: with nothing left to send it will not call the session
                // whole, and with a piece just sent it did not take the piece. Neither mends by asking again now.
                throw VenueUploadError(piece.isEmpty
                    ? "the service holds all \(length) bytes and does not call the session whole"
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

    /// The file from `offset`: at most `max` bytes cut at a line's end - or to the next line's end, or the file's, when one line is longer.
    static func piece(_ file: URL, offset: Int64, max: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let length = Int64(handle.seekToEndOfFile())
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
        while true {
            let more = handle.readData(ofLength: 4096)
            if more.isEmpty {
                return bytes
            }
            if let newline = more.firstIndex(of: UInt8(ascii: "\n")) {
                bytes.append(more.prefix(through: newline))
                return bytes
            }
            bytes.append(more)
        }
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

/// Runs the uploads on a queue of its own, when there is something to send: asked at a session's
/// end, as the tracker starts in a process iOS launched - for the app's opening, a region, a
/// session's location updates - and when the app comes to the front. iOS has no scheduler to
/// hand this to without the host app declaring a task for it, so a run that left something
/// unsent is tried again while the process lives, and otherwise at the next of those moments.
/// Each run holds a background task, which is what keeps a process that has just ended its
/// location session alive for the seconds a visit's file takes.
final class VenueUploader {
    static let shared = VenueUploader()

    private let queue = DispatchQueue(label: "world.dimx.venue-upload", qos: .utility)
    private let store = VenueTrackingStore()
    private var running = false
    private var again = false
    private var retryAfter: TimeInterval = 60
    /// Stands in for the network in a test; nil for the real one.
    var transport: VenueUploadTransport?

    /// `activeId` is the session being written, which is never sent.
    func kick(_ why: String, activeId: String?) {
        queue.async { [self] in
            if running {
                again = true
                return
            }
            var uploads = store.uploads()
            guard !VenueUpload.pending(store.sessionsDirectory, uploads, activeId: activeId).isEmpty else { return }
            running = true
            var task = UIBackgroundTaskIdentifier.invalid
            task = UIApplication.shared.beginBackgroundTask(withName: "dimx-venue-upload") {
                // iOS wants the time back: what is unsent is tried at the next run.
                UIApplication.shared.endBackgroundTask(task)
                task = .invalid
            }
            let outcome = VenueUpload.run(store.sessionsDirectory, uploads: &uploads, activeId: activeId,
                                          transport: transport ?? VenueUploadHttp(), now: Int64(Date().timeIntervalSince1970 * 1000),
                                          log: { [store] line in store.log(line) })
            store.writeUploads(uploads)
            store.log("upload (\(why)): \(outcome)")
            running = false
            if task != .invalid {
                UIApplication.shared.endBackgroundTask(task)
            }
            if outcome.sent + outcome.refused > 0 {
                DispatchQueue.main.async { VenueTracker.shared.uploadsChanged() }
            }
            if outcome.waiting > 0 {
                let wait = retryAfter
                retryAfter = min(retryAfter * 2, 15 * 60)
                queue.asyncAfter(deadline: .now() + wait) { [self] in kick("after \(Int(wait)) s", activeId: VenueTracker.shared.currentSessionId()) }
            } else {
                retryAfter = 60
                if again {
                    again = false
                    kick("asked meanwhile", activeId: VenueTracker.shared.currentSessionId())
                }
            }
        }
    }
}
