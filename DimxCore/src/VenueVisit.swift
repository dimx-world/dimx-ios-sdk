import Foundation

/// The venue tracking's judgement, as arithmetic with nothing of iOS in it: whether a visit has
/// begun, whether it is over, and what of the beacons and the fixes is worth keeping. The Swift
/// twin of android-app's VenueVisit.java, held to it by the scenarios both run
/// (env/venue-tracking/scenarios.json in the dimx-dev workspace; check_swift.sh beside it compiles
/// this file alone, for the mac, and runs them). VenueTracker feeds it what the phone observed.
///
/// - `Judge` - the visit's state. A visit starts as a candidate: something said the phone may be
///   at the venue. It becomes inside on evidence of the venue itself - one of its beacons heard,
///   good fixes within its site - is leaving when a fence exit or a fix outside says so, and over
///   when that has stood for the confirmation time with no beacon heard and no fix inside
///   meanwhile - or at once when there is no doubt of it: good fixes clearly beyond the fence.
///   Evidence is only ever what was observed: silence is nothing, and a visit nobody observed
///   anything of for long enough ends as lost, not as stayed.
/// - `BleWindows` - the beacons heard, summed into windows; a window with nothing in it is
///   written too, since "listened and heard nothing" and "was not listening" are different facts.
/// - `FixSampler` - which fixes are kept: one a fix interval while the phone moves.
///
/// Times are milliseconds since the epoch, as Android keeps them, so one reader takes both
/// phones' sessions.
enum VenueVisit {
    private static let earthRadiusM = 6_371_008.8

