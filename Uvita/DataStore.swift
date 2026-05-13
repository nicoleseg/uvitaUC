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
        for r in readings {
            let day = cal.startOfDay(for: r.date)
            if let end = endDate, r.date > end { continue }
            dayMap[day, default: []].append(r)
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

    // ── Body part SED ────────────────────────────────────────

    func cumulativeBodyPartSED() -> [String: Double] {
        var totals: [String: Double] = [
            "Head": 0, "Hands": 0, "Forearms": 0,
            "Upper Arms": 0, "Lower Legs": 0,
            "Upper Legs": 0, "Torso": 0
        ]
        for r in readings where !r.indoors {
            totals["Head",      default: 0] += r.bodyPartSED.head
            totals["Hands",     default: 0] += r.bodyPartSED.hands
            totals["Forearms",  default: 0] += r.bodyPartSED.forearms
            totals["Upper Arms",default: 0] += r.bodyPartSED.upperArms
            totals["Lower Legs",default: 0] += r.bodyPartSED.lowerLegs
            totals["Upper Legs",default: 0] += r.bodyPartSED.upperLegs
            totals["Torso",     default: 0] += r.bodyPartSED.torso
        }
        return totals
    }

    var mostExposedBodyPart: (String, Double) {
        cumulativeBodyPartSED()
            .max(by: { $0.value < $1.value }) ?? ("None", 0)
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
        if let d = UserDefaults.standard.data(forKey: profileKey),
           let p = try? JSONDecoder().decode(
                UserProfile.self, from: d) { profile = p }
        if let d = UserDefaults.standard.data(forKey: readingsKey),
           let r = try? JSONDecoder().decode(
                [DayReading].self, from: d) { readings = r }
        if let d = UserDefaults.standard.data(forKey: foodLogKey),
           let f = try? JSONDecoder().decode(
                [FoodLogEntry].self, from: d) { foodLog = f }
    }
}
