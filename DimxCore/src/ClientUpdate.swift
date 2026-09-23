import Foundation

/**
 * The platform's verdict on this build - what it answered the connection's
 * registration with, held by the engine (`Context.clientUpdate`), and told to
 * `Context.clientUpdateHandler` whenever it changes. `required` means the build is past
 * the floor the backend holds and must not go on: the engine refuses every
 * request from here (E1003), and the SDK refuses its screens with
 * `DimxError.updateRequired`. `advisory` is a nudge the host app may show at
 * its own pace - `shouldPrompt()` keeps the pace the platform asked for - and
 * no more. The platform decides which; the app only actions it.
 */
public struct ClientUpdate {
    public enum Severity: String {
        case advisory = "Advisory"
        case required = "Required"
    }

    public let severity: Severity
    /// Which floor the build fell under: api_version, build or version.
    public let reason: String?
    /// What this build would have to be for the verdict to clear.
    public let minVersion: String?
    public let minBuild: String?
    /// This platform's store page, where the holder goes to update.
    public let url: String?
    /// What the platform would have the screen say; the app's own wording when it names none.
    public let message: String?
    /// advisory only: not to be shown again before this many seconds have passed.
    public let remindAfterSeconds: Double?
    /// The verdict as the engine handed it over.
    public let json: String

    public var isRequired: Bool { severity == .required }

    /// What to say when the platform named nothing.
    public var displayMessage: String {
        if let message = message, !message.isEmpty {
            return message
        }
        return isRequired
            ? "This version is no longer supported. Please update to continue."
            : "A newer version is available."
    }

    init?(object: [String: Any], json: String) {
        guard let severity = Severity(rawValue: object["severity"] as? String ?? "") else {
            return nil
        }
        self.severity = severity
        self.json = json
        self.reason = object["reason"] as? String
        self.minVersion = object["min_version"] as? String
        self.minBuild = object["min_build"] as? String
        self.url = object["url"] as? String
        self.message = object["message"] as? String
        self.remindAfterSeconds = (object["remind_after_seconds"] as? NSNumber)?.doubleValue
    }

    /// The engine's JSON; nil for an empty or unreadable one.
    public init?(json: String) {
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        self.init(object: object, json: json)
    }
}

/// Where this build stands with the platform, read at any time (`Context.updateStatus`).
public enum UpdateStatus {
    /// No registration has been answered on this run: offline, or not connected yet.
    case unknown
    /// Answered, and nothing to say.
    case none
    case advisory(ClientUpdate)
    case required(ClientUpdate)
}

/// What the SDK refuses with.
public enum DimxError: Error {
    /// This build may not talk to the platform any more; the update carries where to go.
    case updateRequired(ClientUpdate)
}

extension DimxError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .updateRequired(let update):
            return update.displayMessage
        }
    }
}

// MARK: - The advisory's pace

extension ClientUpdate {
    private static let promptedKey = "dimx_update_prompted"
    /// What is being asked for, so a raised floor is a new advisory rather than one already shown.
    private var promptKey: String { "\(minBuild ?? "")/\(minVersion ?? "")" }

    /// Whether to put this in front of the holder now: always for `required`; for an advisory, not within
    /// `remindAfterSeconds` (a day when the platform named none) of the last `markPrompted()` - per device
    /// and per verdict, so a raised floor asks again.
    public func shouldPrompt() -> Bool {
        if isRequired {
            return true
        }
        let prompted = UserDefaults.standard.dictionary(forKey: Self.promptedKey) as? [String: Double] ?? [:]
        let last = prompted[promptKey] ?? 0
        return Date().timeIntervalSince1970 - last >= (remindAfterSeconds ?? 86400)
    }

    /// The holder has seen it: an advisory is not shown again before its interval has passed.
    public func markPrompted() {
        guard !isRequired else {
            return
        }
        var prompted = UserDefaults.standard.dictionary(forKey: Self.promptedKey) as? [String: Double] ?? [:]
        prompted[promptKey] = Date().timeIntervalSince1970
        UserDefaults.standard.set(prompted, forKey: Self.promptedKey)
    }
}