    /// Metres between two points, along the great circle.
    static func distanceM(_ lat1: Double, _ lng1: Double, _ lat2: Double, _ lng2: Double) -> Double {
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let dPhi = (lat2 - lat1) * .pi / 180
        let dLambda = (lng2 - lng1) * .pi / 180
        let a = sin(dPhi / 2) * sin(dPhi / 2) + cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2)
        return 2 * earthRadiusM * asin(min(1.0, a.squareRoot()))
    }

    /// Java's Math.round: half goes up, also below zero - so both phones round a median alike.
    static func roundHalfUp(_ value: Double) -> Double {
        (value + 0.5).rounded(.down)
    }

    // MARK: - JSON, as the configs and the kept judge spell it

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

    static func int64(_ object: [String: Any], _ key: String) -> Int64 {
        Int64(number(object, key, 0))
    }

    // MARK: - The rules

    /// How long the judge waits before it concludes; a venue's config may say otherwise, in seconds.
    struct Rules {
        /// A candidate nothing confirmed for this long was not a visit.
        var arrivalConfirmMs: Int64 = 10 * 60_000
        /// An exit has to stand this long, with no beacon heard and no fix inside, to be the departure.
        var exitConfirmMs: Int64 = 3 * 60_000
        /// A visit nothing was observed of for this long is over, and says it was lost.
        var lostAfterMs: Int64 = 90 * 60_000
        var maxSessionMs: Int64 = 12 * 3_600_000
        /// A session whose recording stopped is taken up again within this, and closed past it.
        var resumeWindowMs: Int64 = 45 * 60_000
        /// Whether good fixes inside the site confirm an arrival.
        var gpsConfirms = true

        static func from(_ json: [String: Any]?) -> Rules {
            var rules = Rules()
            guard let json = json else { return rules }
            rules.arrivalConfirmMs = seconds(json, "arrival_confirm_s", rules.arrivalConfirmMs, 60, 3_600)
            rules.exitConfirmMs = seconds(json, "exit_confirm_s", rules.exitConfirmMs, 30, 1_800)
            rules.lostAfterMs = seconds(json, "lost_after_s", rules.lostAfterMs, 300, 6 * 3_600)
            rules.maxSessionMs = seconds(json, "max_session_s", rules.maxSessionMs, 600, 24 * 3_600)
            rules.resumeWindowMs = seconds(json, "resume_window_s", rules.resumeWindowMs, 0, 6 * 3_600)
            if json["gps_confirms"] != nil {
                rules.gpsConfirms = VenueVisit.bool(json, "gps_confirms")
            }
            return rules
        }

        func toJson() -> [String: Any] {
            [
                "arrival_confirm_s": arrivalConfirmMs / 1000,
                "exit_confirm_s": exitConfirmMs / 1000,
                "lost_after_s": lostAfterMs / 1000,
                "max_session_s": maxSessionMs / 1000,
                "resume_window_s": resumeWindowMs / 1000,
                "gps_confirms": gpsConfirms,
            ]
        }

        private static func seconds(_ json: [String: Any], _ key: String, _ fallbackMs: Int64, _ minS: Double, _ maxS: Double) -> Int64 {
            let value = VenueVisit.number(json, key, .nan)
            if value.isNaN {
                return fallbackMs
            }
            return Int64(VenueVisit.roundHalfUp(max(minS, min(maxS, value)))) * 1000
        }
    }

    // MARK: - The judge

    /// One thing the judge concluded: what changed, on what evidence, when.
    struct Change: CustomStringConvertible {
        static let confirmed = "confirmed"
        static let leaving = "leaving"
        static let stayed = "stayed"
        static let ended = "ended"

        let what: String
        /// For ended: departed, not_confirmed, lost, expired. Empty otherwise.
        let why: String
        /// The evidence: beacon, gps, fence, fence+gps, timeout, silence, stale.
        let by: String
        let at: Int64

        var description: String {
            what + (why.isEmpty ? "" : " " + why) + " by " + by
        }
    }

    /// The visit's state, from what was observed. Every input answers at most one change, and
    /// `tick` is what lets time itself conclude something.
    final class Judge {
        static let candidate = "candidate"
        static let inside = "inside"
        static let leavingState = "leaving"
        static let endedState = "ended"

        /// A fix this accurate, or better, and within the site is the phone at the venue.
        static let goodAccuracyM = 50.0
        /// A fix is outside only when the whole of its error circle is, and by this much more.
        static let outsideMarginM = 25.0
        /// A beacon heard this recently is the venue still: nothing opens an exit against it.
        static let beaconFreshMs: Int64 = 30_000
        static let insideFixesNeeded = 3
        static let insideSpanMs: Int64 = 30_000
        static let outsideFixesNeeded = 3
        static let outsideSpanMs: Int64 = 60_000
        /// With beacons at the venue and nothing listening for them, fixes alone end a visit, and
        /// indoors a fix can be far out: more of them, over longer.
        static let outsideFixesUnheard = 5
        static let outsideSpanUnheardMs: Int64 = 120_000
        /// Good fixes in a row whose error circles lie wholly beyond the fence - and outside the
        /// site - end a visit that is leaving at once: no doubt is left for the confirmation time
        /// to settle. With the fence's own exit beside them, one is enough.
        static let beyondFixesNeeded = 2

        private let rules: Rules
        private let siteRadius: Double
        private let fenceRadius: Double
        private let venueHasBeacons: Bool

        var state = Judge.candidate
        var startedAt: Int64
        /// From when silence counts: the start, or the last time the recording was taken up again.
        var liveSince: Int64
        var confirmedAt: Int64 = 0
        var confirmedBy = ""
        var lastBeaconAt: Int64 = 0
        /// The last evidence of the venue itself: a beacon, a good fix within the site.
        var lastInsideAt: Int64 = 0
        /// The last observation of any kind, whatever it said.
        var lastEvidenceAt: Int64 = 0
        /// The last fix as it was handed over - its distances and accuracy - for a phone said not to have moved since; -1 while there is none.
        var lastFixDistance = -1.0
        var lastFixFenceDistance = -1.0
        var lastFixAccuracy = -1.0
        var insideFixes = 0
        var insideFixesSince: Int64 = 0
        var outsideFixes = 0
        var outsideFixesSince: Int64 = 0
        var lastOutsideAt: Int64 = 0
        /// Good fixes in a row clearly beyond the fence (`beyondFixesNeeded`).
        var beyondFixes = 0
        var fenceExitAt: Int64 = 0
        var leavingSince: Int64 = 0
        var leavingWhy = ""
        /// Whether the venue's beacons are being listened for at all.
        var listening = false
        var endedAt: Int64 = 0
        var endedWhy = ""
        var endedBy = ""

        init(rules: Rules, siteRadiusM: Double, fenceRadiusM: Double, venueHasBeacons: Bool, startedAt: Int64) {
            self.rules = rules
            self.siteRadius = siteRadiusM
            self.fenceRadius = fenceRadiusM
            self.venueHasBeacons = venueHasBeacons
            self.startedAt = startedAt
            self.liveSince = startedAt
        }

        var ended: Bool { state == Judge.endedState }

        /// The listening for the venue's beacons started or stopped.
        func onListening(_ nowListening: Bool) {
            listening = nowListening
        }

        /// The recording was taken up again after a gap: silence is counted from now.
        func resumed(_ t: Int64) {
            liveSince = t
            // Whatever the phone did meanwhile, the fix from before no longer says where it is.
            lastFixDistance = -1
            lastFixFenceDistance = -1
            lastFixAccuracy = -1
            beyondFixes = 0
        }

        /// One of the venue's beacons was heard.
        func onBeacon(_ t: Int64) -> Change? {
            if ended {
                return nil
            }
            lastBeaconAt = t
            lastEvidenceAt = t
            if state == Judge.candidate {
                _ = noteInside(t)
                return confirm(t, "beacon")
            }
            return noteInside(t) ? Change(what: Change.stayed, why: "", by: "beacon", at: t) : nil
        }

        /// A fix, as its distance from the middle of the venue's site, its distance from the middle
        /// of the venue's fence - below zero for none known - and its accuracy, in metres.
        func onFix(_ t: Int64, distanceM: Double, fenceDistanceM: Double, accuracyM: Double) -> Change? {
            if ended {
                return nil
            }
            lastEvidenceAt = t
            lastFixDistance = distanceM
            lastFixFenceDistance = fenceDistanceM
            lastFixAccuracy = accuracyM
            let accuracy = accuracyM > 0 ? accuracyM : 100
            let good = accuracy <= Judge.goodAccuracyM
            let outside = distanceM - accuracy > siteRadius + Judge.outsideMarginM
            if good {
                // A good fix clearly beyond the fence adds to the run, any other good fix breaks
                // it; a poor one says nothing either way.
                let beyond = outside && fenceDistanceM >= 0 && fenceDistanceM - accuracy > fenceRadius
                beyondFixes = beyond ? beyondFixes + 1 : 0
            }
            if distanceM <= siteRadius && good {
                if insideFixes == 0 {
                    insideFixesSince = t
                }
                insideFixes += 1
                let stayed = noteInside(t)
                if state == Judge.candidate && rules.gpsConfirms
                    && insideFixes >= Judge.insideFixesNeeded && t - insideFixesSince >= Judge.insideSpanMs {
                    return confirm(t, "gps")
                }
                return stayed ? Change(what: Change.stayed, why: "", by: "gps", at: t) : nil
            }
            if outside {
                insideFixes = 0
                insideFixesSince = 0
                if outsideFixes == 0 {
                    outsideFixesSince = t
                }
                outsideFixes += 1
                lastOutsideAt = t
                return maybeLeave(t) ?? maybeDepart(t)
            }
            return nil   // it could be either side: an observation, and no evidence
        }

        /// The platform's word that the phone has not moved since its last fix - Core Location
        /// says so, and sends no fixes meanwhile: that fix stands, observed again now. Nothing
        /// without a fix to stand on.
        func onStationary(_ t: Int64) -> Change? {
            if ended || lastFixDistance < 0 {
                return nil
            }
            return onFix(t, distanceM: lastFixDistance, fenceDistanceM: lastFixFenceDistance, accuracyM: lastFixAccuracy)
        }

        /// The platform's fence round the venue was crossed.
        func onFence(_ t: Int64, entered: Bool) -> Change? {
            if ended {
                return nil
            }
            if entered {
                fenceExitAt = 0
                beyondFixes = 0
                // The fence is wider than the site, so coming back into it proves nothing of the
                // venue; it only takes back an exit that nothing but the fence had said.
                if state == Judge.leavingState && outsideFixes == 0 {
                    state = Judge.inside
                    leavingSince = 0
                    leavingWhy = ""
                    return Change(what: Change.stayed, why: "", by: "fence", at: t)
                }
                return nil
            }
            fenceExitAt = t
            if state == Judge.candidate && lastBeaconAt == 0 && insideFixes == 0 {
                return end(t, "not_confirmed", "fence")
            }
            return maybeLeave(t) ?? maybeDepart(t)
        }

        /// Time passed: what it concludes by itself. Called every few seconds while a session runs.
        func tick(_ t: Int64) -> Change? {
            if ended {
                return nil
            }
            if t - startedAt >= rules.maxSessionMs {
                return end(t, "expired", "timeout")
            }
            if state == Judge.candidate && t - startedAt >= rules.arrivalConfirmMs {
                return end(t, "not_confirmed", "timeout")
            }
            if state == Judge.inside, let leaving = maybeLeave(t) {
                return leaving
            }
            if state == Judge.leavingState {
                if let departed = maybeDepart(t) {
                    return departed
                }
                let quiet = t - leavingSince >= rules.exitConfirmMs && t - lastInsideAt >= rules.exitConfirmMs
                if quiet {
                    let unheard = venueHasBeacons && !listening
                    let need = unheard ? Judge.outsideFixesUnheard : Judge.outsideFixesNeeded
                    let span = unheard ? Judge.outsideSpanUnheardMs : Judge.outsideSpanMs
                    let byFixes = outsideFixes >= need && lastOutsideAt - outsideFixesSince >= span
                    let byFence = fenceExitAt > 0 && (!unheard || outsideFixes >= 1)
                    if byFence || byFixes {
                        return end(t, "departed", byFence ? (outsideFixes > 0 ? "fence+gps" : "fence") : "gps")
                    }
                }
                // An exit only fixes spoke of, and none has since: it was not one.
                let lastSaid = max(lastOutsideAt, leavingSince)
                if fenceExitAt == 0 && t - lastSaid >= 2 * rules.exitConfirmMs {
                    state = Judge.inside
                    leavingSince = 0
                    leavingWhy = ""
                    outsideFixes = 0
                    outsideFixesSince = 0
                    lastOutsideAt = 0
                    beyondFixes = 0
                    return Change(what: Change.stayed, why: "", by: "stale", at: t)
                }
            }
            if t - max(lastEvidenceAt, liveSince) >= rules.lostAfterMs {
                return end(t, "lost", "silence")
            }
            return nil
        }

        /// Ends the visit for a reason of the caller's: disabled, config_removed, permission, interrupted.
        func endNow(_ t: Int64, why: String, by: String) -> Change {
            end(t, why, by)
        }

        private func beaconsFresh(_ t: Int64) -> Bool {
            lastBeaconAt > 0 && t - lastBeaconAt < Judge.beaconFreshMs
        }

        /// Evidence of the venue itself; answers whether it took an exit back.
        private func noteInside(_ t: Int64) -> Bool {
            lastInsideAt = t
            outsideFixes = 0
            outsideFixesSince = 0
            lastOutsideAt = 0
            beyondFixes = 0
            fenceExitAt = 0
            if state == Judge.leavingState {
                state = Judge.inside
                leavingSince = 0
                leavingWhy = ""
                return true
            }
            return false
        }

        private func confirm(_ t: Int64, _ by: String) -> Change {
            state = Judge.inside
            confirmedAt = t
            confirmedBy = by
            lastInsideAt = t
            return Change(what: Change.confirmed, why: "", by: by, at: t)
        }

        private func maybeLeave(_ t: Int64) -> Change? {
            if state != Judge.inside || beaconsFresh(t) {
                return nil
            }
            let why: String
            if fenceExitAt > 0 {
                why = outsideFixes > 0 ? "fence+gps" : "fence"
            } else if outsideFixes > 0 {
                why = "gps"
            } else {
                return nil
            }
            state = Judge.leavingState
            leavingSince = t
            leavingWhy = why
            return Change(what: Change.leaving, why: "", by: why, at: t)
        }

        /// A departure there is no doubt of ends the visit without waiting out the confirmation:
        /// `beyondFixesNeeded` good fixes in a row clearly beyond the fence, or the fence's own exit
        /// and one such fix. A phone between the site and the fence - at the venue's door, or
        /// indoors with a fix thrown out - waits for the confirmation as ever.
        private func maybeDepart(_ t: Int64) -> Change? {
            if state != Judge.leavingState || beyondFixes == 0 {
                return nil
            }
            if beyondFixes < Judge.beyondFixesNeeded && fenceExitAt == 0 {
                return nil
            }
            return end(t, "departed", fenceExitAt > 0 ? "fence+gps" : "gps")
        }

        private func end(_ t: Int64, _ why: String, _ by: String) -> Change {
            state = Judge.endedState
            endedAt = t
            endedWhy = why
            endedBy = by
            return Change(what: Change.ended, why: why, by: by, at: t)
        }

        func toJson() -> [String: Any] {
            [
                "state": state, "started_at": startedAt, "live_since": liveSince,
                "confirmed_at": confirmedAt, "confirmed_by": confirmedBy,
                "last_beacon_at": lastBeaconAt, "last_inside_at": lastInsideAt, "last_evidence_at": lastEvidenceAt,
                "last_fix_d": lastFixDistance, "last_fix_fd": lastFixFenceDistance, "last_fix_acc": lastFixAccuracy,
                "inside_fixes": insideFixes, "inside_fixes_since": insideFixesSince,
                "outside_fixes": outsideFixes, "outside_fixes_since": outsideFixesSince, "last_outside_at": lastOutsideAt,
                "beyond_fixes": beyondFixes,
                "fence_exit_at": fenceExitAt, "leaving_since": leavingSince, "leaving_why": leavingWhy,
                "listening": listening, "ended_at": endedAt, "ended_why": endedWhy, "ended_by": endedBy,
            ]
        }

        /// A judge as `toJson` kept it, for a process that takes a session up again.
        static func from(_ json: [String: Any], rules: Rules, siteRadiusM: Double, fenceRadiusM: Double, venueHasBeacons: Bool) -> Judge {
            let judge = Judge(rules: rules, siteRadiusM: siteRadiusM, fenceRadiusM: fenceRadiusM, venueHasBeacons: venueHasBeacons,
                              startedAt: VenueVisit.int64(json, "started_at"))
            let state = VenueVisit.string(json, "state")
            judge.state = [Judge.inside, Judge.leavingState, Judge.endedState].contains(state) ? state : Judge.candidate
            judge.liveSince = json["live_since"] != nil ? VenueVisit.int64(json, "live_since") : judge.startedAt
            judge.confirmedAt = VenueVisit.int64(json, "confirmed_at")
            judge.confirmedBy = VenueVisit.string(json, "confirmed_by")
            judge.lastBeaconAt = VenueVisit.int64(json, "last_beacon_at")
            judge.lastInsideAt = VenueVisit.int64(json, "last_inside_at")
            judge.lastEvidenceAt = VenueVisit.int64(json, "last_evidence_at")
            judge.lastFixDistance = VenueVisit.number(json, "last_fix_d", -1)
            judge.lastFixFenceDistance = VenueVisit.number(json, "last_fix_fd", -1)
            judge.lastFixAccuracy = VenueVisit.number(json, "last_fix_acc", -1)
            judge.insideFixes = Int(VenueVisit.number(json, "inside_fixes", 0))
            judge.insideFixesSince = VenueVisit.int64(json, "inside_fixes_since")
            judge.outsideFixes = Int(VenueVisit.number(json, "outside_fixes", 0))
            judge.outsideFixesSince = VenueVisit.int64(json, "outside_fixes_since")
            judge.lastOutsideAt = VenueVisit.int64(json, "last_outside_at")
            judge.beyondFixes = Int(VenueVisit.number(json, "beyond_fixes", 0))
            judge.fenceExitAt = VenueVisit.int64(json, "fence_exit_at")
            judge.leavingSince = VenueVisit.int64(json, "leaving_since")
            judge.leavingWhy = VenueVisit.string(json, "leaving_why")
            judge.listening = VenueVisit.bool(json, "listening")
            judge.endedAt = VenueVisit.int64(json, "ended_at")
            judge.endedWhy = VenueVisit.string(json, "ended_why")
            judge.endedBy = VenueVisit.string(json, "ended_by")
            return judge
        }
    }

    // MARK: - The beacons, in windows

    /// The venue's beacons as they were heard, summed into windows of a few seconds: per beacon
    /// how many reports, their median strength and the strongest. Windows follow each other with
    /// no hole from `start` to `stop`, so the records say exactly when the phone was listening; a
    /// run of windows with nothing heard is kept as one record of the whole run.
    final class BleWindows {
        /// The strongest beacons of a window that are written; the rest are counted.
        static let maxBeacons = 12
        /// A run of empty windows is written out once it is this long.
        static let emptyRunFlushMs: Int64 = 60_000

        struct Stat {
            let major: Int
            let minor: Int
            let count: Int
            let median: Int
            let max: Int
        }

        struct Window {
            let start: Int64
            let lengthMs: Int64
            let adverts: Int
            /// Strongest first, maxBeacons at most.
            let beacons: [Stat]
            /// Beacons heard in the window beyond the ones listed.
            let more: Int
        }

        private let windowMs: Int64
        private var windowStart: Int64 = -1
        private var current: [Int: [Int]] = [:]
        private var currentAdverts = 0
        private var emptyFrom: Int64 = -1
        private var emptyLength: Int64 = 0

        init(windowMs: Int64) {
            self.windowMs = max(1000, windowMs)
        }

        var listening: Bool { windowStart >= 0 }

        /// Listening begins: windows are counted from here.
        func start(_ t: Int64) {
            if windowStart < 0 {
                windowStart = t
            }
        }

        /// A report of one of the venue's beacons. Windows that ended before it are closed into `out` first.
        func add(_ t: Int64, major: Int, minor: Int, rssi: Int, into out: inout [Window]) {
            if windowStart < 0 {
                return
            }
            roll(t, &out)
            current[(major << 16) | (minor & 0xFFFF), default: []].append(rssi)
            currentAdverts += 1
        }

        /// Time passed with or without reports: the windows that ended are closed into `out`.
        func drain(_ t: Int64, into out: inout [Window]) {
            if windowStart < 0 {
                return
            }
            roll(t, &out)
            if emptyFrom >= 0 && emptyLength >= BleWindows.emptyRunFlushMs {
                flushEmpty(&out)
            }
        }

        /// Listening ended: what was heard up to now is closed into `out`, the last window cut short.
        func stop(_ t: Int64, into out: inout [Window]) {
            if windowStart < 0 {
                return
            }
            roll(t, &out)
            let partial = max(0, t - windowStart)
            if partial > 0 || currentAdverts > 0 {
                close(windowStart, partial, &out)
            }
            flushEmpty(&out)
            windowStart = -1
        }

        private func roll(_ t: Int64, _ out: inout [Window]) {
            if t - windowStart < windowMs {
                return
            }
            close(windowStart, windowMs, &out)
            windowStart += windowMs
            // Whatever whole windows passed since are empty ones: one stretch, however long.
            let whole = (t - windowStart) / windowMs
            if whole > 0 {
                if emptyFrom < 0 {
                    emptyFrom = windowStart
                    emptyLength = 0
                }
                emptyLength += whole * windowMs
                windowStart += whole * windowMs
            }
        }

        private func close(_ start: Int64, _ lengthMs: Int64, _ out: inout [Window]) {
            if currentAdverts == 0 {
                if emptyFrom < 0 {
                    emptyFrom = start
                    emptyLength = 0
                }
                emptyLength += lengthMs
                return
            }
            flushEmpty(&out)
            var stats: [Stat] = []
            for (key, unsorted) in current {
                let values = unsorted.sorted()
                let n = values.count
                let median = n % 2 == 1 ? values[n / 2] : Int(VenueVisit.roundHalfUp(Double(values[n / 2 - 1] + values[n / 2]) / 2.0))
                stats.append(Stat(major: key >> 16, minor: key & 0xFFFF, count: n, median: median, max: values[n - 1]))
            }
            stats.sort { a, b in
                if a.median != b.median { return a.median > b.median }
                if a.major != b.major { return a.major < b.major }
                return a.minor < b.minor
            }
            let more = max(0, stats.count - BleWindows.maxBeacons)
            if more > 0 {
                stats = Array(stats.prefix(BleWindows.maxBeacons))
            }
            out.append(Window(start: start, lengthMs: lengthMs, adverts: currentAdverts, beacons: stats, more: more))
            current.removeAll()
            currentAdverts = 0
        }

        private func flushEmpty(_ out: inout [Window]) {
            if emptyFrom < 0 {
                return
            }
            if emptyLength > 0 {
                out.append(Window(start: emptyFrom, lengthMs: emptyLength, adverts: 0, beacons: [], more: 0))
            }
            emptyFrom = -1
            emptyLength = 0
        }
    }

    // MARK: - The fixes that are kept

    /// Which fixes are written: one a fix interval at most - Core Location hands them faster -
    /// and of those every one that moved half a metre from the last one written, so the path is
    /// as dense as the interval while the visitor walks and a phone lying still does not write its
    /// one place over and over. One is written every minute whatever it says: the proof fixes kept
    /// coming, which is what a still phone's time at the venue is counted from. A written fix
    /// carries how many were passed over since the one before it.
    final class FixSampler {
        /// A fix this far from the last one written has moved.
        static let minMoveM = 0.5
        /// One is written this often whatever it says.
        static let keepEveryMs: Int64 = 60_000
        /// The interval is held to this much of itself: a fix handed a little early is not lost to the jitter.
        static let intervalSlack = 0.9

        private let minIntervalMs: Int64
        private var any = false
        private var lastAt: Int64 = 0
        private var lastLat = 0.0
        private var lastLng = 0.0
        private var skipped = 0

        /// One fix an `intervalMs` at most: the config's fix_interval_s.
        init(intervalMs: Int64) {
            minIntervalMs = max(1_000, Int64(VenueVisit.roundHalfUp(Double(intervalMs) * FixSampler.intervalSlack)))
        }

        /// Answers how many fixes were passed over since the last kept one when this one is to be kept, -1 to pass it over.
        func offer(_ t: Int64, lat: Double, lng: Double) -> Int {
            let keep: Bool
            if !any {
                keep = true
            } else if t - lastAt < minIntervalMs {
                keep = false
            } else {
                keep = t - lastAt >= FixSampler.keepEveryMs || VenueVisit.distanceM(lastLat, lastLng, lat, lng) >= FixSampler.minMoveM
            }
            if !keep {
                skipped += 1
                return -1
            }
            let passed = skipped
            any = true
            lastAt = t
            lastLat = lat
            lastLng = lng
            skipped = 0
            return passed
        }

        /// A fix that is not written whatever it says - one beyond the fence: counted among those passed over.
        func pass() {
            skipped += 1
        }

        /// A stretch with no fixes ended the run: the next fix is kept whatever it says.
        func reset() {
            any = false
            skipped = 0
        }
    }

    // MARK: - The records

    /// A session's lines, one JSON object each (the format is env/venue-tracking/README.md's):
    /// every record has `k`, its kind, and `t`, milliseconds since the epoch.
    enum Records {
        static let version = 1

        static func fix(_ t: Int64, lat: Double, lng: Double, accuracyM: Double, skipped: Int, source: String) -> [String: Any] {
            var json: [String: Any] = [
                "k": "fix", "t": t, "lat": round(lat, 1e6), "lng": round(lng, 1e6), "acc": round(accuracyM, 10), "src": source,
            ]
            if skipped > 0 {
                json["skipped"] = skipped
            }
            return json
        }

        static func ble(_ window: BleWindows.Window) -> [String: Any] {
            var json: [String: Any] = ["k": "ble", "t": window.start, "w": window.lengthMs, "n": window.adverts]
            if !window.beacons.isEmpty {
                json["b"] = window.beacons.map { [$0.major, $0.minor, $0.count, $0.median, $0.max] }
            }
            if window.more > 0 {
                json["more"] = window.more
            }
            return json
        }

        /// A stretch nothing was sampled in, said outright: `sensor` is all, fix or ble.
        static func gap(_ t: Int64, from: Int64, to: Int64, sensor: String, why: String) -> [String: Any] {
            ["k": "gap", "t": t, "from": from, "to": to, "s": sensor, "why": why]
        }

        static func event(_ t: Int64, _ name: String) -> [String: Any] {
            ["k": "ev", "t": t, "e": name]
        }

        static func change(_ change: Change, state: String) -> [String: Any] {
            var json = event(change.at, change.what)
            if !change.why.isEmpty {
                json["why"] = change.why
            }
            json["by"] = change.by
            json["state"] = state
            return json
        }

        /// A value held to `1 / scale` (a scale of 1e6 keeps six decimals), as a decimal number:
        /// written as a Double, JSONSerialization spells 50.41203 as 50.412030000000001.
        static func round(_ value: Double, _ scale: Double) -> NSNumber {
            guard value.isFinite else { return NSNumber(value: 0) }
            let mantissa = VenueVisit.roundHalfUp(value * scale)
            let digits = Int16(max(0, (log10(scale)).rounded()))
            return NSDecimalNumber(mantissa: UInt64(abs(mantissa)), exponent: -digits, isNegative: mantissa < 0)
        }

        /// One record as its line: keys sorted, so the same record is the same text.
        static func line(_ record: [String: Any]) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .withoutEscapingSlashes]),
                  let text = String(data: data, encoding: .utf8) else {
                return "{}"
            }
            return text
        }
    }
}
