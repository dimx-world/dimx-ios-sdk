import CoreLocation
import DimxNative
import Foundation
import UIKit

/// Ranges the iBeacon UUIDs the engine registers and hands every observation to
/// the engine. Four things decide whether ranging is actually running: the
/// engine has registered a UUID (`register`), the app is not in the background,
/// location is authorised with *precise* accuracy - ranging delivers nothing
/// under approximate location, so a reduced grant is answered with the one-time
/// full-accuracy prompt - and ranging is available, which CoreLocation withdraws
/// while Bluetooth is off. A start CoreLocation refuses or fails is retried with
/// backoff, and re-tried at once when authorisation changes or the app returns
/// to the foreground.
///
/// Ranging stops with the app's going to the background, as Android's scan
/// does: the engine's update loop is parked there and takes no reading until
/// the return, and iOS no longer suspends a process a visit is tracked in
/// (VenueTracker) - it runs for the whole visit, and every answer ranged
/// meanwhile waited in the engine's queue to be taken, at the return, as heard
/// that moment. An iPhone back in front after three and a half minutes of
/// walking took in ten beacons of both wings of a mall in one millisecond, and
/// its next fixes stood 49 to 92 m from where it was (2026-11-20). The visit
/// tracker and the parking watcher range through location managers of their
/// own and are not this one's to stop.
///
/// Every call, including the delegate callbacks, lands on the main queue;
/// nothing here is synchronised.
final class BeaconScanner: NSObject, CLLocationManagerDelegate {
    // CoreLocation does not expose the calibrated iBeacon Measured Power byte.
    // The current beacon deployment is configured and tested with -60 dBm.
    private static let measuredPower: Int32 = -60
    // The entry under NSLocationTemporaryUsageDescriptionDictionary in the app's
    // Info.plist: the text of the prompt asking for precise location when the
    // user granted approximate. An app without the entry gets no prompt and a
    // console warning from CoreLocation.
    private static let fullAccuracyPurposeKey = "BeaconRanging"
    private static let retryMin: TimeInterval = 5
    private static let retryMax: TimeInterval = 60

    private let mManager = CLLocationManager()
    // What the engine has registered; ranging is wanted while this is not empty.
    private var mRegistered = Set<UUID>()
    // What CoreLocation has been asked to range and has not failed since.
    private var mRanging = Set<UUID>()
    // Off screen, where nothing is ranged. A process iOS launched in the
    // background for a region starts there.
    private var mInBackground = UIApplication.shared.applicationState == .background
    private var mFullAccuracyRequested = false
    private var mRetry: DispatchWorkItem?
    private var mRetryDelay = BeaconScanner.retryMin

