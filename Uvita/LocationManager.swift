import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject,
                       CLLocationManagerDelegate {
    private let mgr = CLLocationManager()
    @Published var latitude:  Double = 0
    @Published var longitude: Double = 0
    @Published var accuracy:  Double = 10
    @Published var ready    = false
    @Published var statusMessage = "Waiting for GPS..."

    override init() {
        super.init()
        mgr.delegate = self
        mgr.desiredAccuracy =
            kCLLocationAccuracyHundredMeters
        mgr.allowsBackgroundLocationUpdates = true
        mgr.pausesLocationUpdatesAutomatically = false
        mgr.requestAlwaysAuthorization()
        mgr.startUpdatingLocation()
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locs: [CLLocation]) {
        guard let loc = locs.last else { return }
        latitude  = loc.coordinate.latitude
        longitude = loc.coordinate.longitude
        accuracy  = loc.horizontalAccuracy
        ready     = true
        statusMessage = String(
            format: "GPS ready — %.3f, %.3f (±%.0fm)",
            latitude, longitude, accuracy)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error) {
        statusMessage =
            "GPS error: \(error.localizedDescription)"
    }

    func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization
        status: CLAuthorizationStatus) {
        if status == .denied || status == .restricted {
            statusMessage =
                "Location denied — enable in Settings"
        }
    }
}
