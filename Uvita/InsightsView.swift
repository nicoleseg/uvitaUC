import SwiftUI

struct InsightsView: View {
    @EnvironmentObject var store: DataStore
    @State var selectedRange     = 0
    @State var projectionWindow: Int = 14
    let ranges = ["7 days", "14 days", "30 days"]

    var daysToShow: Int {
        switch selectedRange {
        case 0:  return 7
        case 1:  return 14
        default: return 30
        }
    }

    // Uses DataStore.longitudinalModel() which aggregates
    // readings into daily totals before running Eq. 8
    var longitudinalData: [DataStore.DayModelResult] {
        store.longitudinalModel(daysBack: daysToShow)
    }

    var totalUV: Double {
        longitudinalData.map { $0.uvContrib }.reduce(0, +)
    }
    var totalOral: Double {
        longitudinalData.map { $0.oralContrib }.reduce(0, +)
    }
    var totalCombined: Double {
        longitudinalData.last?.total ?? store.profile.initialLevel
    }

    // Projection window — uses daily aggregates too
    struct ProjDay {
        let uvDose:   Double
        let oralDose: Double
        let bsa:      Double
    }

    var projWindowDays: [ProjDay] {
        let cal   = Calendar.current
        var dayMap: [Date: (uv: Double, oral: Double, bsa: Double)] = [:]
        for r in store.readings {
            let day = cal.startOfDay(for: r.date)
            dayMap[day] = (
                uv:   (dayMap[day]?.uv ?? 0) + r.sed,
                oral: r.oralUg,
                bsa:  r.bsaPercent)
        }
        return Array(dayMap.values
            .sorted { _ , _ in false }
            .prefix(projectionWindow))
            .map { ProjDay(uvDose: $0.uv, oralDose: $0.oral, bsa: $0.bsa) }
    }

    var actualWindowDays: Int { projWindowDays.count }

    var windowAvgSED:  Double {
        guard !projWindowDays.isEmpty else { return 0 }
        return projWindowDays.map { $0.uvDose }.reduce(0,+) / Double(projWindowDays.count)
    }
    var windowAvgBSA:  Double {
        guard !projWindowDays.isEmpty else { return 0 }
        return projWindowDays.map { $0.bsa }.reduce(0,+) / Double(projWindowDays.count)
    }
    var windowAvgOral: Double {
        guard !projWindowDays.isEmpty else { return 0 }
        return projWindowDays.map { $0.oralDose }.reduce(0,+) / Double(projWindowDays.count)
    }

    // Observed days (corrected) — solid colored line
    var observedCorrected: [Double] {
        longitudinalData.map { $0.total }
    }

    // Observed days (raw auto) — dashed gray line
    var observedRaw: [Double] {
        store.rawLongitudinalModel(daysBack: daysToShow).map { $0.total }
    }

    // Projected days (corrected) continuing from last observed C_total
    var projectedCorrected: [Double] {
        guard !projWindowDays.isEmpty else { return [] }
        let C0 = observedCorrected.last ?? store.profile.initialLevel
        let n  = max(1, 90 - observedCorrected.count)
        return VitaminDEngine.runModel(
            oralDoses: Array(repeating: windowAvgOral, count: n),
            uvDoses:   Array(repeating: windowAvgSED,  count: n),
            bodyAreas: Array(repeating: windowAvgBSA,  count: n),
            age:       store.profile.age,
            skinType:  store.profile.skinType,
            C0:        C0)
    }

    // Projected days (raw) continuing from last observed raw C_total
    var projectedRaw: [Double] {
        guard !projWindowDays.isEmpty else { return [] }
        let rawActuals = store.rawLongitudinalModel(daysBack: daysToShow)
        let C0 = rawActuals.last?.total ?? store.profile.initialLevel
        let n  = max(1, 90 - rawActuals.count)
        return store.rawAutoProjection(windowDays: projectionWindow,
                                       C0override: C0,
                                       nDays: n)
    }

