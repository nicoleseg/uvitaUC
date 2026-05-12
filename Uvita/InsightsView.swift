import SwiftUI

struct InsightsView: View {
    @EnvironmentObject var store: DataStore
    @State var selectedRange      = 0
    @State var projectionBaseline: Double = 25.0
    @State var projectionWindow:   Int    = 14
    let ranges = ["7 days", "14 days", "30 days"]

    var daysToShow: Int {
        switch selectedRange {
        case 0:  return 7
        case 1:  return 14
        default: return 30
        }
    }

    var longitudinalData: [(label: String,
                            total: Double,
                            uvContrib: Double,
                            oralContrib: Double)] {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        var dayMap: [Date: DayReading] = [:]
        for r in store.readings {
            let day = cal.startOfDay(for: r.date)
            dayMap[day] = r
        }
        guard let cutoff = cal.date(
            byAdding: .day,
            value: -(daysToShow - 1),
            to: today) else { return [] }
        let sorted = dayMap
            .filter { $0.key >= cutoff }
            .sorted { $0.key < $1.key }
        guard !sorted.isEmpty else { return [] }

        let uvDoses   = sorted.map { $0.value.sed }
        let bsas      = sorted.map { $0.value.bsaPercent }
        let oralDoses = sorted.map { $0.value.oralUg }
        let n         = sorted.count

        let totals = VitaminDEngine.runModel(
            oralDoses: oralDoses, uvDoses: uvDoses,
            bodyAreas: bsas,
            age: store.profile.age,
            skinType: store.profile.skinType,
            C0: store.profile.initialLevel)

        let uvOnly = VitaminDEngine.runModel(
            oralDoses: Array(repeating: 0, count: n),
            uvDoses: uvDoses, bodyAreas: bsas,
            age: store.profile.age,
            skinType: store.profile.skinType,
            C0: store.profile.initialLevel)

        let oralOnly = VitaminDEngine.runModel(
            oralDoses: oralDoses,
            uvDoses: Array(repeating: 0, count: n),
            bodyAreas: bsas,
            age: store.profile.age,
            skinType: store.profile.skinType,
            C0: store.profile.initialLevel)

        return sorted.enumerated().map { i, pair in
            let fmt = DateFormatter()
            fmt.dateFormat = "M/d"
            return (
                label: fmt.string(from: pair.key),
                total: totals[i],
                uvContrib: max(0, uvOnly[i] -
                    store.profile.initialLevel),
                oralContrib: max(0, oralOnly[i] -
                    store.profile.initialLevel))
        }
    }

    var totalUV: Double {
        longitudinalData.map { $0.uvContrib }.reduce(0,+)
    }
    var totalOral: Double {
        longitudinalData.map { $0.oralContrib }.reduce(0,+)
    }
    var totalCombined: Double {
        longitudinalData.last?.total
            ?? store.profile.initialLevel
    }

    var windowReadings: [DayReading] {
        let cal = Calendar.current
        var dayMap: [Date: DayReading] = [:]
        for r in store.readings {
            let day = cal.startOfDay(for: r.date)
            dayMap[day] = r
        }
        return Array(
            dayMap.values
                .sorted { $0.date > $1.date }
                .prefix(projectionWindow))
    }

    var actualWindowDays: Int { windowReadings.count }

    var windowAvgSED: Double {
        guard !windowReadings.isEmpty else { return 0 }
        return windowReadings.map { $0.sed }.reduce(0,+)
            / Double(windowReadings.count)
    }
    var windowAvgBSA: Double {
        guard !windowReadings.isEmpty else { return 0 }
        return windowReadings
            .map { $0.bsaPercent }.reduce(0,+)
            / Double(windowReadings.count)
    }
    var windowAvgOral: Double {
        guard !windowReadings.isEmpty else { return 0 }
        return windowReadings.map { $0.oralUg }.reduce(0,+)
            / Double(windowReadings.count)
    }

    var projection90: [Double] {
        guard !windowReadings.isEmpty else { return [] }
        let uvDoses   = Array(repeating: windowAvgSED,
                              count: 90)
        let bsas      = Array(repeating: windowAvgBSA,
                              count: 90)
        let oralDoses = Array(repeating: windowAvgOral,
                              count: 90)
        return VitaminDEngine.runModel(
            oralDoses: oralDoses,
            uvDoses:   uvDoses,
            bodyAreas: bsas,
            age:       store.profile.age,
            skinType:  store.profile.skinType,
            C0:        projectionBaseline)
    }

