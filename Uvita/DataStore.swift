import Foundation
import Combine

class DataStore: ObservableObject {
    @Published var profile:  UserProfile     = UserProfile()
    @Published var readings: [DayReading]    = []
    @Published var foodLog:  [FoodLogEntry]  = []

    private let profileKey  = "uvita_profile_v2"
    private let readingsKey = "uvita_readings_v2"
    private let foodLogKey  = "uvita_foodlog_v1"

    init() { load() }

    // ── Write ────────────────────────────────────────────────

    func saveProfile() {
        if let d = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(d, forKey: profileKey)
        }
    }

    func addReading(_ r: DayReading) {
        readings.append(r)
        saveReadings()
    }

    // Remove the most recent auto reading if it was taken
    // within the last 6 minutes — called before adding a
    // corrected reading so the wrong one doesn't pollute
    // the daily SED aggregate or the model.
    // The original wrong reading remains in the CSV as an
    // append-only audit log — only removed from DataStore.
    func removeLastReadingIfRecent() {
        guard let last = readings.last,
              last.label == nil,  // only remove auto readings
              Date().timeIntervalSince(last.date) < 6 * 60
        else { return }
        readings.removeLast()
        saveReadings()
    }

    func addFoodLog(_ entry: FoodLogEntry) {
        foodLog.append(entry)
        saveFoodLog()
        FileLogger.logDiet(entry)
    }

    func removeFoodLog(_ entry: FoodLogEntry) {
        foodLog.removeAll { $0.id == entry.id }
        saveFoodLog()
    }

    func clearToday() {
        readings = readings.filter {
            !Calendar.current.isDateInToday($0.date)
        }
        saveReadings()
    }

    func clearAll() {
        readings = []
        saveReadings()
    }

    // ── Today helpers ────────────────────────────────────────

    var todayReadings: [DayReading] {
        readings.filter { Calendar.current.isDateInToday($0.date) }
    }

    var todayFoodLog: [FoodLogEntry] {
        foodLog.filter { Calendar.current.isDateInToday($0.date) }
    }

    // Sum of all per-reading SEDs logged today — this is
    // today's accumulated E(t) for display purposes.
    func todaySED() -> Double {
        todayReadings.reduce(0) { $0 + $1.sed }
    }

    // Daily oral intake resolved from the active source.
    // Food log entries are only counted if oralSource == .manualLog.
    // This ensures only one source is active at a time — if the
    // user switches back and forth during the day, only the
    // currently chosen source counts.
    func dailyOralUg() -> Double {
        switch profile.oralSource {
        case .manualLog:
            // Sum only food log entries for today
            return todayFoodLog.reduce(0) { $0 + $1.vitaminDug }
        default:
            // All other sources (useEstimate=5µg, manualIU, healthKit, assumeZero)
            // return a fixed daily value from the profile
            return profile.supplementOralUg
        }
    }

    // Food log total for today (for display only — not for
    // the model unless oralSource == .manualLog)
    func todayOralUgFromFoodLog() -> Double {
        todayFoodLog.reduce(0) { $0 + $1.vitaminDug }
    }

    // ── Diffey model — one entry per calendar day ────────────
    //
    // IMPORTANT: runModel() takes daily aggregates, not
    // per-reading values. Each day's entry is:
    //   uvDose   = sum of all reading.sed for that day
    //   oralDose = that day's oral intake (one value per day)
    //   bodyArea = most common (last) BSA% for the day
    //
    // This matches Eq. 8 where T indexes calendar days.

    private struct DayAggregate {
        let date:     Date
        let uvDose:   Double   // sum of per-reading SEDs
        let oralDose: Double   // daily oral µg
        let bsa:      Double   // last clothing BSA%
    }

    private func buildDayAggregates(
        upTo endDate: Date? = nil) -> [DayAggregate] {
        let cal  = Calendar.current
        var dayMap: [Date: [DayReading]] = [:]
        let startCutoff = profile.studyStartDate
            .map { cal.startOfDay(for: $0) }
        for r in readings {
            let day = cal.startOfDay(for: r.date)
            if let end   = endDate,   r.date > end  { continue }
            if let start = startCutoff, day < start { continue }
            dayMap[day, default: []].append(r)
        }

        // Deduplicate readings that are both close in time AND location.
        // This handles correction readings and glitches without
        // collapsing legitimate readings from movement.
        //
        // A reading is a duplicate of the previous if:
        //   - within 5 min (same scheduled interval), AND
        //   - within 30m GPS distance (same physical location)
        //
        // If you moved 50m+ (CoreLocation threshold), readings
        // are kept separately even if < 5 min apart.
        let windowSec: TimeInterval = 5 * 60
        let dupDistanceM: Double    = 30.0

        for day in dayMap.keys {
            let sorted = dayMap[day]!.sorted { $0.date < $1.date }
            var deduped: [DayReading] = []
            for r in sorted {
                if let last = deduped.last,
                   r.date.timeIntervalSince(last.date) < windowSec,
                   haversineDistance(
                       lat1: last.lat, lon1: last.lon,
                       lat2: r.lat,   lon2: r.lon) < dupDistanceM {
                    // Same time window + same location — replace with newest
                    deduped[deduped.count - 1] = r
                } else {
                    deduped.append(r)
                }
            }
            dayMap[day] = deduped
        }
        return dayMap
            .sorted { $0.key < $1.key }
            .map { day, rds in
                // UV dose = sum of all per-reading SEDs for the day
                let uvDose = rds.reduce(0) { $0 + $1.sed }
                // Oral dose = last reading's snapshot (daily value)
                let oral   = rds.sorted { $0.date < $1.date }
                                .last?.oralUg ?? profile.supplementOralUg
                // BSA = last clothing setting of the day
                let bsa    = rds.sorted { $0.date < $1.date }
                                .last?.bsaPercent ?? profile.clothing.bsaPercent
                return DayAggregate(date: day, uvDose: uvDose,
                                    oralDose: oral, bsa: bsa)
            }
    }

    // Absolute longitudinal plasma level as of right now.
    // Runs full Diffey model across all days up to today.
    func currentPlasmaLevel() -> Double {
        let aggs = buildDayAggregates()
        guard !aggs.isEmpty else { return profile.initialLevel }
        let result = VitaminDEngine.runModel(
            oralDoses: aggs.map { $0.oralDose },
            uvDoses:   aggs.map { $0.uvDose },
            bodyAreas: aggs.map { $0.bsa },
            age:       profile.age,
            skinType:  profile.skinType,
            C0:        profile.initialLevel)
        return result.last ?? profile.initialLevel
    }

    // Yesterday's ending plasma level — used to compute
    // today's delta on the Today tab.
    func yesterdayPlasmaLevel() -> Double {
        let cal = Calendar.current
        guard let yesterday = cal.date(
            byAdding: .day, value: -1, to: cal.startOfDay(for: Date()))
        else { return profile.initialLevel }
        let end  = cal.date(bySettingHour: 23, minute: 59,
                            second: 59, of: yesterday) ?? yesterday
        let aggs = buildDayAggregates(upTo: end)
        guard !aggs.isEmpty else { return profile.initialLevel }
        let result = VitaminDEngine.runModel(
            oralDoses: aggs.map { $0.oralDose },
            uvDoses:   aggs.map { $0.uvDose },
            bodyAreas: aggs.map { $0.bsa },
            age:       profile.age,
            skinType:  profile.skinType,
            C0:        profile.initialLevel)
        return result.last ?? profile.initialLevel
    }

    // Today's contribution = current absolute - yesterday's ending level.
    // This is what the Today tab big number shows.
    // Positive = gained vitamin D today, negative = losing (low UV day).
    func todayContribution() -> Double {
        currentPlasmaLevel() - yesterdayPlasmaLevel()
    }

    func plasmaForDay(_ date: Date) -> Double {
        let cal = Calendar.current
        let end = cal.date(bySettingHour: 23, minute: 59,
                           second: 59, of: date) ?? date
        let aggs = buildDayAggregates(upTo: end)
        guard !aggs.isEmpty else { return 0 }
        let result = VitaminDEngine.runModel(
            oralDoses: aggs.map { $0.oralDose },
            uvDoses:   aggs.map { $0.uvDose },
            bodyAreas: aggs.map { $0.bsa },
            age:       profile.age,
            skinType:  profile.skinType,
            C0:        profile.initialLevel)
        return result.last ?? profile.initialLevel
    }

    func plasmaHistory(days: Int) -> [(Date, Double)] {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<days).compactMap { offset -> (Date, Double)? in
            guard let date = cal.date(
                byAdding: .day, value: -offset, to: today)
            else { return nil }
            let level = plasmaForDay(date)
            guard level > 0 else { return nil }
            return (date, level)
        }.reversed()
    }

    // Same as buildDayAggregates but uses autoIndoorsResolved
    // instead of indoors — gives the "what if no corrections" projection
    private func buildRawDayAggregates(
        upTo endDate: Date? = nil) -> [DayAggregate] {
        let cal  = Calendar.current
        var dayMap: [Date: [DayReading]] = [:]
        let startCutoff = profile.studyStartDate
            .map { cal.startOfDay(for: $0) }
        for r in readings {
            let day = cal.startOfDay(for: r.date)
            if let end   = endDate,   r.date > end  { continue }
            if let start = startCutoff, day < start { continue }
            dayMap[day, default: []].append(r)
        }

        // Same location-aware deduplication as buildDayAggregates
        let windowSec: TimeInterval = 5 * 60
        let dupDistanceM: Double    = 30.0
        for day in dayMap.keys {
            let sorted = dayMap[day]!.sorted { $0.date < $1.date }
            var deduped: [DayReading] = []
            for r in sorted {
                if let last = deduped.last,
                   r.date.timeIntervalSince(last.date) < windowSec,
                   haversineDistance(
                       lat1: last.lat, lon1: last.lon,
                       lat2: r.lat,   lon2: r.lon) < dupDistanceM {
                    deduped[deduped.count - 1] = r
                } else {
                    deduped.append(r)
                }
            }
            dayMap[day] = deduped
        }

        // Build aggregates using auto-corrected SED values
        return dayMap
            .sorted { $0.key < $1.key }
            .map { day, rds in
                // Recompute UV dose using autoIndoors
                let uvDose = rds.reduce(0.0) { acc, r in
                    let rawIndoor = r.autoIndoorsResolved
                    let rawUVI    = rawIndoor ? 0.0 : r.uvi
                    return acc + VitaminDEngine.uviToSED(
                        uvi: rawUVI,
                        intervalHours: r.intervalHours)
                }
                let oral = rds.sorted { $0.date < $1.date }
                               .last?.oralUg ?? profile.supplementOralUg
                let bsa  = rds.sorted { $0.date < $1.date }
                               .last?.bsaPercent ?? profile.clothing.bsaPercent
                return DayAggregate(date: day, uvDose: uvDose,
                                    oralDose: oral, bsa: bsa)
            }
    }

    // Raw auto projection — what the model would show
    // without any user corrections to indoor detection
    func rawAutoProjection(windowDays: Int) -> [Double] {
        let aggs = buildRawDayAggregates()
        let window = Array(aggs.suffix(windowDays))
        guard !window.isEmpty else { return [] }
        let avgSED  = window.map { $0.uvDose  }.reduce(0,+) / Double(window.count)
        let avgOral = window.map { $0.oralDose }.reduce(0,+) / Double(window.count)
        let avgBSA  = window.map { $0.bsa      }.reduce(0,+) / Double(window.count)
        return VitaminDEngine.runModel(
            oralDoses: Array(repeating: avgOral, count: 90),
            uvDoses:   Array(repeating: avgSED,  count: 90),
            bodyAreas: Array(repeating: avgBSA,  count: 90),
            age:       profile.age,
            skinType:  profile.skinType,
            C0:        profile.initialLevel)
    }

    // For InsightsView longitudinal chart — returns per-day
    // model output with UV/oral split, one entry per day.
    struct DayModelResult {
        let date:        Date
        let label:       String
        let total:       Double
        let uvContrib:   Double
        let oralContrib: Double
    }

    func longitudinalModel(daysBack: Int) -> [DayModelResult] {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let cutoff = cal.date(
            byAdding: .day, value: -(daysBack - 1), to: today)
        else { return [] }

        let aggs = buildDayAggregates()
            .filter { $0.date >= cutoff }
        guard !aggs.isEmpty else { return [] }

        let n = aggs.count
        let totals = VitaminDEngine.runModel(
            oralDoses: aggs.map { $0.oralDose },
            uvDoses:   aggs.map { $0.uvDose },
            bodyAreas: aggs.map { $0.bsa },
            age: profile.age, skinType: profile.skinType,
            C0: profile.initialLevel)

        let uvOnly = VitaminDEngine.runModel(
            oralDoses: Array(repeating: 0, count: n),
            uvDoses:   aggs.map { $0.uvDose },
            bodyAreas: aggs.map { $0.bsa },
            age: profile.age, skinType: profile.skinType,
            C0: profile.initialLevel)

        let oralOnly = VitaminDEngine.runModel(
            oralDoses: aggs.map { $0.oralDose },
            uvDoses:   Array(repeating: 0, count: n),
            bodyAreas: aggs.map { $0.bsa },
            age: profile.age, skinType: profile.skinType,
            C0: profile.initialLevel)

        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"
        return aggs.enumerated().map { i, agg in
            DayModelResult(
                date:        agg.date,
                label:       fmt.string(from: agg.date),
                total:       totals[i],
                uvContrib:   max(0, uvOnly[i]   - profile.initialLevel),
                oralContrib: max(0, oralOnly[i] - profile.initialLevel))
        }
    }

    // ── Helpers ──────────────────────────────────────────────────

    // Haversine distance in metres between two GPS coordinates.
    // Used to distinguish duplicate readings (same spot, < 30m)
    // from legitimate movement readings (moved 50m+).
    private func haversineDistance(lat1: Double, lon1: Double,
                                    lat2: Double, lon2: Double) -> Double {
        let R   = 6371000.0  // Earth radius in metres
        let φ1  = lat1 * .pi / 180
        let φ2  = lat2 * .pi / 180
        let Δφ  = (lat2 - lat1) * .pi / 180
        let Δλ  = (lon2 - lon1) * .pi / 180
        let a   = sin(Δφ/2) * sin(Δφ/2)
                + cos(φ1) * cos(φ2) * sin(Δλ/2) * sin(Δλ/2)
        return R * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    // ── Retroactive historical UVI fill ─────────────────────
    // For readings where:
    //   - autoIndoors = true (detector said indoors)
    //   - autoIndoors != indoors (user corrected to outdoors)
    //   - rawUVI = 0.0 (no real UVI stored — was zeroed by indoor detection)
    // Fetches the real historical UVI from Open-Meteo archive API
    // and fills in rawUVI so the raw auto projection is accurate.
    func fillHistoricalUVI() async {
        // Find readings that need filling
        let needsFill = readings.enumerated().filter { _, r in
            r.rawUVI == 0.0
            && (r.autoIndoors == true)   // detector said indoors
            && (r.autoIndoors != r.indoors) // but was corrected to outdoors
        }
        guard !needsFill.isEmpty else {
            print("DataStore: no readings need historical UVI fill")
            return
        }

        // Group by date to minimize API calls (one call per day)
        let cal = Calendar.current
        var dayMap: [Date: [(offset: Int, element: DayReading)]] = [:]
        for pair in needsFill {
            let day = cal.startOfDay(for: pair.element.date)
            dayMap[day, default: []].append(pair)
        }

        print("DataStore: fetching historical UVI for \(dayMap.count) days")

        for (day, pairs) in dayMap {
            guard let hourlyUVI = await fetchHistoricalUVI(
                date: day,
                lat:  pairs.first?.element.lat  != 0
                    ? pairs.first!.element.lat
                    : profile.lastKnownLat,
                lon:  pairs.first?.element.lon  != 0
                    ? pairs.first!.element.lon
                    : profile.lastKnownLon)
            else { continue }

            for (idx, reading) in pairs {
                let hour = cal.component(.hour, from: reading.date)
                let uvi  = hourlyUVI[min(hour, hourlyUVI.count - 1)]
                readings[idx].rawUVI = uvi
                print("DataStore: filled rawUVI=\(uvi) for reading at \(reading.date)")
            }
        }
        saveReadings()
        print("DataStore: historical UVI fill complete — \(needsFill.count) readings updated")
    }

    private func fetchHistoricalUVI(
        date: Date, lat: Double, lon: Double) async -> [Double]? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let dateStr = fmt.string(from: date)

        var comps = URLComponents(
            string: "https://archive-api.open-meteo.com/v1/archive")!
        comps.queryItems = [
            .init(name: "latitude",     value: "\(lat)"),
            .init(name: "longitude",    value: "\(lon)"),
            .init(name: "start_date",   value: dateStr),
            .init(name: "end_date",     value: dateStr),
            .init(name: "hourly",       value: "uv_index"),
            .init(name: "timezone",     value: "America/Chicago"),
        ]
        guard let url = comps.url else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data)
                as! [String: Any]
            let hourly  = json["hourly"] as? [String: Any] ?? [:]
            let uviList = hourly["uv_index"] as? [Double] ?? []
            return uviList.isEmpty ? nil : uviList
        } catch {
            print("DataStore: historical UVI fetch failed: \(error)")
            return nil
        }
    }

    // ── Retroactive corrections patch ────────────────────────
    // Reads corrections.csv from the app's Documents folder,
    // matches each correction to the closest reading by timestamp,
    // and sets autoIndoors on that reading to the auto-detected value.
    // Only runs on readings where autoIndoors is still nil.
    // Safe to call multiple times — skips already-patched readings.
    // Status message from last patch attempt — shown in ProfileView
    @Published var correctionPatchStatus: String = ""

    func patchAutoIndoorsFromCSV() {
        guard let dir = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask).first else { return }

        let csvURL = dir
            .appendingPathComponent("Corrections")
            .appendingPathComponent("corrections.csv")

        guard let content = try? String(contentsOf: csvURL,
            encoding: .utf8) else {
            print("DataStore: corrections.csv not found — skipping patch")
            correctionPatchStatus = "corrections.csv not found — no corrections to apply"
            return
        }

        let lines = content.components(separatedBy: "\n")
            .dropFirst()  // skip header
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        // Parse each correction row
        struct CorrectionRow {
            let date:         Date
            let autoIndoor:   Bool
            let userIndoor:   Bool
            let wasWrong:     Bool
        }

        let fmt = ISO8601DateFormatter()
        var corrections: [CorrectionRow] = []

        for line in lines {
            let cols = line.components(separatedBy: ",")
            // timestamp,lat,lon,gps_accuracy_m,
            // auto_detected_indoor,user_set_indoor,was_wrong,...
            guard cols.count >= 7,
                  let date      = fmt.date(from: cols[0]),
                  let autoInt   = Int(cols[4]),
                  let userInt   = Int(cols[5]),
                  let wrongInt  = Int(cols[6])
            else { continue }

            corrections.append(CorrectionRow(
                date:       date,
                autoIndoor: autoInt  == 1,
                userIndoor: userInt  == 1,
                wasWrong:   wrongInt == 1))
        }

        guard !corrections.isEmpty else {
            print("DataStore: no corrections to patch")
            correctionPatchStatus = "corrections.csv found but empty — 0 rows"
            return
        }

        var patchCount = 0
        let matchWindow: TimeInterval = 6 * 60  // 6 minutes

        for correction in corrections {
            // Find the reading closest to this correction timestamp
            // within the match window, that hasn't been patched yet
            let candidates = readings
                .enumerated()
                .filter { _, r in
                    r.autoIndoors == nil &&
                    r.label == nil &&
                    abs(r.date.timeIntervalSince(correction.date))
                        < matchWindow
                }
                .sorted { a, b in
                    abs(a.element.date.timeIntervalSince(correction.date))
                    < abs(b.element.date.timeIntervalSince(correction.date))
                }

            guard let (idx, _) = candidates.first else { continue }

            readings[idx].autoIndoors = correction.autoIndoor
            patchCount += 1
        }

        if patchCount > 0 {
            saveReadings()
            print("DataStore: patched autoIndoors on \(patchCount) readings")
        }
        let total = corrections.count
        let wrong = corrections.filter { $0.wasWrong }.count
        correctionPatchStatus = patchCount > 0
            ? "Patched \(patchCount) readings from \(total) corrections (\(wrong) where detector was wrong)"
            : "\(total) corrections found — all readings already patched or no timestamp matches"
    }

    // ── Body part SED ────────────────────────────────────────

    func cumulativeBodyPartSED() -> [(String, Double)] {
        var totals: [String: Double] = [
            "Head": 0, "Neck": 0, "Upper Arms": 0,
            "Forearms": 0, "Hands": 0, "Torso": 0,
            "Upper Legs": 0, "Lower Legs": 0
        ]
        for r in readings where !r.indoors && r.label == nil {
            totals["Head",       default: 0] += r.bodyPartSED.head
            totals["Neck",       default: 0] += r.bodyPartSED.neck
            totals["Upper Arms", default: 0] += r.bodyPartSED.upperArms
            totals["Forearms",   default: 0] += r.bodyPartSED.forearms
            totals["Hands",      default: 0] += r.bodyPartSED.hands
            totals["Torso",      default: 0] += r.bodyPartSED.torso
            totals["Upper Legs", default: 0] += r.bodyPartSED.upperLegs
            totals["Lower Legs", default: 0] += r.bodyPartSED.lowerLegs
        }
        // Return head-to-toe order
        return [("Head", totals["Head"]!),
                ("Neck", totals["Neck"]!),
                ("Upper Arms", totals["Upper Arms"]!),
                ("Forearms", totals["Forearms"]!),
                ("Hands", totals["Hands"]!),
                ("Torso", totals["Torso"]!),
                ("Upper Legs", totals["Upper Legs"]!),
                ("Lower Legs", totals["Lower Legs"]!)]
    }

    var mostExposedBodyPart: (String, Double) {
        cumulativeBodyPartSED()
            .max(by: { $0.1 < $1.1 }) ?? ("None", 0)
    }

    // ── Persistence ──────────────────────────────────────────

    private func saveReadings() {
        if let d = try? JSONEncoder().encode(readings) {
            UserDefaults.standard.set(d, forKey: readingsKey)
        }
    }

    private func saveFoodLog() {
        if let d = try? JSONEncoder().encode(foodLog) {
            UserDefaults.standard.set(d, forKey: foodLogKey)
        }
    }

    private func load() {
        // Safe decode — if stored data is incompatible with the
        // current model (e.g. new fields added), discard it rather
        // than crashing. User loses old readings but app stays stable.
        if let d = UserDefaults.standard.data(forKey: profileKey) {
            if let p = try? JSONDecoder().decode(UserProfile.self, from: d) {
                profile = p
            } else {
                print("DataStore: profile decode failed — using defaults")
                UserDefaults.standard.removeObject(forKey: profileKey)
            }
        }
        if let d = UserDefaults.standard.data(forKey: readingsKey) {
            if let r = try? JSONDecoder().decode([DayReading].self, from: d) {
                readings = r
            } else {
                // Try decoding one at a time — keep any that succeed,
                // discard ones with missing/incompatible fields
                if let raw = try? JSONSerialization.jsonObject(with: d)
                    as? [[String: Any]] {
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    readings = raw.compactMap { dict in
                        guard let data = try? JSONSerialization.data(
                            withJSONObject: dict) else { return nil }
                        return try? decoder.decode(DayReading.self, from: data)
                    }
                    print("DataStore: partial readings recovered: \(readings.count)")
                } else {
                    print("DataStore: readings decode failed — cleared")
                    UserDefaults.standard.removeObject(forKey: readingsKey)
                }
            }
        }
        if let d = UserDefaults.standard.data(forKey: foodLogKey) {
            if let f = try? JSONDecoder().decode([FoodLogEntry].self, from: d) {
                foodLog = f
            } else {
                print("DataStore: foodLog decode failed — cleared")
                UserDefaults.standard.removeObject(forKey: foodLogKey)
            }
        }
    }
}
