import CoreLocation

/// iOS monitors at most twenty regions for an app - circular and beacon regions together, across
/// every CLLocationManager of the process, whoever registered them: a twenty-first is refused with
/// a monitoring failure, and nothing says which feature lost. Two features of the SDK register
/// regions - the parking detection (ParkingWatcher) and the venue tracking (VenueTracker) - and a
/// host app may register its own, so each asks here how much room is left before it registers.
///
/// The split between the two: the parking detection keeps to six venues, a fence and a beacon
/// region each, and the venue tracking to four, which is the twenty when both are full and no
/// more than their share when the host takes some.
enum RegionBudget {
    static let limit = 20

    /// How many more regions may be registered. `replacing` names regions about to be registered
    /// again under the identifiers they have: iOS replaces a region of the same identifier, so
    /// those take no new room.
    static func room(_ manager: CLLocationManager, replacing: Set<String> = []) -> Int {
        limit - manager.monitoredRegions.filter { !replacing.contains($0.identifier) }.count
    }
}
