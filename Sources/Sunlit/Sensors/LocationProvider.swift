import Foundation
import CoreLocation
import Observation
import SunlitCore

/// Where the device is.
///
/// Deliberately modest: one authorisation request, a coarse fix good enough for
/// solar geometry, and no background use. A tenth of a degree of latitude moves
/// sunrise by well under a minute, so there is nothing to gain from precise
/// accuracy and a permission prompt to lose.
@Observable
final class LocationProvider: NSObject {

    private(set) var coordinate: CLLocationCoordinate2D?
    private(set) var elevation: Double = 0
    private(set) var authorisation: CLAuthorizationStatus = .notDetermined
    private(set) var isResolving: Bool = false

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorisation = manager.authorizationStatus
    }

    func requestAuthorisation() {
        manager.requestWhenInUseAuthorization()
    }

    func refresh() {
        guard authorisation == .authorizedWhenInUse || authorisation == .authorizedAlways else { return }
        isResolving = true
        manager.requestLocation()
    }

    /// The current fix as a core Place, or nil when there is none yet.
    func currentPlace(named name: String) -> Place? {
        guard let coordinate else { return nil }
        return Place(
            name: name,
            geographic: Coordinates.Geographic(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                elevation: elevation),
            timeZoneIdentifier: TimeZone.current.identifier)
    }
}

extension LocationProvider: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorisation = manager.authorizationStatus
        if authorisation == .authorizedWhenInUse || authorisation == .authorizedAlways {
            refresh()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        isResolving = false
        guard let last = locations.last else { return }
        coordinate = last.coordinate
        // A negative altitude is the system saying it does not know, not a
        // place below sea level, and feeding it into the pressure model would
        // quietly distort refraction.
        elevation = last.verticalAccuracy > 0 ? max(0, last.altitude) : 0
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isResolving = false
    }
}