    var projectionsHaveDiff: Bool {
        let maxDiff = zip(projectedCorrected, projectedRaw)
            .map { abs($0 - $1) }.max() ?? 0
        return maxDiff > 0.1
    }

    var projectionEndDate: Date {
        Calendar.current.date(byAdding: .day, value: 89, to: Date()) ?? Date()
    }

    var daysToEscapeDeficiency: Int? {
        projectedCorrected.firstIndex { $0 >= 30 }.map { $0 + 1 }
    }
    var daysToSufficiency: Int? {
        projectedCorrected.firstIndex { $0 >= 50 }.map { $0 + 1 }
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

                        // Range picker with date label
                        VStack(spacing: 4) {
                            Picker("Range", selection: $selectedRange) {
                                ForEach(0..<ranges.count, id: \.self) {
                                    Text(ranges[$0]).tag($0)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal)

                            if let first = longitudinalData.first,
                               let last  = longitudinalData.last {
                                let fmt = DateFormatter()
                                let _   = { fmt.dateFormat = "MMM d" }()
                                Text("\(fmt.string(from: first.date)) – \(fmt.string(from: last.date))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Day-by-day plasma chart
                        if !longitudinalData.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Plasma 25(OH)D — Day by Day")
                                    .font(.headline).padding(.horizontal)
                                Text("One point per calendar day · Eq. 8 (Diffey 2013)")
                                    .font(.caption2).foregroundColor(.secondary)
                                    .padding(.horizontal)
                                LongitudinalLineChart(
                                    data: longitudinalData,
                                    baseline: store.profile.initialLevel)
                                    .frame(height: 220).padding(.horizontal)
                            }
                            .padding(.vertical)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(16).padding(.horizontal)
                        }

                        // Combined contribution section
                        if !longitudinalData.isEmpty {
                            CombinedContributionCard(
                                uvContrib:   totalUV,
                                oralContrib: totalOral,
                                baseline:    store.profile.initialLevel,
                                total:       totalCombined,
                                daysToShow:  daysToShow)
                        }

                        BodyPartSEDCard()

                        // 90-day projection
                        VStack(alignment: .leading, spacing: 10) {
                            Text("90-Day Projection")
                                .font(.headline).padding(.horizontal)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Average over most recent:")
                                    .font(.caption).foregroundColor(.secondary)
                                HStack(spacing: 8) {
                                    ForEach([7, 14, 21, 30], id: \.self) { days in
                                        ProjectionWindowButton(
                                            days: days,
                                            selected: projectionWindow == days
                                        ) { projectionWindow = days }
                                    }
                                    Spacer()
                                    Text("(\(actualWindowDays) days data)")
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                            }.padding(.horizontal)

                            // C0 read-only — edit in Profile
                            HStack {
                                Text("Starting plasma (C₀)")
                                    .font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Text(String(format: "%.0f nmol/L",
                                            store.profile.initialLevel))
                                    .font(.caption).fontWeight(.semibold)
                                    .foregroundColor(store.profile.initialLevel < 30
                                        ? .red : store.profile.initialLevel < 50
                                        ? .orange : .green)
                                Text("· set in Profile")
                                    .font(.caption2).foregroundColor(.secondary)
                            }.padding(.horizontal)

                            if !projectedCorrected.isEmpty {
                                HStack(spacing: 10) {
                                    StatMiniCard(
                                        label: "Avg SED (\(actualWindowDays)d)",
                                        value: String(format: "%.4f", windowAvgSED),
                                        color: .orange)
                                    StatMiniCard(
                                        label: "Escapes deficiency",
                                        sublabel: "(≥30 nmol/L)",
                                        value: daysToEscapeDeficiency.map { "Day \($0)" } ?? "Not in 90d",
                                        color: daysToEscapeDeficiency != nil ? .green : .red)
                                    StatMiniCard(
                                        label: "Reaches sufficiency",
                                        sublabel: "(≥50 nmol/L)",
                                        value: daysToSufficiency.map { "Day \($0)" } ?? "Not in 90d",
                                        color: daysToSufficiency != nil ? .green : .red)
                                }.padding(.horizontal)

                                ProjectionChart(
                                    observed:          observedCorrected,
                                    observedRaw:       observedRaw,
                                    projected:         projectedCorrected,
                                    projectedRaw:      projectionsHaveDiff ? projectedRaw : nil,
                                    startDate:         longitudinalData.first?.date ?? Date(),
                                    endDate:           projectionEndDate)
                                    .frame(height: 260).padding(.horizontal)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 14) {
                                        HStack(spacing: 5) {
                                            Rectangle().fill(Color.teal)
                                                .frame(width: 16, height: 2.5)
                                            Text("Observed (corrected)")
                                                .font(.caption2).foregroundColor(.secondary)
                                        }
                                        HStack(spacing: 5) {
                                            HStack(spacing: 2) {
                                                ForEach(0..<3, id: \.self) { _ in
                                                    Rectangle().fill(Color.teal)
                                                        .frame(width: 4, height: 2.5)
                                                }
                                            }
                                            Text("Projected (corrected)")
                                                .font(.caption2).foregroundColor(.secondary)
                                        }
                                    }
                                    HStack(spacing: 14) {
                                        HStack(spacing: 5) {
                                            Rectangle().fill(Color.gray.opacity(0.5))
                                                .frame(width: 16, height: 2)
                                            Text("Observed (auto only)")
                                                .font(.caption2).foregroundColor(.secondary)
                                        }
                                        HStack(spacing: 5) {
                                            HStack(spacing: 2) {
                                                ForEach(0..<3, id: \.self) { _ in
                                                    Rectangle().fill(Color.gray.opacity(0.5))
                                                        .frame(width: 4, height: 2)
                                                }
                                            }
                                            Text("Projected (auto only)")
                                                .font(.caption2).foregroundColor(.secondary)
                                        }
                                        if !projectionsHaveDiff {
                                            Text("· lines identical")
                                                .font(.caption2).foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding(.horizontal)

                                Text("14d window recommended — matches 25-day plasma half-life.")
                                    .font(.caption2).foregroundColor(.secondary)
                                    .padding(.horizontal)
                            } else {
                                Text("Track at least one day to generate a projection.")
                                    .font(.caption).foregroundColor(.secondary).padding()
                            }
                        }
                        .padding(.vertical)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(16).padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Model Insights")
        }
    }
}

struct ProjectionWindowButton: View {
    let days:     Int
    let selected: Bool
    let action:   () -> Void
    var body: some View {
        Button(action: action) {
            let bg: Color  = selected ? .blue : Color.gray.opacity(0.06)
            let fg: Color  = selected ? .white : .primary
            Text("\(days)d")
                .font(.caption).fontWeight(.semibold)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(bg).foregroundColor(fg)
                .cornerRadius(8)
        }
    }
}

struct StatMiniCard: View {
    let label:    String
    var sublabel: String? = nil
    let value:    String
    let color:    Color
    var body: some View {
        VStack(spacing: 3) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            if let sub = sublabel {
                Text(sub).font(.system(size: 10)).foregroundColor(.secondary)
            }
            Text(value).font(.subheadline).fontWeight(.bold).foregroundColor(color)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(Color.gray.opacity(0.06)).cornerRadius(10)
    }
}

// ── Longitudinal line chart ───────────────────────────────────
struct LongitudinalLineChart: View {
    let data: [DataStore.DayModelResult]
    let baseline: Double

    var minVal: Double {
        min(baseline - 5, data.map { $0.total }.min() ?? baseline)
    }
    var maxVal: Double {
        max(baseline + 20, data.map { $0.total }.max() ?? baseline + 20)
    }
    var range: Double { max(1, maxVal - minVal) }

    var endDateLabel: String {
        guard let last = data.last else { return "" }
        let fmt = DateFormatter(); fmt.dateFormat = "MMM d"
        return fmt.string(from: last.date)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height - 24
            let n = data.count
            ZStack(alignment: .bottomLeading) {
                let y50 = h - h * CGFloat((50 - minVal) / range)
                let y30 = h - h * CGFloat((30 - minVal) / range)

                Rectangle().fill(Color.green.opacity(0.25))
                    .frame(height: 1).offset(y: y50)
                Text("50").font(.system(size: 8)).foregroundColor(.green)
                    .offset(x: 2, y: y50 - 10)
                Rectangle().fill(Color.red.opacity(0.25))
                    .frame(height: 1).offset(y: y30)
                Text("30").font(.system(size: 8)).foregroundColor(.red)
                    .offset(x: 2, y: y30 - 10)

                if n >= 2 {
                    Path { path in
                        for i in 0..<n {
                            let x = w * CGFloat(i) / CGFloat(n - 1)
                            let y = h - h * CGFloat((data[i].total - minVal) / range)
                            i == 0 ? path.move(to: .init(x: x, y: y))
                                   : path.addLine(to: .init(x: x, y: y))
                        }
                    }.stroke(Color.teal, lineWidth: 2.5)
                }

                ForEach(0..<n, id: \.self) { i in
                    let x = w * CGFloat(i) / CGFloat(max(1, n-1))
                    let y = h - h * CGFloat((data[i].total - minVal) / range)
                    Circle()
                        .fill(data[i].total < 30 ? Color.red
                              : data[i].total < 50 ? Color.orange : Color.teal)
                        .frame(width: 8, height: 8).position(x: x, y: y)
                    if i == 0 || i == n-1 || i % 2 == 0 {
                        Text(data[i].label).font(.system(size: 8))
                            .foregroundColor(.secondary).position(x: x, y: h + 12)
                    }
                }

                if !endDateLabel.isEmpty && n >= 1 {
                    Text(endDateLabel).font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.teal)
                        .position(x: max(40, w - 6), y: h + 22)
                }
            }
        }
    }
}





