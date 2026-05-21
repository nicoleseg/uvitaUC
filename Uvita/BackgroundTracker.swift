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



    private let weather = WeatherService()

    func autoResume(location: LocationManager, store: DataStore) {
        let was = UserDefaults.standard.bool(forKey: "uvita_tracking")
        if was { start(location: location, store: store) }
    }

    func start(location: LocationManager, store: DataStore) {
        isTracking = true
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

        // Compute the corrected UVI and SED so corrections.csv
        // is self-contained — no need to cross-reference UVlogs.
        // UVI = 0 if user marked indoors, last known UVI if outdoors.
        let correctedUVI = isIndoor ? 0.0
            : (store.readings.last?.uvi ?? 0.0)
        let correctedSED = VitaminDEngine.uviToSED(
            uvi:           correctedUVI,
            intervalHours: logIntervalHours)

        // Log the correction for later analysis
        FileLogger.logCorrection(
            date:         Date(),
            lat:          location.latitude,
            lon:          location.longitude,
            accuracy:     location.accuracy,
            autoDetected: wasAuto,
            userSet:      isIndoor,
            uvi:          correctedUVI,
            sed:          correctedSED)

        // Fire an immediate corrected reading so the plasma
        // estimate updates right away
        Task { @MainActor in
            // Remove the last auto reading before adding the
            // corrected one — Option C replacement strategy.
            // CSV is unaffected (append-only audit log).
            store.removeLastReadingIfRecent()
            await log(location: location, store: store,
                      overrideIndoor: isIndoor, label: nil)
        }
    }

    func logNow(location: LocationManager,
               store: DataStore,
               label: String? = nil) async {
        await log(location: location, store: store, label: label)
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
                     overrideIndoor: Bool? = nil,
                     label: String? = nil) async {
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

            // Raw UVI — 0 if indoors, actual if outdoors.
            // No smoothing — the uncertainty flag handles
            // flagging unreliable readings for evaluation.
            let rawUVI = resolvedIndoor ? 0.0 : w.uvi

            // SED for this 5-min interval
            let sed = VitaminDEngine.uviToSED(
                uvi:           rawUVI,
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

            // Uncertainty flag — for CSV evaluation only.
            // Poor accuracy alone, or stationary + moderate accuracy,
            // suggests the reading may be unreliable.
            // Does not change SED, indoor state, or plasma calculation.
            let isUncertain = location.accuracy > 40
                || (location.isStationary && location.accuracy > 25)

            let reading = DayReading(
                date:          Date(),
                uvi:           rawUVI,
                intervalHours: logIntervalHours,
                sed:           sed,
                bsaPercent:    profile.clothing.bsaPercent,
                oralUg:        oralSnap,
                plasmaLevel:   plasma,
                indoors:       resolvedIndoor,
                bodyPartSED:   bodyPartSED,
                clothingName:  profile.clothing.rawValue,
                isUncertain:   isUncertain,
                label:         label,
                lat:           location.latitude,
                lon:           location.longitude,
                gpsAccuracy:   location.accuracy)

            store.addReading(reading)
            FileLogger.log(reading: reading)

            lastLogTime = Date()
            todayCount  = store.todayReadings.count
        } catch {
            print("Tracker error: \(error)")
        }
    }
}
