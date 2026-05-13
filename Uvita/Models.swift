import Foundation

struct DiffeyParams {
    static let f:          Double = 0.15
    static let beta:       Double = 25
    static let gamma:      Double = 250
    static let alpha:      Double = 0.6
    static let alphaPrime: Double = 1.5
    static let A_uv:       Double = 0.18
    static let S:          Double = 0.023
}

enum SkinType: String, CaseIterable, Identifiable, Codable {
    case typeI_II   = "Type I–II (very fair, burns easily)"
    case typeIII_VI = "Type III–VI (medium to dark, rarely burns)"
    var id: String { rawValue }
    var factor: Double {
        switch self {
        case .typeI_II:   return 1.0
        case .typeIII_VI: return 1.0 / 1.35
        }
    }
    var description: String {
        switch self {
        case .typeI_II:   return "Burns easily, rarely tans"
        case .typeIII_VI: return "Tans easily, rarely burns"
        }
    }
}

enum ClothingOption: String, CaseIterable, Identifiable, Codable {
    case fullyCovered     = "Full coverage (coat/hoodie)"
    case longSleevesPants = "Long sleeves + pants"
    case tshirtPants      = "T-shirt + pants"
    case tshirtShorts     = "T-shirt + shorts"
    case tankShorts       = "Tank top + shorts"
    case swimwear         = "Swimwear / very minimal"
    var id: String { rawValue }
    var bsaPercent: Double {
        switch self {
        case .fullyCovered:     return 2.0
        case .longSleevesPants: return 7.0
        case .tshirtPants:      return 13.0
        case .tshirtShorts:     return 30.0
        case .tankShorts:       return 37.0
        case .swimwear:         return 80.0
        }
    }
}

enum OralIntakeSource: String, Codable, CaseIterable {
    case healthKit   = "Apple Health (auto)"
    case manualLog   = "Log food in UVita"
    case manualIU    = "Enter IU/day manually"
    case useEstimate = "Use population average (5 µg/day)"
    case assumeZero  = "Assume 0 (no oral intake)"
}

struct UserProfile: Codable {
    var age:               Int              = 22
    var skinType:          SkinType         = .typeI_II
    var clothing:          ClothingOption   = .tshirtPants
    var oralIU:            Double           = 0.0
    var initialLevel:      Double           = 30.0
    var oralSource:        OralIntakeSource = .useEstimate
    var onboardingComplete                  = false

    // Daily oral µg from supplement / estimate.
    // Food log entries are tracked separately in DataStore
    // and resolved at the day level in dailyOralUg().
    var supplementOralUg: Double {
        switch oralSource {
        case .useEstimate: return 5.0    // ~200 IU/day population average
        case .assumeZero:  return 0.0
        case .manualIU:    return oralIU / 40.0
        case .healthKit:   return oralIU / 40.0
        case .manualLog:   return 0.0    // food log supplies the value
        }
    }
}

struct VitaminDEngine {

    static func ageFactor(_ age: Int) -> Double {
        max(0.1, 1.0 - 0.013 * Double(age - 20))
    }

    // Eq. 2 — SED for a single time-slice of duration
    // `intervalHours`. Each reading represents the UV dose
    // accumulated during its sampling interval, NOT the
    // whole day. Summing all readings in a day gives the
    // correct daily E(t) for the Diffey model.
    //
    // E_reading = UVI × 0.025 × intervalHours × 3600 / (2 × 100)
    //
    // For a fixed 5-min logger: intervalHours = 5/60 = 0.0833
    static func uviToSED(uvi: Double,
                         intervalHours: Double) -> Double {
        uvi * 0.025 * intervalHours * 3600.0 / (2.0 * 100.0)
    }

    static func R_UV(_ t: Double) -> Double {
        let p = DiffeyParams.self
        return p.A_uv * (
            (1 - p.f) * pow(2, -t / p.beta)
            + p.f     * pow(2, -t / p.gamma)
            - pow(2, -t / p.alpha)
        )
    }

    static func R_oral(_ t: Double) -> Double {
        let p = DiffeyParams.self
        return p.S * (
            (1 - p.f) * pow(2, -t / p.beta)
            + p.f     * pow(2, -t / p.gamma)
            - pow(2, -t / p.alphaPrime)
        )
    }

    static func computeC_oral(_ oralDoses: [Double]) -> [Double] {
        let N = oralDoses.count
        var result = [Double](repeating: 0.0, count: N)
        for T in 0..<N {
            var total = 0.0
            for t in 0...T {
                total += oralDoses[t] * R_oral(Double(T - t + 1))
            }
            result[T] = total
        }
        return result
    }

    static func computeC_sun(uvDoses: [Double],
                              bodyAreas: [Double],
                              age: Int,
                              skinType: SkinType) -> [Double] {
        let demo = ageFactor(age) * skinType.factor
        let N = uvDoses.count
        var result = [Double](repeating: 0.0, count: N)
        for T in 0..<N {
            var total = 0.0
            for t in 0...T {
                total += demo * uvDoses[t] * bodyAreas[t]
                       * R_UV(Double(T - t + 1))
            }
            result[T] = total
        }
        return result
    }

