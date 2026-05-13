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
    private struct ProjDay {
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

    var projection90: [Double] {
        guard !projWindowDays.isEmpty else { return [] }
        return VitaminDEngine.runModel(
            oralDoses: Array(repeating: windowAvgOral, count: 90),
            uvDoses:   Array(repeating: windowAvgSED,  count: 90),
            bodyAreas: Array(repeating: windowAvgBSA,  count: 90),
            age:       store.profile.age,
            skinType:  store.profile.skinType,
            C0:        store.profile.initialLevel)
    }

    var projectionEndDate: Date {
        Calendar.current.date(byAdding: .day, value: 89, to: Date()) ?? Date()
    }

    var daysToEscapeDeficiency: Int? {
        projection90.firstIndex { $0 >= 30 }.map { $0 + 1 }
    }
    var daysToSufficiency: Int? {
        projection90.firstIndex { $0 >= 50 }.map { $0 + 1 }
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
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(16).padding(.horizontal)
                        }

                        // Contribution breakdown
                        if !longitudinalData.isEmpty {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Vitamin D by Source")
                                        .font(.headline)
                                    Text("Cumulative over \(daysToShow)-day window")
                                        .font(.caption2).foregroundColor(.secondary)
                                    ContributionBar(
                                        uvContrib:   totalUV,
                                        oralContrib: totalOral,
                                        baseline:    store.profile.initialLevel,
                                        total:       totalCombined)
                                        .frame(width: 110, height: 100)
                                        .padding(.leading, 65)
                                }
                                .frame(maxWidth: .infinity).padding()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(16)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Contribution Breakdown")
                                        .font(.headline)
                                    let netGain = max(0.01, totalUV + totalOral)
                                    let uvPct   = totalUV   / netGain * 100
                                    let orPct   = totalOral / netGain * 100
                                    HStack(spacing: 10) {
                                        ContribCard(
                                            label: "UV synthesis",
                                            value: String(format: "%.1f%%", uvPct),
                                            sub:   String(format: "+%.2f nmol/L", totalUV),
                                            color: .orange).scaleEffect(0.88)
                                        ContribCard(
                                            label: "Oral intake",
                                            value: String(format: "%.1f%%", orPct),
                                            sub:   String(format: "+%.2f nmol/L", totalOral),
                                            color: .blue).scaleEffect(0.88)
                                    }
                                    Text(uvPct > 60
                                         ? "Matches paper — UV dominant"
                                         : "UV lower than expected")
                                        .font(.caption2)
                                        .foregroundColor(uvPct > 60 ? .green : .orange)
                                        .padding(8)
                                        .background(Color(.tertiarySystemBackground))
                                        .cornerRadius(8)
                                }
                                .frame(maxWidth: .infinity).padding()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(16)
                            }
                            .padding(.horizontal)
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
                                        Button {
                                            projectionWindow = days
                                        } label: {
                                            Text("\(days)d")
                                                .font(.caption).fontWeight(.semibold)
                                                .padding(.horizontal, 12).padding(.vertical, 6)
                                                .background(projectionWindow == days
                                                    ? Color.blue
                                                    : Color(.tertiarySystemBackground))
                                                .foregroundColor(projectionWindow == days
                                                    ? .white : .primary)
                                                .cornerRadius(8)
                                        }
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

                            if !projection90.isEmpty {
                                HStack(spacing: 10) {
                                    StatMiniCard(
                                        label: "Avg SED (\(actualWindowDays)d)",
                                        value: String(format: "%.4f", windowAvgSED),
                                        color: .orange)
                                    StatMiniCard(
                                        label: "Escapes deficiency",
                                        value: daysToEscapeDeficiency.map { "Day \($0)" } ?? "Not in 90d",
                                        color: daysToEscapeDeficiency != nil ? .green : .red)
                                    StatMiniCard(
                                        label: "Reaches sufficiency",
                                        value: daysToSufficiency.map { "Day \($0)" } ?? "Not in 90d",
                                        color: daysToSufficiency != nil ? .green : .red)
                                }.padding(.horizontal)

                                ProjectionChart(
                                    data: projection90,
                                    startDate: Date(),
                                    endDate: projectionEndDate)
                                    .frame(height: 240).padding(.horizontal)

                                Text("14d window recommended — matches 25-day plasma half-life.")
                                    .font(.caption2).foregroundColor(.secondary)
                                    .padding(.horizontal)
                            } else {
                                Text("Track at least one day to generate a projection.")
                                    .font(.caption).foregroundColor(.secondary).padding()
                            }
                        }
                        .padding(.vertical)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(16).padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Model Insights")
        }
    }
}

