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
    // Matched to bsa.py Lund-Browder chart values
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

struct DayReading: Codable, Identifiable {
    var id        = UUID()
    let date:          Date
    let uvi:           Double
    let daylightHours: Double
    let sed:           Double
    let bsaPercent:    Double
    let oralUg:        Double
    let plasmaLevel:   Double
}

struct UserProfile: Codable {
    var age:          Int            = 22
    var skinType:     SkinType       = .typeI_II
    var clothing:     ClothingOption = .tshirtPants
    var oralIU:       Double         = 0.0
    var initialLevel: Double         = 50.0
    var oralUg: Double { oralIU / 40.0 }
}

struct VitaminDEngine {

    static func ageFactor(_ age: Int) -> Double {
        1.0 - 0.013 * Double(age - 20)
    }

    static func uviToSED(uvi: Double, daylightHours: Double) -> Double {
        uvi * 0.025 * daylightHours * 3600.0 / (2.0 * 100.0)
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

    static func computeC_sun(
        uvDoses: [Double],
        bodyAreas: [Double],
        age: Int,
        skinType: SkinType
    ) -> [Double] {
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

    static func runModel(
        oralDoses: [Double],
        uvDoses:   [Double],
        bodyAreas: [Double],
        age:       Int,
        skinType:  SkinType,
        C0:        Double = 50.0
    ) -> [Double] {
        let N      = oralDoses.count
        let C_oral = computeC_oral(oralDoses)
        let C_sun  = computeC_sun(
            uvDoses: uvDoses, bodyAreas: bodyAreas,
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

    static func singleDayEstimate(
        uvi: Double, daylightHours: Double,
        bsaPercent: Double, age: Int,
        skinType: SkinType, oralUg: Double,
        C0: Double = 50.0
    ) -> Double {
        let sed = uviToSED(uvi: uvi, daylightHours: daylightHours)
        return runModel(
            oralDoses: [oralUg],
            uvDoses:   [sed],
            bodyAreas: [bsaPercent],
            age: age, skinType: skinType, C0: C0
        ).first ?? C0
    }
}
