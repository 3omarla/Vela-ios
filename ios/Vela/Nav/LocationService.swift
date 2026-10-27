import CoreLocation
import Combine

@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    @Published private(set) var location: CLLocation?
    @Published private(set) var heading: CLLocationDirection?
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined

    let fixes = PassthroughSubject<CLLocation, Never>()
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .automotiveNavigation
        authorization = manager.authorizationStatus
    }

    func start() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    /// Guidance mode: best accuracy, keeps running with the screen off.
    func setNavigating(_ on: Bool, mode: TravelMode = .drive) {
        manager.desiredAccuracy = on ? kCLLocationAccuracyBestForNavigation : kCLLocationAccuracyBest
        manager.activityType = mode == .drive ? .automotiveNavigation : .otherNavigation
        manager.pausesLocationUpdatesAutomatically = !on
        if on {
            if manager.authorizationStatus == .authorizedWhenInUse { manager.requestAlwaysAuthorization() }
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
        } else {
            manager.allowsBackgroundLocationUpdates = false
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for l in locations where l.horizontalAccuracy >= 0 {
                self.location = l
                self.fixes.send(l)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in self.heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorization = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