    override init() {
        super.init()
        mManager.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Registers one UUID to range for. The set only grows between `stop`s: the
    /// engine adds UUIDs as it learns of nearby beacons and, rather than taking
    /// them back one by one, stops the scan outright once none are nearby. A
    /// repeat of a known UUID is a no-op.
    func register(_ value: String) {
        guard let uuid = UUID(uuidString: value) else {
            Logger.warn("[Beacon] ignoring malformed UUID [\(value)]")
            return
        }
        if !mRegistered.insert(uuid).inserted {
            return
        }
        Logger.info("[Beacon] scan UUID registered [\(uuid.uuidString.lowercased())] total [\(mRegistered.count)]")

        sync()
    }

    /// The engine has no beacons nearby: ranging stops and every UUID is
    /// forgotten, so the next `register` starts from nothing.
    func stop() {
        resetRetry()
        stopRanging("the engine has no beacons nearby")
        mRegistered.removeAll()
    }

    /// Ranging ends for every UUID; what is registered stays, for `sync` to
    /// start again.
    private func stopRanging(_ why: String) {
        for uuid in mRanging {
            mManager.stopRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: uuid))
        }
        if !mRanging.isEmpty {
            Logger.info("[Beacon] ranging stopped UUIDs [\(mRanging.count)] - \(why)")
        }
        mRanging.removeAll()
    }

    // MARK: - Starting

    /// Brings ranging in line with what is wanted: every registered UUID that is
    /// not ranging is started, provided the preconditions hold. Idempotent, so
    /// every trigger - a registration, an authorisation change, the foreground,
    /// a retry - simply calls it.
    private func sync() {
        cancelRetry()
        if mRegistered.isEmpty || mInBackground {
            return
        }

        switch mManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            break
        default:
            // LocationManager asks for permission; a grant arrives as
            // locationManagerDidChangeAuthorization on this delegate too.
            return
        }

        // Withdrawn while Bluetooth is off. Nothing announces it coming back
        // short of CoreBluetooth, so ask again on a timer.
        guard CLLocationManager.isRangingAvailable() else {
            Logger.warn("[Beacon] ranging unavailable (Bluetooth off?), retrying in [\(Int(mRetryDelay))s]")
            scheduleRetry()
            return
        }

        if mManager.accuracyAuthorization == .reducedAccuracy {
            requestFullAccuracy()
            return
        }

        let pending = mRegistered.subtracting(mRanging)
        for uuid in pending {
            mManager.startRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: uuid))
            mRanging.insert(uuid)
        }
        if !pending.isEmpty {
            Logger.info("[Beacon] ranging started UUIDs [\(pending.count)] total [\(mRanging.count)]")
        }
    }

    /// Ranging silently delivers nothing under approximate location, so ask for
    /// precise once per process - the prompt is a system alert, and the grant
    /// lasts until the app is terminated.
    private func requestFullAccuracy() {
        if mFullAccuracyRequested {
            return
        }
        mFullAccuracyRequested = true
        Logger.warn("[Beacon] location is approximate; ranging needs precise location, asking")
        mManager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: Self.fullAccuracyPurposeKey) { error in
            if let error = error {
                Logger.error("[Beacon] full accuracy request failed: \(error.localizedDescription)")
            }
            // A grant also arrives as locationManagerDidChangeAuthorization;
            // sync is idempotent, so answering both costs nothing.
            DispatchQueue.main.async { [weak self] in self?.sync() }
        }
    }

    // MARK: - Retrying

    private func scheduleRetry() {
        cancelRetry()
        let retry = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.mRetry = nil
            self.mRetryDelay = min(self.mRetryDelay * 2, Self.retryMax)
            self.sync()
        }
        mRetry = retry
        DispatchQueue.main.asyncAfter(deadline: .now() + mRetryDelay, execute: retry)
    }

    private func cancelRetry() {
        mRetry?.cancel()
        mRetry = nil
    }

    private func resetRetry() {
        cancelRetry()
        mRetryDelay = Self.retryMin
    }

    @objc private func appDidEnterBackground() {
        mInBackground = true
        resetRetry()
        stopRanging("the app is in the background")
    }

    @objc private func appWillEnterForeground() {
        mInBackground = false
        resetRetry()
        sync()
    }

    // MARK: - CLLocationManagerDelegate

    /// Fires on creation, on the permission grant LocationManager asks for, and
    /// when the accuracy grant changes - the full-accuracy prompt included.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        resetRetry()
        sync()
    }

    func locationManager(_ manager: CLLocationManager,
                         didRange beacons: [CLBeacon],
                         satisfying beaconConstraint: CLBeaconIdentityConstraint) {
        // An answer already on its way when ranging stopped for the background
        // is not the engine's to queue.
        if mInBackground {
            return
        }
        // Delivered once a second per constraint; ranging is working.
        mRetryDelay = Self.retryMin

        for beacon in beacons {
            // Proximity is unknown exactly when CoreLocation had no fresh RSSI
            // for this beacon in the last second; the reading is 0 and worthless.
            if beacon.proximity == .unknown {
                continue
            }
            let uuid = beacon.uuid.uuidString.lowercased()
            let major = beacon.major.int32Value
            let minor = beacon.minor.int32Value
            let rssi = Int32(beacon.rssi)

            processBeaconObservation(uuid, major, minor, rssi, Self.measuredPower)
        }
    }

    /// The constraint is forgotten as ranging, so the next sync starts it again;
    /// CoreLocation treats a repeat of an equal constraint as the same one.
    func locationManager(_ manager: CLLocationManager,
                         rangingBeaconsDidFailFor constraint: CLBeaconIdentityConstraint,
                         withError error: Error) {
        Logger.error("[Beacon] ranging failed UUID [\(constraint.uuid.uuidString.lowercased())]: \(error.localizedDescription), retrying in [\(Int(mRetryDelay))s]")
        mRanging.remove(constraint.uuid)
        scheduleRetry()
    }
}
