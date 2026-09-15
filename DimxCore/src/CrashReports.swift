import Foundation
import MetricKit
import DimxNative

/**
 What iOS knows of the app's deaths - MetricKit's crash diagnostics, handed to
 the app at the launch after a crash with the operating system's own call stack
 - reported to the engine's telemetry as the previous run's `Crash`: each frame
 as the binary and the offset into its text segment, with the binary's UUID, the
 way an assert's stack is written, so env/symbolize.sh names them against the
 dSYM. Nothing runs in the crashing process, and no account is needed to read
 it. Crashlytics, when the app carries it, keeps sending its own beside this.
 */
final class CrashReports: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashReports()
    private var started = false

    /** Subscribes once the engine is up; pending diagnostics arrive shortly after. */
    func start() {
        guard !started else { return }
        started = true
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                report(crash, ended: payload.timeStampEnd)
            }
        }
    }

    private func report(_ crash: MXCrashDiagnostic, ended: Date) {
        var context: [String: String] = ["source": "os", "reason": "crash"]
        if let reason = crash.terminationReason, !reason.isEmpty {
            context["termination_reason"] = reason
        }
        if let signal = crash.signal {
            context["signal"] = Self.signalName(signal.int32Value)
        }
        if let type = crash.exceptionType {
            context["exception_type"] = type.stringValue
        }
        if let code = crash.exceptionCode {
            context["exception_code"] = code.stringValue
        }
        if let region = crash.virtualMemoryRegionInfo, !region.isEmpty {
            context["memory_region"] = String(region.prefix(300))
        }
        context["app_build"] = crash.metaData.applicationBuildVersion
        context["os_version"] = crash.metaData.osVersion
        context["device"] = crash.metaData.deviceType
        context["exit_time"] = ISO8601DateFormatter().string(from: ended)

        let frames = Self.frames(of: crash.callStackTree)
        let value = context["termination_reason"] ?? context["signal"] ?? "crash"
        Logger.warn("CrashReports: a previous run died of a crash [\(value)], \(frames.count) frames")
        Telemetry_reportException("Crash", value, Self.json(context), Self.json(frames))
    }

    /**
     The crashing thread's frames, innermost first, off the tree's JSON: `callStacks`,
     the one marked `threadAttributed` (else the first), its `callStackRootFrames`
     chained inward through `subFrames`. A frame is the binary, the offset into its
     text segment and its UUID.
     */
    private static func frames(of tree: MXCallStackTree) -> [[String: Any]] {
        guard let parsed = try? JSONSerialization.jsonObject(with: tree.jsonRepresentation()) as? [String: Any],
              let stacks = parsed["callStacks"] as? [[String: Any]], !stacks.isEmpty else {
            return []
        }
        let stack = stacks.first { ($0["threadAttributed"] as? Bool) == true } ?? stacks[0]
        var chain: [[String: Any]] = []
        var frame = (stack["callStackRootFrames"] as? [[String: Any]])?.first
        while let current = frame {
            chain.append(current)
            frame = (current["subFrames"] as? [[String: Any]])?.first
        }
        return chain.reversed().map { current in
            [
                "m": (current["binaryName"] as? String) ?? "",
                "o": (current["offsetIntoBinaryTextSegment"] as? Int) ?? 0,
                "b": ((current["binaryUUID"] as? String) ?? "").replacingOccurrences(of: "-", with: "").lowercased(),
                "s": "",
                "f": "",
                "l": 0,
            ]
        }
    }

    private static func signalName(_ number: Int32) -> String {
        let names: [Int32: String] = [1: "SIGHUP", 2: "SIGINT", 3: "SIGQUIT", 4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT", 7: "SIGEMT",
                                      8: "SIGFPE", 9: "SIGKILL", 10: "SIGBUS", 11: "SIGSEGV", 12: "SIGSYS", 13: "SIGPIPE", 15: "SIGTERM"]
        return "\(names[number] ?? "signal") (\(number))"
    }

    private static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}
