import Foundation
import Combine

class BackgroundTracker: ObservableObject {
    @Published var isTracking  = false
    @Published var lastLogTime: Date? = nil
    @Published var todayCount:  Int   = 0
    @Published var indoors:     Bool  = false

    // How long must pass between logs (10 min)
    private let logInterval: TimeInterval = 10 * 60

    private let weather = WeatherService()

    // Called from TodayView.onAppear — resumes if was
    // tracking before app was killed
    func autoResume(location: LocationManager,
                    store: DataStore) {
        let was = UserDefaults.standard
            .bool(forKey: "uvita_tracking")
        if was { start(location: location, store: store) }
    }

    func start(location: LocationManager,
               store: DataStore) {
        isTracking = true
        UserDefaults.standard.set(
            true, forKey: "uvita_tracking")

        // Wire CoreLocation callback — fires whenever
        // CoreLocation delivers a new position (50m move
        // or app foreground). logIfDue() gates actual
        // network calls to once per logInterval.
        location.onLocationUpdate = { [weak self] in
            Task { @MainActor in
                await self?.logIfDue(
                    location: location, store: store)
            }
        }

        // Log immediately on start so user sees data
        Task { @MainActor in
            await logIfDue(
                location: location,
                store: store,
                force: true)
        }
    }

    func stop() {
        isTracking = false
        UserDefaults.standard.set(
            false, forKey: "uvita_tracking")
        // Nil out the callback so location events
        // no longer trigger logging
        // (LocationManager keeps running for GPS display)
    }

    // Force an immediate log — used when clothing changes
    func logNow(location: LocationManager,
                store: DataStore) async {
        await log(location: location, store: store)
    }

    // Gate: only call log() if enough time has passed
    @MainActor
    private func logIfDue(location: LocationManager,
                          store: DataStore,
                          force: Bool = false) async {
        guard isTracking else { return }
        guard location.ready else { return }

        let now = Date()
        if !force {
            if let last = lastLogTime,
               now.timeIntervalSince(last) < logInterval {
                return
            }
        }
        await log(location: location, store: store)
    }

    @MainActor
    private func log(location: LocationManager,
                     store: DataStore) async {
        guard location.ready else { return }
        do {
            let w = try await weather.fetch(
                lat:      location.latitude,
                lon:      location.longitude,
                accuracy: location.accuracy)

            indoors = w.indoors

            let profile = store.profile

            // Combine supplement + food log for oral intake
            let oralUg = profile.oralUg
                + store.todayOralUgFromFoodLog()

            let sed = VitaminDEngine.uviToSED(
                uvi:           w.uvi,
                daylightHours: w.daylightHours)

            let bodyPartSED = BodyPartSED.compute(
                baseSED:  sed,
                clothing: profile.clothing)

            let plasma = VitaminDEngine.singleDayEstimate(
                uvi:           w.uvi,
                daylightHours: w.daylightHours,
                bsaPercent:    profile.clothing.bsaPercent,
                age:           profile.age,
                skinType:      profile.skinType,
                oralUg:        oralUg,
                C0:            profile.initialLevel)

            let reading = DayReading(
                date:          Date(),
                uvi:           w.uvi,
                daylightHours: w.daylightHours,
                sed:           sed,
                bsaPercent:    profile.clothing.bsaPercent,
                oralUg:        oralUg,
                plasmaLevel:   plasma,
                indoors:       w.indoors,
                bodyPartSED:   bodyPartSED,
                clothingName:  profile.clothing.rawValue)

            store.addReading(reading)
            FileLogger.log(reading: reading)

            lastLogTime = Date()
            todayCount  = store.todayReadings.count
        } catch {
            print("Tracker error: \(error)")
        }
    }
}
