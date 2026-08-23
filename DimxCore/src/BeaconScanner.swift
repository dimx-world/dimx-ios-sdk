import CoreLocation
import DimxNative
import Foundation

final class BeaconScanner: NSObject, CLLocationManagerDelegate {
    // CoreLocation does not expose the calibrated iBeacon Measured Power byte.
    // The current beacon deployment is configured and tested with -60 dBm.
    private static let measuredPower: Int32 = -60

    private let mManager = CLLocationManager()
    private var mConstraints: [UUID: CLBeaconIdentityConstraint] = [:]
    private var mRangingUuids = Set<UUID>()
    private var mObservedBeacons = Set<String>()

    override init() {
        super.init()
        mManager.delegate = self
    }

    func updateUuids(_ json: String) {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let values = object as? [String] else {
            Logger.error("[Beacon] invalid scan UUID configuration")
            return
        }

        let parsedUuids = values.compactMap(UUID.init(uuidString:))
        if parsedUuids.count != values.count {
            Logger.warn("[Beacon] ignoring invalid scan UUID")
        }
        let uuids = Set(parsedUuids)
        var removedCount = 0

        for uuid in Set(mConstraints.keys).subtracting(uuids) {
            if let constraint = mConstraints.removeValue(forKey: uuid) {
                removedCount += 1
                if mRangingUuids.remove(uuid) != nil {
                    mManager.stopRangingBeacons(satisfying: constraint)
                }
            }
        }

        var addedCount = 0
        for uuid in uuids where mConstraints[uuid] == nil {
            mConstraints[uuid] = CLBeaconIdentityConstraint(uuid: uuid)
            addedCount += 1
        }

        if addedCount > 0 || removedCount > 0 {
            Logger.info("[Beacon] scan UUIDs updated added [\(addedCount)] removed [\(removedCount)] total [\(mConstraints.count)]")
        }

        startRangingIfAuthorized()
    }

    private func startRangingIfAuthorized() {
        switch mManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            var startedCount = 0
            for (uuid, constraint) in mConstraints where !mRangingUuids.contains(uuid) {
                mManager.startRangingBeacons(satisfying: constraint)
                mRangingUuids.insert(uuid)
                startedCount += 1
            }
            if startedCount > 0 {
                Logger.info("[Beacon] ranging started UUIDs [\(startedCount)] total [\(mRangingUuids.count)]")
            }
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        startRangingIfAuthorized()
    }

    func locationManager(_ manager: CLLocationManager,
                         didRange beacons: [CLBeacon],
                         satisfying beaconConstraint: CLBeaconIdentityConstraint) {
        for beacon in beacons {
            let uuid = beacon.uuid.uuidString.lowercased()
            let major = beacon.major.int32Value
            let minor = beacon.minor.int32Value
            let rssi = Int32(beacon.rssi)
            let id = "\(uuid):\(major):\(minor)"
            if beacon.proximity == .unknown || beacon.accuracy < 0 {
                continue
            }
            if mObservedBeacons.insert(id).inserted {
                Logger.info("[Beacon] observed [\(id)] RSSI [\(rssi)] measuredPower [\(Self.measuredPower)]")
            }

            processBeaconObservation(uuid, major, minor, rssi, Self.measuredPower)
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         rangingBeaconsDidFailFor constraint: CLBeaconIdentityConstraint,
                         withError error: Error) {
        Logger.error("[Beacon] ranging failed UUID [\(constraint.uuid.uuidString.lowercased())]: \(error.localizedDescription)")
    }
}