// ── Projection chart — segment-colored by value ───────────────
// rawData is optional second line showing auto-detection only
struct ProjectionChart: View {
    let data:      [Double]
    var rawData:   [Double]? = nil
    let startDate: Date
    let endDate:   Date

    var allValues: [Double] { data + (rawData ?? []) }
    var minVal: Double { 20.0 }
    var maxVal: Double { max(60, allValues.max() ?? 60) }
    var range:  Double { maxVal - minVal }

    var endDateLabel: String {
        let fmt = DateFormatter(); fmt.dateFormat = "MMM d"
        return fmt.string(from: endDate)
    }
    func lineColor(_ v: Double) -> Color {
        v < 30 ? .red : v < 50 ? .orange : .green
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height - 28
            let n = data.count
            ZStack(alignment: .bottomLeading) {
                let y30 = h - h * CGFloat((30 - minVal) / range)
                let y50 = h - h * CGFloat((50 - minVal) / range)

                Rectangle().fill(Color.red.opacity(0.06))
                    .frame(width: w, height: h - y30).offset(y: y30)
                Rectangle().fill(Color.green.opacity(0.06))
                    .frame(width: w, height: y50)
                Rectangle().fill(Color.green.opacity(0.4))
                    .frame(height: 1).offset(y: y50)
                Text("50 sufficient").font(.system(size: 8)).foregroundColor(.green)
                    .offset(x: 2, y: y50 - 10)
                Rectangle().fill(Color.red.opacity(0.4))
                    .frame(height: 1).offset(y: y30)
                Text("30 deficient").font(.system(size: 8)).foregroundColor(.red)
                    .offset(x: 2, y: y30 - 10)

                // Raw auto line — dashed gray, drawn first (behind)
                if let raw = rawData, raw.count >= 2 {
                    Path { p in
                        for i in 0..<raw.count {
                            let x = w * CGFloat(i) / CGFloat(raw.count - 1)
                            let y = h - h * CGFloat((raw[i] - minVal) / range)
                            i == 0 ? p.move(to: .init(x: x, y: y))
                                   : p.addLine(to: .init(x: x, y: y))
                        }
                    }
                    .stroke(Color.gray.opacity(0.5),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }

                // Corrected line — colored by plasma value, drawn on top
                if n >= 2 {
                    ForEach(0..<(n-1), id: \.self) { i in
                        let x1 = w * CGFloat(i)   / CGFloat(n-1)
                        let x2 = w * CGFloat(i+1) / CGFloat(n-1)
                        let y1 = h - h * CGFloat((data[i]   - minVal) / range)
                        let y2 = h - h * CGFloat((data[i+1] - minVal) / range)
                        Path { p in
                            p.move(to: .init(x: x1, y: y1))
                            p.addLine(to: .init(x: x2, y: y2))
                        }.stroke(lineColor(data[i]), lineWidth: 2.5)
                    }
                }

                ForEach([0,14,29,44,59,74,89], id: \.self) { i in
                    if i < n {
                        let x = w * CGFloat(i) / CGFloat(n-1)
                        Text("D\(i+1)").font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .position(x: x, y: h + 10)
                    }
                }
                Text(endDateLabel).font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .position(x: w - 20, y: h + 22)
            }
        }
    }
}

