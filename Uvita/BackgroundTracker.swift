import Foundation
import Combine

class BackgroundTracker: ObservableObject {
    @Published var isTracking    = false
    @Published var lastLogTime:  Date? = nil
    @Published var todayCount:   Int   = 0
    @Published var indoors:      Bool  = false

    // Manual override — set by the user tapping the toggle.
    // nil means "use auto detection". When set, this value
    // overrides the OSM indoor result for every reading until
    // cleared (which happens when auto detection changes state,
    // i.e. the user physically moves somewhere different).
    @Published var manualIndoorOverride: Bool? = nil

    let logIntervalSeconds: TimeInterval = 5 * 60
    var logIntervalHours: Double { logIntervalSeconds / 3600.0 }

    // Rolling window of recent raw UVI values (auto-detected).
    // Window size = 3 readings = 15 min. Smooths out single
    // GPS-blip spikes before they enter SED calculation.
    private var uviWindow: [Double] = []
    private let uviWindowSize = 3

    private let weather = WeatherService()

    func autoResume(location: LocationManager, store: DataStore) {
        let was = UserDefaults.standard.bool(forKey: "uvita_tracking")
        if was { start(location: location, store: store) }
    }

    func start(location: LocationManager, store: DataStore) {
        isTracking = true
        uviWindow  = []
        manualIndoorOverride = nil
        UserDefaults.standard.set(true, forKey: "uvita_tracking")

        location.onLocationUpdate = { [weak self] in
            Task { @MainActor in
                await self?.logIfDue(location: location, store: store)
            }
        }
        Task { @MainActor in
            await logIfDue(location: location, store: store, force: true)
        }
    }

    func stop() {
        isTracking = false
        uviWindow  = []
        manualIndoorOverride = nil
        UserDefaults.standard.set(false, forKey: "uvita_tracking")
    }

    // Called when user taps the indoor/outdoor toggle.
    // Flips the current state, logs a correction to CSV,
    // and immediately fires a corrected reading.
    func userOverrideIndoor(
        _ isIndoor: Bool,
        location: LocationManager,
        store: DataStore) {

        let wasAuto = indoors
        manualIndoorOverride = isIndoor
        indoors = isIndoor

        // Log the correction for later analysis
        FileLogger.logCorrection(
            date:         Date(),
            lat:          location.latitude,
            lon:          location.longitude,
            accuracy:     location.accuracy,
            autoDetected: wasAuto,
            userSet:      isIndoor)

        // Fire an immediate corrected reading so the plasma
        // estimate updates right away
        Task { @MainActor in
            await log(location: location, store: store,
                      overrideIndoor: isIndoor)
        }
    }

    func logNow(location: LocationManager, store: DataStore) async {
        await log(location: location, store: store)
    }

    @MainActor
    private func logIfDue(location: LocationManager,
                          store: DataStore,
                          force: Bool = false) async {
        guard isTracking, location.ready else { return }
        if !force {
            if let last = lastLogTime,
               Date().timeIntervalSince(last) < logIntervalSeconds {
                return
            }
        }
        await log(location: location, store: store)
    }

    @MainActor
    private func log(location: LocationManager,
                     store: DataStore,
                     overrideIndoor: Bool? = nil) async {
        guard location.ready else { return }
        do {
            let w = try await weather.fetch(
                lat:      location.latitude,
                lon:      location.longitude,
                accuracy: location.accuracy)

            // Resolve indoor state: manual override wins,
            // then auto detection. If auto changed from the
            // last manual override state, clear the override
            // so future readings go back to auto.
            let autoIndoor = w.indoors
            let resolvedIndoor: Bool
            if let ov = overrideIndoor ?? manualIndoorOverride {
                // If auto now disagrees with override for 2+
                // readings in a row, the user has probably
                // moved — clear the override
                if autoIndoor != ov {
                    manualIndoorOverride = nil
                    resolvedIndoor = autoIndoor
                } else {
                    resolvedIndoor = ov
                }
            } else {
                resolvedIndoor = autoIndoor
            }
            indoors = resolvedIndoor

            // Rolling average UVI — add raw UVI to window
            // (0 if indoors, actual if outdoor).
            // Use the smoothed average for SED so a single
            // GPS spike at UVI=8 surrounded by 0s becomes
            // avg=(0+8+0)/3=2.67 instead of a full-spike reading.
            let rawUVI = resolvedIndoor ? 0.0 : w.uvi
            uviWindow.append(rawUVI)
            if uviWindow.count > uviWindowSize {
                uviWindow.removeFirst()
            }
            let smoothedUVI = uviWindow.reduce(0,+) / Double(uviWindow.count)

            // SED for this 5-min interval using smoothed UVI
            let sed = VitaminDEngine.uviToSED(
                uvi:           smoothedUVI,
                intervalHours: logIntervalHours)

            let profile     = store.profile
            let bodyPartSED = BodyPartSED.compute(
                baseSED:  sed,
                clothing: profile.clothing)

            let todaySEDSoFar = store.todaySED() + sed
            let oralSnap      = store.dailyOralUg()
            let plasma = VitaminDEngine.runModel(
                oralDoses: [oralSnap],
                uvDoses:   [todaySEDSoFar],
                bodyAreas: [profile.clothing.bsaPercent],
                age:       profile.age,
                skinType:  profile.skinType,
                C0:        profile.initialLevel
            ).first ?? profile.initialLevel

            let reading = DayReading(
                date:          Date(),
                uvi:           smoothedUVI,
                intervalHours: logIntervalHours,
                sed:           sed,
                bsaPercent:    profile.clothing.bsaPercent,
                oralUg:        oralSnap,
                plasmaLevel:   plasma,
                indoors:       resolvedIndoor,
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