    var daysToEscapeDeficiency: Int? {
        projection90.firstIndex { $0 >= 30 }
            .map { $0 + 1 }
    }
    var daysToSufficiency: Int? {
        projection90.firstIndex { $0 >= 50 }
            .map { $0 + 1 }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {

                    if store.readings.isEmpty {
                        Text("No data yet — start tracking on the Today tab and come back after a few days.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(32)
                    } else {

                        Picker("Range",
                               selection: $selectedRange) {
                            ForEach(0..<ranges.count,
                                    id: \.self) {
                                Text(ranges[$0]).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)

                        // Chart 1: Longitudinal
                        if !longitudinalData.isEmpty {
                            VStack(alignment: .leading,
                                   spacing: 8) {
                                Text("Plasma 25(OH)D — Day by Day")
                                    .font(.headline)
                                    .padding(.horizontal)
                                Text("Running C_total(T) via Eqs. 8-11")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                                LongitudinalLineChart(
                                    data: longitudinalData,
                                    baseline:
                                        store.profile.initialLevel)
                                    .frame(height: 220)
                                    .padding(.horizontal)
                            }
                            .padding(.vertical)
                            .background(Color(
                                .secondarySystemBackground))
                            .cornerRadius(16)
                            .padding(.horizontal)
                        }

                        if !longitudinalData.isEmpty {

                            HStack(alignment: .top,
                                   spacing: 20) {

                                // LEFT: stacked contribution bar
                                VStack(alignment: .leading,
                                       spacing: 8) {

                                    Text("Vitamin D by Source")
                                        .font(.headline)

                                    Text(
                                        "Cumulative modeled contribution over selected window"
                                    )
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                    ContributionBar(
                                        uvContrib: totalUV,
                                        oralContrib: totalOral,
                                        baseline: store.profile.initialLevel,
                                        total: totalCombined
                                    )
                                    .frame(width: 110, height: 100)
                                    .padding(.leading, 65)
                                }
                                .frame(maxWidth: .infinity)
                                .background(
                                    Color(.secondarySystemBackground)
                                )
                                .cornerRadius(16)

                                // RIGHT: percentage breakdown
                                VStack(alignment: .leading,
                                       spacing: 8) {

                                    Text("Contribution Breakdown")
                                        .font(.headline)

                                    let netGain = max(
                                        0.01,
                                        totalUV + totalOral
                                    )

                                    let uvPct =
                                        totalUV / netGain * 100

                                    let orPct =
                                        totalOral / netGain * 100

                                    HStack(spacing: 10) {

                                        ContribCard(
                                            label: "UV synthesis",
                                            value: String(
                                                format: "%.1f%%",
                                                uvPct
                                            ),
                                            sub: String(
                                                format: "+%.2f nmol/L",
                                                totalUV
                                            ),
                                            color: .orange
                                        )
                                        .scaleEffect(0.88)

                                        ContribCard(
                                            label: "Oral intake",
                                            value: String(
                                                format: "%.1f%%",
                                                orPct
                                            ),
                                            sub: String(
                                                format: "+%.2f nmol/L",
                                                totalOral
                                            ),
                                            color: .blue
                                        )
                                        .scaleEffect(0.88)
                                    }

                                    VStack(alignment: .leading,
                                           spacing: 4) {

                                        Text(
                                            uvPct > 60
                                            ? "Matches paper — UV dominant"
                                            : "UV lower than expected — possibly indoors often"
                                        )
                                        .font(.caption2)
                                        .foregroundColor(
                                            uvPct > 60
                                            ? .green
                                            : .orange
                                        )
                                    }
                                    .padding(10)
                                    .background(
                                        Color(.tertiarySystemBackground)
                                    )
                                    .cornerRadius(10)
                                }
                                .frame(maxWidth: .infinity,
                                       alignment: .topLeading)
                                .padding()
                                .background(
                                    Color(.secondarySystemBackground)
                                )
                                .cornerRadius(16)
                            }
                            .padding(.horizontal)
                        }

                        // ── Body part SED card ─────────────────
                        
                        BodyPartSEDCard()
                        

                        // 90-day projection
                        VStack(alignment: .leading,
                               spacing: 10) {
                            Text("90-Day Projection")
                                .font(.headline)
                                .padding(.horizontal)

                            // Window picker
                            VStack(alignment: .leading,
                                   spacing: 6) {
                                Text("Average over most recent:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack(spacing: 8) {
                                    ForEach([7, 14, 21, 30],
                                            id: \.self) { days in
                                        Button {
                                            projectionWindow = days
                                        } label: {
                                            Text("\(days)d")
                                                .font(.caption)
                                                .fontWeight(
                                                    .semibold)
                                                .padding(
                                                    .horizontal, 12)
                                                .padding(
                                                    .vertical, 6)
                                                .background(
                                                    projectionWindow
                                                    == days
                                                    ? Color.blue
                                                    : Color(.tertiarySystemBackground))
                                                .foregroundColor(
                                                    projectionWindow
                                                    == days
                                                    ? .white
                                                    : .primary)
                                                .cornerRadius(8)
                                        }
                                    }
                                    Spacer()
                                    Text("(\(actualWindowDays) days)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Text(actualWindowDays < projectionWindow
                                    ? "Only \(actualWindowDays) days tracked."
                                    : "14d recommended. Matches plasma half-life.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)

                            // C0 input
                            VStack(alignment: .leading,
                                   spacing: 6) {
                                Text("Starting plasma level (C0)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack {
                                    TextField("25",
                                        value: $projectionBaseline,
                                        format: .number)
                                        .keyboardType(.decimalPad)
                                        .textFieldStyle(
                                            .roundedBorder)
                                        .frame(width: 70)
                                    Text("nmol/L")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(
                                        projectionBaseline < 30
                                        ? "Deficient"
                                        : projectionBaseline < 50
                                        ? "Insufficient"
                                        : "Sufficient")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(
                                            projectionBaseline < 30
                                            ? .red
                                            : projectionBaseline < 50
                                            ? .orange : .green)
                                }
                                Text("Paper uses 25 nmol/L. Enter blood test result if known.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)

                            // Summary cards
                            if !projection90.isEmpty {
                                HStack(spacing: 10) {
                                    VStack(spacing: 4) {
                                        Text("Avg SED (\(actualWindowDays)d)")
                                            .font(.caption2)
                                            .foregroundColor(
                                                .secondary)
                                        Text(String(format: "%.4f",
                                            windowAvgSED))
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundColor(.orange)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color(
                                        .tertiarySystemBackground))
                                    .cornerRadius(10)

                                    VStack(spacing: 4) {
                                        Text("Escapes deficiency")
                                            .font(.caption2)
                                            .foregroundColor(
                                                .secondary)
                                        if let d =
                                            daysToEscapeDeficiency {
                                            Text("Day \(d)")
                                                .font(.subheadline)
                                                .fontWeight(.bold)
                                                .foregroundColor(
                                                    .green)
                                        } else {
                                            Text("Not in 90 days")
                                                .font(.caption)
                                                .foregroundColor(
                                                    .red)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color(
                                        .tertiarySystemBackground))
                                    .cornerRadius(10)

                                    VStack(spacing: 4) {
                                        Text("Reaches sufficiency")
                                            .font(.caption2)
                                            .foregroundColor(
                                                .secondary)
                                        if let d =
                                            daysToSufficiency {
                                            Text("Day \(d)")
                                                .font(.subheadline)
                                                .fontWeight(.bold)
                                                .foregroundColor(
                                                    .green)
                                        } else {
                                            Text("Not in 90 days")
                                                .font(.caption)
                                                .foregroundColor(
                                                    .red)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color(
                                        .tertiarySystemBackground))
                                    .cornerRadius(10)
                                }
                                .padding(.horizontal)

                                ProjectionChart(
                                    data: projection90)
                                    .frame(height: 220)
                                    .padding(.horizontal)

                                Text("14d window recommended — matches 25-day plasma half-life (beta, Table I). Switch to 7d if lifestyle recently changed.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                            } else {
                                Text("Track at least one day to generate a projection.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding()
                            }
                        }
                        .padding(.vertical)
                        .background(Color(
                            .secondarySystemBackground))
                        .cornerRadius(16)
                        .padding(.horizontal)

                    } // end if !readings.isEmpty
                }
                .padding(.vertical)
            }
            .navigationTitle("Model Insights")
        }
    }
}

// ── Longitudinal line chart ───────────────────────────────────
struct LongitudinalLineChart: View {
    let data: [(label: String, total: Double,
                uvContrib: Double, oralContrib: Double)]
    let baseline: Double

    var minVal: Double {
        min(baseline - 5,
            data.map { $0.total }.min() ?? baseline)
    }
    var maxVal: Double {
        max(baseline + 20,
            data.map { $0.total }.max() ?? baseline + 20)
    }
    var range: Double { max(1, maxVal - minVal) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height - 24
            let n = data.count

            ZStack(alignment: .bottomLeading) {
                let y50 = h - h * CGFloat(
                    (50 - minVal) / range)
                let y30 = h - h * CGFloat(
                    (30 - minVal) / range)

                Rectangle()
                    .fill(Color.green.opacity(0.25))
                    .frame(height: 1).offset(y: y50)
                Text("50 sufficient")
                    .font(.system(size: 8))
                    .foregroundColor(.green)
                    .offset(x: 2, y: y50 - 10)

                Rectangle()
                    .fill(Color.red.opacity(0.25))
                    .frame(height: 1).offset(y: y30)
                Text("30 deficient")
                    .font(.system(size: 8))
                    .foregroundColor(.red)
                    .offset(x: 2, y: y30 - 10)

                if n >= 2 {
                    Path { path in
                        for i in 0..<n {
                            let x = w * CGFloat(i)
                                / CGFloat(n - 1)
                            let y = h - h * CGFloat(
                                (data[i].total - minVal)
                                / range)
                            if i == 0 {
                                path.move(to:
                                    .init(x: x, y: y))
                            } else {
                                path.addLine(to:
                                    .init(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Color.teal, lineWidth: 2.5)
                }

                ForEach(0..<n, id: \.self) { i in
                    let x = w * CGFloat(i)
                        / CGFloat(max(1, n - 1))
                    let y = h - h * CGFloat(
                        (data[i].total - minVal) / range)
                    Circle()
                        .fill(data[i].total < 30
                              ? Color.red
                              : data[i].total < 50
                              ? Color.orange : Color.teal)
                        .frame(width: 8, height: 8)
                        .position(x: x, y: y)
                    Text(data[i].label)
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                        .position(x: x, y: h + 12)
                }
            }
        }
    }
}

// ── Stacked contribution bar ──────────────────────────────────
struct ContributionBar: View {
    let uvContrib:   Double
    let oralContrib: Double
    let baseline:    Double
    let total:       Double

    var body: some View {
        GeometryReader { geo in
            let w       = geo.size.width * 0.4
            let h       = geo.size.height - 30
            let netGain = max(0.01,
                              uvContrib + oralContrib)
            let scaleH  = h / netGain

            HStack(alignment: .bottom, spacing: 20) {
                VStack(spacing: 0) {
                    Text(String(format: "%.1f nmol/L",
                                total))
                        .font(.system(size: 10,
                                      weight: .bold))
                    ZStack(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: w,
                                   height: CGFloat(baseline)
                                   * scaleH * 0.3)
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.orange)
                                .frame(width: w,
                                       height: max(2,
                                           CGFloat(uvContrib)
                                           * scaleH))
                                .overlay(
                                    uvContrib > netGain * 0.1
                                    ? Text(String(format:
                                        "%.2f", uvContrib))
                                        .font(.system(size: 9))
                                        .foregroundColor(.white)
                                    : nil)
                            Rectangle()
                                .fill(Color.blue)
                                .frame(width: w,
                                       height: max(2,
                                           CGFloat(oralContrib)
                                           * scaleH))
                                .overlay(
                                    oralContrib > netGain * 0.1
                                    ? Text(String(format:
                                        "%.2f", oralContrib))
                                        .font(.system(size: 9))
                                        .foregroundColor(.white)
                                    : nil)
                        }
                    }
                    Text("You")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Rectangle().fill(Color.orange)
                            .frame(width: 14, height: 14)
                            .cornerRadius(2)
                        Text("UV synthesis")
                            .font(.caption)
                    }
                    HStack(spacing: 6) {
                        Rectangle().fill(Color.blue)
                            .frame(width: 14, height: 14)
                            .cornerRadius(2)
                        Text("Oral intake")
                            .font(.caption)
                    }
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.4))
                            .frame(width: 14, height: 14)
                            .cornerRadius(2)
                        Text("Baseline")
                            .font(.caption)
                    }
                    Spacer()
                    Text("Paper avg: UV = 73-98%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 22)
                Spacer()
            }
        }
    }
}

// ── Contribution card ─────────────────────────────────────────
struct ContribCard: View {
    let label: String
    let value: String
    let sub:   String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3).fontWeight(.bold)
                .foregroundColor(color)
            Text(sub)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }
}

// ── 90-day projection chart ───────────────────────────────────
struct ProjectionChart: View {
    let data: [Double]

    var minVal: Double { 20.0 }
    var maxVal: Double { max(60, data.max() ?? 60) }
    var range:  Double { maxVal - minVal }

    var day30: Int? {
        data.firstIndex { $0 >= 30 }.map { $0 + 1 }
    }
    var day50: Int? {
        data.firstIndex { $0 >= 50 }.map { $0 + 1 }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height - 20
            let n = data.count

            ZStack(alignment: .bottomLeading) {
                let y30 = h - h * CGFloat(
                    (30 - minVal) / range)
                let y50 = h - h * CGFloat(
                    (50 - minVal) / range)

                Rectangle()
                    .fill(Color.red.opacity(0.06))
                    .frame(width: w, height: h - y30)
                    .offset(y: y30)
                Rectangle()
                    .fill(Color.green.opacity(0.06))
                    .frame(width: w, height: y50)

                Rectangle()
                    .fill(Color.green.opacity(0.4))
                    .frame(height: 1).offset(y: y50)
                Text("50 sufficient")
                    .font(.system(size: 8))
                    .foregroundColor(.green)
                    .offset(x: 2, y: y50 - 10)

                Rectangle()
                    .fill(Color.red.opacity(0.4))
                    .frame(height: 1).offset(y: y30)
                Text("30 deficient")
                    .font(.system(size: 8))
                    .foregroundColor(.red)
                    .offset(x: 2, y: y30 - 10)

                if n >= 2 {
                    Path { path in
                        for i in 0..<n {
                            let x = w * CGFloat(i)
                                / CGFloat(n - 1)
                            let y = h - h * CGFloat(
                                (data[i] - minVal) / range)
                            if i == 0 {
                                path.move(to:
                                    .init(x: x, y: y))
                            } else {
                                path.addLine(to:
                                    .init(x: x, y: y))
                            }
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [.red, .orange, .green],
                            startPoint: .leading,
                            endPoint: .trailing),
                        lineWidth: 2.5)
                }

                if let d30 = day30, d30 <= n {
                    let x = w * CGFloat(d30 - 1)
                        / CGFloat(n - 1)
                    let y = h - h * CGFloat(
                        (30 - minVal) / range)
                    Circle().fill(Color.orange)
                        .frame(width: 8, height: 8)
                        .position(x: x, y: y)
                    Text("Day \(d30)")
                        .font(.system(size: 8,
                                      weight: .bold))
                        .foregroundColor(.orange)
                        .position(x: x + 22, y: y - 8)
                }
                if let d50 = day50, d50 <= n {
                    let x = w * CGFloat(d50 - 1)
                        / CGFloat(n - 1)
                    let y = h - h * CGFloat(
                        (50 - minVal) / range)
                    Circle().fill(Color.green)
                        .frame(width: 8, height: 8)
                        .position(x: x, y: y)
                    Text("Day \(d50)")
                        .font(.system(size: 8,
                                      weight: .bold))
                        .foregroundColor(.green)
                        .position(x: x + 22, y: y - 8)
                }

                ForEach([0, 14, 29, 44, 59, 74, 89],
                        id: \.self) { i in
                    if i < n {
                        let x = w * CGFloat(i)
                            / CGFloat(n - 1)
                        Text("D\(i + 1)")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .position(x: x, y: h + 10)
                    }
                }
            }
        }
    }
}