    // runModel expects ONE entry per CALENDAR DAY.
    // Each entry's uvDose is the sum of all per-reading SEDs
    // for that day. oralDose is the day's total oral intake.
    // bodyArea is the day's representative BSA %.
    static func runModel(oralDoses: [Double],
                         uvDoses:   [Double],
                         bodyAreas: [Double],
                         age:       Int,
                         skinType:  SkinType,
                         C0:        Double = 30.0) -> [Double] {
        let N      = oralDoses.count
        let C_oral = computeC_oral(oralDoses)
        let C_sun  = computeC_sun(uvDoses: uvDoses,
                                   bodyAreas: bodyAreas,
                                   age: age, skinType: skinType)
        var C_total = [Double](repeating: 0.0, count: N)
        for T in 0..<N {
            let C_prev      = T == 0 ? C0  : C_total[T-1]
            let C_oral_prev = T == 0 ? 0.0 : C_oral[T-1]
            let C_sun_prev  = T == 0 ? 0.0 : C_sun[T-1]
            let F           = exp(-0.01 * C_prev)
            C_total[T] = C_prev
                + (C_oral[T] - C_oral_prev)
                + F * (C_sun[T] - C_sun_prev)
        }
        return C_total
    }
}

// Per-body-part BSA breakdown from Lund-Browder chart
struct BodyPartExposure: Codable {
    let head:      Double
    let hands:     Double
    let forearms:  Double
    let upperArms: Double
    let lowerLegs: Double
    let upperLegs: Double
    let torso:     Double
}

extension ClothingOption {
    var bodyPartExposure: BodyPartExposure {
        switch self {
        case .fullyCovered:
            return BodyPartExposure(head: 2, hands: 0, forearms: 0,
                                    upperArms: 0, lowerLegs: 0,
                                    upperLegs: 0, torso: 0)
        case .longSleevesPants:
            return BodyPartExposure(head: 2, hands: 5, forearms: 0,
                                    upperArms: 0, lowerLegs: 0,
                                    upperLegs: 0, torso: 0)
        case .tshirtPants:
            return BodyPartExposure(head: 2, hands: 5, forearms: 6,
                                    upperArms: 0, lowerLegs: 0,
                                    upperLegs: 0, torso: 0)
        case .tshirtShorts:
            return BodyPartExposure(head: 2, hands: 5, forearms: 6,
                                    upperArms: 9, lowerLegs: 8,
                                    upperLegs: 0, torso: 0)
        case .tankShorts:
            return BodyPartExposure(head: 2, hands: 5, forearms: 6,
                                    upperArms: 9, lowerLegs: 8,
                                    upperLegs: 3, torso: 4)
        case .swimwear:
            return BodyPartExposure(head: 2, hands: 5, forearms: 6,
                                    upperArms: 9, lowerLegs: 8,
                                    upperLegs: 11, torso: 18)
        }
    }
}

struct BodyPartSED: Codable {
    let head:      Double
    let hands:     Double
    let forearms:  Double
    let upperArms: Double
    let lowerLegs: Double
    let upperLegs: Double
    let torso:     Double

    static func compute(baseSED: Double,
                        clothing: ClothingOption) -> BodyPartSED {
        let bp    = clothing.bodyPartExposure
        let total = clothing.bsaPercent
        guard total > 0 else {
            return BodyPartSED(head: 0, hands: 0, forearms: 0,
                               upperArms: 0, lowerLegs: 0,
                               upperLegs: 0, torso: 0)
        }
        return BodyPartSED(
            head:      baseSED * bp.head      / total,
            hands:     baseSED * bp.hands     / total,
            forearms:  baseSED * bp.forearms  / total,
            upperArms: baseSED * bp.upperArms / total,
            lowerLegs: baseSED * bp.lowerLegs / total,
            upperLegs: baseSED * bp.upperLegs / total,
            torso:     baseSED * bp.torso     / total)
    }

    var asDictionary: [String: Double] {
        ["Head": head, "Hands": hands,
         "Forearms": forearms, "Upper Arms": upperArms,
         "Lower Legs": lowerLegs, "Upper Legs": upperLegs,
         "Torso": torso]
    }

    var mostExposed: (String, Double) {
        asDictionary.max(by: { $0.value < $1.value }) ?? ("None", 0)
    }
}

// A single logged reading — one per 5-min interval.
// sed here is the per-reading SED (small number).
// The Diffey model receives DAILY aggregates from DataStore,
// not individual readings.
struct DayReading: Codable, Identifiable {
    var id            = UUID()
    let date:          Date
    let uvi:           Double
    let intervalHours: Double   // duration this reading represents (5/60)
    let sed:           Double   // per-reading SED — small, sums to daily E(t)
    let bsaPercent:    Double
    let oralUg:        Double   // snapshot oral µg at time of reading (not used in model directly)
    let plasmaLevel:   Double   // live estimate shown in UI only — not used in longitudinal model
    let indoors:       Bool
    let bodyPartSED:   BodyPartSED
    let clothingName:  String
}

struct FoodLogEntry: Codable, Identifiable {
    var id         = UUID()
    let name:        String
    let brand:       String
    let vitaminDug:  Double
    let servingDesc: String
    let date:        Date
}
