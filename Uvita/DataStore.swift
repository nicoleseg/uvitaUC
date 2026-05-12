import Foundation
import Combine

class DataStore: ObservableObject {
    @Published var profile  = UserProfile()
    @Published var readings: [DayReading] = []
    @Published var foodLog:  [FoodLogEntry] = []

    private let profileKey  = "uvita_profile_v2"
    private let readingsKey = "uvita_readings_v2"
    private let foodLogKey  = "uvita_foodlog_v1"

    init() { load() }

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

    // ── Derived values ────────────────────────────────────────

    var todayReadings: [DayReading] {
        readings.filter { Calendar.current.isDateInToday($0.date) }
    }

    var todayFoodLog: [FoodLogEntry] {
        foodLog.filter { Calendar.current.isDateInToday($0.date) }
    }

    // Sum of vitamin D from food log entries logged today
    func todayOralUgFromFoodLog() -> Double {
        todayFoodLog.reduce(0) { $0 + $1.vitaminDug }
    }

    func todaySED() -> Double {
        todayReadings.reduce(0) { $0 + $1.sed }
    }

    func todayAvgPlasma() -> Double {
        guard !todayReadings.isEmpty else { return profile.initialLevel }
        return todayReadings.map { $0.plasmaLevel }.reduce(0, +)
            / Double(todayReadings.count)
    }

    // ── Full longitudinal model ───────────────────────────────

    func currentPlasmaLevel() -> Double {
        guard !readings.isEmpty else { return profile.initialLevel }
        let cal = Calendar.current
        var dayMap: [Date: DayReading] = [:]
        for r in readings {
            let day = cal.startOfDay(for: r.date)
            dayMap[day] = r
        }
        let sorted = dayMap.values.sorted { $0.date < $1.date }
        let result = VitaminDEngine.runModel(
            oralDoses: sorted.map { $0.oralUg },
            uvDoses:   sorted.map { $0.sed },
            bodyAreas: sorted.map { $0.bsaPercent },
            age:       profile.age,
            skinType:  profile.skinType,
            C0:        profile.initialLevel)
        return result.last ?? profile.initialLevel
    }

    func plasmaForDay(_ date: Date) -> Double {
        let cal = Calendar.current
        let dayReadings = readings.filter {
            cal.isDate($0.date, inSameDayAs: date)
        }.sorted { $0.date < $1.date }
        guard !dayReadings.isEmpty else { return 0 }

        var dayMap: [Date: DayReading] = [:]
        for r in readings {
            let day = cal.startOfDay(for: r.date)
            if r.date <= dayReadings.last!.date {
                dayMap[day] = r
            }
        }
        let sorted = dayMap.values.sorted { $0.date < $1.date }
        let result = VitaminDEngine.runModel(
            oralDoses: sorted.map { $0.oralUg },
            uvDoses:   sorted.map { $0.sed },
            bodyAreas: sorted.map { $0.bsaPercent },
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

    // ── Body part SED ─────────────────────────────────────────

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
            .max(by: { $0.value < $1.value })
            ?? ("None", 0)
    }

    // ── Persistence ───────────────────────────────────────────

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
           let p = try? JSONDecoder().decode(UserProfile.self, from: d) {
            profile = p
        }
        if let d = UserDefaults.standard.data(forKey: readingsKey),
           let r = try? JSONDecoder().decode([DayReading].self, from: d) {
            readings = r
        }
        if let d = UserDefaults.standard.data(forKey: foodLogKey),
           let f = try? JSONDecoder().decode([FoodLogEntry].self, from: d) {
            foodLog = f
        }
    }
}
