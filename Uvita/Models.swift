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
    // Total BSA% per clothing option — Lund-Browder adult chart.
    // Updated to match body-part breakdowns below exactly.
    var bsaPercent: Double {
        switch self {
        case .fullyCovered:     return 7.0   // head only
        case .longSleevesPants: return 14.0  // head+neck+hands
        case .tshirtPants:      return 20.0  // head+neck+forearms+hands
        case .tshirtShorts:     return 36.0  // +upperArms+lowerLegs
        case .tankShorts:       return 53.0  // +torso partial+upperLegs partial
        case .swimwear:         return 80.0  // near full body
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
    // Study start date — readings before this date are excluded
    // from all model calculations. nil means use all data.
    var studyStartDate:    Date?            = nil

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
// Body part exposure — ordered head to toe
struct BodyPartExposure: Codable {
    let head:      Double
    let neck:      Double
    let upperArms: Double
    let forearms:  Double
    let hands:     Double
    let torso:     Double
    let upperLegs: Double
    let lowerLegs: Double
}

extension ClothingOption {
    // Body-part BSA% exposures — Lund-Browder adult chart.
    // Head=7%, Neck=2%, UpperArms=8%, Forearms=6%, Hands=5%,
    // Torso(ant+post)=36%, UpperLegs=19%, LowerLegs=14%.
    // Values here are exposed fractions of each region per
    // clothing option. Ordered head-to-toe.
    var bodyPartExposure: BodyPartExposure {
        switch self {
        case .fullyCovered:
            // Only head exposed — hat/hood not assumed
            return BodyPartExposure(
                head: 7, neck: 0, upperArms: 0, forearms: 0, hands: 0,
                torso: 0, upperLegs: 0, lowerLegs: 0)
        case .longSleevesPants:
            // Head, neck, hands exposed
            return BodyPartExposure(
                head: 7, neck: 2, upperArms: 0, forearms: 0, hands: 5,
                torso: 0, upperLegs: 0, lowerLegs: 0)
        case .tshirtPants:
            // Head, neck, forearms, hands (short sleeves cover upper arms)
            return BodyPartExposure(
                head: 7, neck: 2, upperArms: 0, forearms: 6, hands: 5,
                torso: 0, upperLegs: 0, lowerLegs: 0)
        case .tshirtShorts:
            // Head, neck, upper arms, forearms, hands, lower legs
            return BodyPartExposure(
                head: 7, neck: 2, upperArms: 8, forearms: 6, hands: 5,
                torso: 0, upperLegs: 0, lowerLegs: 8)
        case .tankShorts:
            // Above + partial torso exposure + partial upper legs
            return BodyPartExposure(
                head: 7, neck: 2, upperArms: 8, forearms: 6, hands: 5,
                torso: 9, upperLegs: 8, lowerLegs: 8)
        case .swimwear:
            // Near full body — swimsuit covers ~20% (pelvis/buttocks)
            // Torso: ant(18)+post(18)-swimsuit(~10) = 26%
            // UpperLegs: 19 - swimsuit overlap (~7) = 12%
            return BodyPartExposure(
                head: 7, neck: 2, upperArms: 8, forearms: 6, hands: 5,
                torso: 26, upperLegs: 12, lowerLegs: 14)
        }
    }
}

// Body part SED — ordered head to toe, neck added
struct BodyPartSED: Codable {
    let head:      Double
    let neck:      Double
    let upperArms: Double
    let forearms:  Double
    let hands:     Double
    let torso:     Double
    let upperLegs: Double
    let lowerLegs: Double

    static func compute(baseSED: Double,
                        clothing: ClothingOption) -> BodyPartSED {
        let bp    = clothing.bodyPartExposure
        let total = clothing.bsaPercent
        guard total > 0 else {
            return BodyPartSED(head: 0, neck: 0, upperArms: 0,
                               forearms: 0, hands: 0, torso: 0,
                               upperLegs: 0, lowerLegs: 0)
        }
        return BodyPartSED(
            head:      baseSED * bp.head      / total,
            neck:      baseSED * bp.neck      / total,
            upperArms: baseSED * bp.upperArms / total,
            forearms:  baseSED * bp.forearms  / total,
            hands:     baseSED * bp.hands     / total,
            torso:     baseSED * bp.torso     / total,
            upperLegs: baseSED * bp.upperLegs / total,
            lowerLegs: baseSED * bp.lowerLegs / total)
    }

    // Ordered head-to-toe for display
    var asOrderedPairs: [(String, Double)] {
        [("Head",       head),
         ("Neck",       neck),
         ("Upper Arms", upperArms),
         ("Forearms",   forearms),
         ("Hands",      hands),
         ("Torso",      torso),
         ("Upper Legs", upperLegs),
         ("Lower Legs", lowerLegs)]
    }

    var asDictionary: [String: Double] {
        Dictionary(uniqueKeysWithValues: asOrderedPairs)
    }

    var mostExposed: (String, Double) {
        asOrderedPairs.max(by: { $0.1 < $1.1 }) ?? ("None", 0)
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
    // intervalHours defaults to 5-min slice for old readings
    var intervalHours: Double   = 5.0 / 60.0
    let sed:           Double
    let bsaPercent:    Double
    let oralUg:        Double
    let plasmaLevel:   Double
    let indoors:       Bool
    let bodyPartSED:   BodyPartSED
    let clothingName:  String
    // Defaults to false for old readings that predate this field
    var isUncertain:   Bool     = false
    // nil for auto readings, set for Log Now readings
    var label:         String?  = nil
    // GPS coords — default to 0 for old readings
    var lat:           Double   = 0.0
    var lon:           Double   = 0.0
    var gpsAccuracy:   Double   = 0.0
    // What the OSM auto-detector originally said before any user correction.
    // Defaults to same as indoors for old readings (no correction history).
    // Set from corrections.csv retroactive patch on first launch.
    var autoIndoors:   Bool?    = nil

    // Resolved auto value — falls back to indoors if not patched yet
    var autoIndoorsResolved: Bool { autoIndoors ?? indoors }
}

struct FoodLogEntry: Codable, Identifiable {
    var id         = UUID()
    let name:        String
    let brand:       String
    let vitaminDug:  Double
    let servingDesc: String
    let date:        Date
}