// ── Combined contribution card ────────────────────────────────
// Single card replacing the old "Vitamin D by Source" +
// "Contribution Breakdown" pair. Stacked horizontal bar with
// percentages inside each segment, nmol/L values below.
struct CombinedContributionCard: View {
    let uvContrib:   Double
    let oralContrib: Double
    let baseline:    Double
    let total:       Double
    let daysToShow:  Int

    var netGain: Double { max(0.01, uvContrib + oralContrib) }
    var uvPct:   Double { uvContrib   / netGain * 100 }
    var orPct:   Double { oralContrib / netGain * 100 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            VStack(alignment: .leading, spacing: 2) {
                Text("Vitamin D Contribution")
                    .font(.headline)
                Text("Cumulative over \(daysToShow)-day window · UV vs oral split")
                    .font(.caption2).foregroundColor(.secondary)
            }

            // Stacked horizontal bar
            GeometryReader { geo in
                let w = geo.size.width
                let uvW   = CGFloat(uvPct   / 100) * w
                let orW   = CGFloat(orPct   / 100) * w
                ZStack(alignment: .leading) {
                    // UV segment
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange)
                        .frame(width: max(uvW, 2), height: 36)
                    // Oral segment
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue)
                        .frame(width: max(orW, 2), height: 36)
                        .offset(x: uvW)
                    // UV label inside bar
                    if uvW > 44 {
                        Text(String(format: "%.0f%%", uvPct))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .offset(x: uvW / 2 - 14)
                    }
                    // Oral label inside bar
                    if orW > 44 {
                        Text(String(format: "%.0f%%", orPct))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .offset(x: uvW + orW / 2 - 14)
                    }
                }
            }
            .frame(height: 36)

            // Values row below bar
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Circle().fill(Color.orange).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("UV synthesis").font(.caption2).foregroundColor(.secondary)
                        Text(String(format: "+%.3f nmol/L", uvContrib))
                            .font(.caption).fontWeight(.semibold).foregroundColor(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    Circle().fill(Color.blue).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Oral intake").font(.caption2).foregroundColor(.secondary)
                        Text(String(format: "+%.3f nmol/L", oralContrib))
                            .font(.caption).fontWeight(.semibold).foregroundColor(.blue)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 1) {
                    Text("Total level").font(.caption2).foregroundColor(.secondary)
                    Text(String(format: "%.1f nmol/L", total))
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(total < 30 ? .red : total < 50 ? .orange : .green)
                }
            }

            // Context note
            HStack(spacing: 4) {
                Image(systemName: uvPct > 60
                    ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.caption).foregroundColor(uvPct > 60 ? .green : .orange)
                Text(uvPct > 60
                     ? "UV dominant — matches literature (73–98%)"
                     : "Oral dominant — possibly limited UV exposure recently")
                    .font(.caption2)
                    .foregroundColor(uvPct > 60 ? .green : .orange)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
        .padding(.horizontal)
    }
}