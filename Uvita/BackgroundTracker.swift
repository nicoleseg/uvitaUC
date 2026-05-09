import Foundation
import Combine

class BackgroundTracker: ObservableObject {
    @Published var isTracking   = false
    @Published var lastLogTime:   Date? = nil
    @Published var todayCount:    Int   = 0
    @Published var indoors:       Bool  = false

    private var timer:   Timer?
    private let weather = WeatherService()
    private let intervalMinutes: Double = 10

    func start(location: LocationManager,
               store: DataStore) {
        guard !isTracking else { return }
        isTracking = true
        UserDefaults.standard.set(
            true, forKey: "uvita_tracking")
        Task {
            await log(location: location,
                      store: store)
        }
        timer = Timer.scheduledTimer(
            withTimeInterval: intervalMinutes * 60,
            repeats: true
        ) { [weak self] _ in
            Task {
                await self?.log(
                    location: location,
                    store: store)
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer      = nil
        isTracking = false
        UserDefaults.standard.set(
            false, forKey: "uvita_tracking")
    }

    func autoResume(location: LocationManager,
                    store: DataStore) {
        let was = UserDefaults.standard
            .bool(forKey: "uvita_tracking")
        if was {
            start(location: location, store: store)
        }
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
            let sed     = VitaminDEngine.uviToSED(
                uvi:           w.uvi,
                daylightHours: w.daylightHours)
            let plasma  =
                VitaminDEngine.singleDayEstimate(
                    uvi:           w.uvi,
                    daylightHours: w.daylightHours,
                    bsaPercent:
                        profile.clothing.bsaPercent,
                    age:           profile.age,
                    skinType:      profile.skinType,
                    oralUg:        profile.oralUg,
                    C0:            profile.initialLevel)

            store.addReading(DayReading(
                date:          Date(),
                uvi:           w.uvi,
                daylightHours: w.daylightHours,
                sed:           sed,
                bsaPercent:
                    profile.clothing.bsaPercent,
                oralUg:        profile.oralUg,
                plasmaLevel:   plasma))

            lastLogTime = Date()
            todayCount  = store.todayReadings.count
        } catch {
            print("Tracker error: \(error)")
        }
    }
}
