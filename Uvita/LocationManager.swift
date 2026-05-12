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

    // BackgroundTracker assigns this to trigger logIfDue()
    // whenever CoreLocation delivers a fresh position.
    // Using CoreLocation as the wake source (not a Timer)
    // means iOS keeps delivering events even when the app
    // has been in the background for a long time, because
    // significant-location-change / 50m distanceFilter
    // wakes the process reliably.
    var onLocationUpdate: (() -> Void)?

    override init() {
        super.init()
        mgr.delegate                        = self
        mgr.desiredAccuracy                 = kCLLocationAccuracyHundredMeters
        mgr.allowsBackgroundLocationUpdates = true
        mgr.pausesLocationUpdatesAutomatically = false
        // Only wake for meaningful moves — prevents
        // spurious indoor/outdoor flips from GPS drift
        // while the device is stationary
        mgr.distanceFilter = 50
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

        // Fire — BackgroundTracker's logIfDue() decides
        // whether enough time has passed to actually log.
        // This is the only place onLocationUpdate is called.
        onLocationUpdate?()
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