struct StatMiniCard: View {
    let label: String
    let value: String
    let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.subheadline).fontWeight(.bold).foregroundColor(color)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground)).cornerRadius(10)
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

// ── Contribution bar ──────────────────────────────────────────
struct ContributionBar: View {
    let uvContrib: Double; let oralContrib: Double
    let baseline: Double;  let total: Double
    var body: some View {
        GeometryReader { geo in
            let w       = geo.size.width * 0.4
            let h       = geo.size.height - 30
            let netGain = max(0.01, uvContrib + oralContrib)
            let scaleH  = h / netGain
            HStack(alignment: .bottom, spacing: 20) {
                VStack(spacing: 0) {
                    Text(String(format: "%.1f nmol/L", total))
                        .font(.system(size: 10, weight: .bold))
                    ZStack(alignment: .bottom) {
                        Rectangle().fill(Color.gray.opacity(0.2))
                            .frame(width: w, height: CGFloat(baseline) * scaleH * 0.3)
                        VStack(spacing: 0) {
                            Rectangle().fill(Color.orange)
                                .frame(width: w, height: max(2, CGFloat(uvContrib) * scaleH))
                            Rectangle().fill(Color.blue)
                                .frame(width: w, height: max(2, CGFloat(oralContrib) * scaleH))
                        }
                    }
                    Text("You").font(.system(size: 10)).foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Rectangle().fill(Color.orange).frame(width:14,height:14).cornerRadius(2)
                        Text("UV synthesis").font(.caption)
                    }
                    HStack(spacing: 6) {
                        Rectangle().fill(Color.blue).frame(width:14,height:14).cornerRadius(2)
                        Text("Oral intake").font(.caption)
                    }
                    HStack(spacing: 6) {
                        Rectangle().fill(Color.gray.opacity(0.4)).frame(width:14,height:14).cornerRadius(2)
                        Text("Baseline").font(.caption)
                    }
                    Spacer()
                    Text("Paper avg: UV = 73–98%").font(.caption2).foregroundColor(.secondary)
                }
                .padding(.bottom, 22)
                Spacer()
            }
        }
    }
}

struct ContribCard: View {
    let label: String; let value: String
    let sub: String;   let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.title3).fontWeight(.bold).foregroundColor(color)
            Text(sub).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(Color(.tertiarySystemBackground)).cornerRadius(12)
    }
}

// ── Projection chart — segment-colored by value ───────────────
struct ProjectionChart: View {
    let data: [Double]; let startDate: Date; let endDate: Date
    var minVal: Double { 20.0 }
    var maxVal: Double { max(60, data.max() ?? 60) }
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
                Rectangle().fill(Color.green.opacity(0.4)).frame(height: 1).offset(y: y50)
                Text("50 sufficient").font(.system(size: 8)).foregroundColor(.green)
                    .offset(x: 2, y: y50 - 10)
                Rectangle().fill(Color.red.opacity(0.4)).frame(height: 1).offset(y: y30)
                Text("30 deficient").font(.system(size: 8)).foregroundColor(.red)
                    .offset(x: 2, y: y30 - 10)

                if n >= 2 {
                    ForEach(0..<(n-1), id: \.self) { i in
                        let x1 = w * CGFloat(i)     / CGFloat(n-1)
                        let x2 = w * CGFloat(i+1)   / CGFloat(n-1)
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
                        Text("D\(i+1)").font(.system(size: 8)).foregroundColor(.secondary)
                            .position(x: x, y: h + 10)
                    }
                }
                Text(endDateLabel).font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary).position(x: w - 20, y: h + 22)
            }
        }
    }
}
