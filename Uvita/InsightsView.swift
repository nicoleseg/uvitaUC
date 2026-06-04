import SwiftUI

// ── InsightsView ──────────────────────────────────────────────
struct InsightsView: View {
    @EnvironmentObject var store: DataStore
    @State var selectedRange     = 0
    @State var projectionWindow: Int = 14
    let ranges = ["7 days", "14 days", "30 days"]

    var daysToShow: Int {
        switch selectedRange {
        case 0: return 7; case 1: return 14; default: return 30
        }
    }

    var longitudinalData: [DataStore.DayModelResult] {
        store.longitudinalModel(daysBack: daysToShow)
    }
    var totalUV:       Double { longitudinalData.map { $0.uvContrib  }.reduce(0,+) }
    var totalOral:     Double { longitudinalData.map { $0.oralContrib }.reduce(0,+) }
    var totalCombined: Double { longitudinalData.last?.total ?? store.profile.initialLevel }

    // ── Window averages ───────────────────────────────────────
    struct ProjDay { let uvDose, oralDose, bsa: Double }

    var projWindowDays: [ProjDay] {
        let cal = Calendar.current
        var dayMap: [Date: (uv: Double, bsa: Double)] = [:]
        for r in store.readings where r.label == nil {
            let day = cal.startOfDay(for: r.date)
            dayMap[day] = (uv: (dayMap[day]?.uv ?? 0) + r.sed,
                           bsa: r.bsaPercent)
        }
        // Resolve oral from food log (same logic as buildDayAggregates)
        // so projection uses actual logged food, not stale snapshots
        return Array(dayMap.keys.sorted().suffix(projectionWindow)).map { day in
            let uvBsa = dayMap[day]!
            let oral: Double
            switch store.profile.oralSource {
            case .manualLog:
                oral = store.foodLog
                    .filter { cal.isDate($0.date, inSameDayAs: day) }
                    .reduce(0) { $0 + $1.vitaminDug }
            default:
                oral = store.profile.supplementOralUg
            }
            return ProjDay(uvDose: uvBsa.uv, oralDose: oral, bsa: uvBsa.bsa)
        }
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

    // ── Observed series ───────────────────────────────────────
    var observedCorrected: [Double] { longitudinalData.map { $0.total } }
    var observedRaw:       [Double] {
        store.rawLongitudinalModel(daysBack: daysToShow).map { $0.total }
    }

    // ── Projected series ──────────────────────────────────────
    var projectedCorrected: [Double] {
        guard !projWindowDays.isEmpty else { return [] }
        let C0 = observedCorrected.last ?? store.profile.initialLevel
        let n  = max(1, 90 - observedCorrected.count)
        return VitaminDEngine.runModel(
            oralDoses: Array(repeating: windowAvgOral, count: n),
            uvDoses:   Array(repeating: windowAvgSED,  count: n),
            bodyAreas: Array(repeating: windowAvgBSA,  count: n),
            age: store.profile.age, skinType: store.profile.skinType, C0: C0)
    }
    var projectedRaw: [Double] {
        guard !projWindowDays.isEmpty else { return [] }
        let rawActuals = store.rawLongitudinalModel(daysBack: daysToShow)
        let C0 = rawActuals.last?.total ?? store.profile.initialLevel
        let n  = max(1, 90 - rawActuals.count)
        return store.rawAutoProjection(windowDays: projectionWindow,
                                       C0override: C0, nDays: n)
    }
    var projectionsHaveDiff: Bool {
        let maxDiff = zip(projectedCorrected, projectedRaw)
            .map { abs($0 - $1) }.max() ?? 0
        return maxDiff > 0.1
    }

    // ── Milestones ────────────────────────────────────────────
    var daysToEscapeDeficiency: Int? {
        projectedCorrected.firstIndex { $0 >= 30 }.map { $0 + 1 }
    }
    var daysToSufficiency: Int? {
        projectedCorrected.firstIndex { $0 >= 50 }.map { $0 + 1 }
    }
    var projectionEndDate: Date {
        Calendar.current.date(byAdding: .day, value: 89, to: Date()) ?? Date()
    }

    // ── Projection section ────────────────────────────────────
    @ViewBuilder
    private var projectionSection: some View {
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

            ProjectionC0Row(level: store.profile.initialLevel)

            if projectedCorrected.isEmpty {
                Text("Track at least one day to generate a projection.")
                    .font(.caption).foregroundColor(.secondary).padding()
            } else {
                ProjectionStatsRow(
                    avgSED:         windowAvgSED,
                    windowDays:     actualWindowDays,
                    escapeDay:      daysToEscapeDeficiency,
                    sufficiencyDay: daysToSufficiency)

                ProjectionChart(
                    observed:     observedCorrected,
                    observedRaw:  observedRaw,
                    projected:    projectedCorrected,
                    projectedRaw: projectionsHaveDiff ? projectedRaw : nil,
                    startDate:    longitudinalData.first?.date ?? Date(),
                    endDate:      projectionEndDate)
                    .frame(height: 260).padding(.horizontal)

                ProjectionLegend(hasDiff: projectionsHaveDiff)

                Text("14d window recommended — matches 25-day plasma half-life.")
                    .font(.caption2).foregroundColor(.secondary).padding(.horizontal)
            }
        }
        .padding(.vertical)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16).padding(.horizontal)
    }

    // ── Body ──────────────────────────────────────────────────
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {
                    if store.readings.isEmpty {
                        Text("No data yet — start tracking on the Today tab.")
                            .font(.caption).foregroundColor(.secondary)
                            .multilineTextAlignment(.center).padding(32)
                    } else {
                        // Range picker
                        VStack(spacing: 4) {
                            Picker("Range", selection: $selectedRange) {
                                ForEach(0..<ranges.count, id: \.self) {
                                    Text(ranges[$0]).tag($0)
                                }
                            }
                            .pickerStyle(.segmented).padding(.horizontal)
                            if let first = longitudinalData.first,
                               let last  = longitudinalData.last {
                                let fmt = DateFormatter()
                                let _ = { fmt.dateFormat = "MMM d" }()
                                Text("\(fmt.string(from: first.date)) – \(fmt.string(from: last.date))")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }

                        // Day-by-day chart
                        if !longitudinalData.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Plasma 25(OH)D — Day by Day")
                                    .font(.headline).padding(.horizontal)
                                Text("One point per calendar day · Eq. 8 (Diffey 2013)")
                                    .font(.caption2).foregroundColor(.secondary).padding(.horizontal)
                                LongitudinalLineChart(
                                    data: longitudinalData,
                                    baseline: store.profile.initialLevel)
                                    .frame(height: 220).padding(.horizontal)
                            }
                            .padding(.vertical)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(16).padding(.horizontal)
                        }

                        // Contribution card
                        if !longitudinalData.isEmpty {
                            CombinedContributionCard(
                                uvContrib:   totalUV,
                                oralContrib: totalOral,
                                baseline:    store.profile.initialLevel,
                                total:       totalCombined,
                                daysToShow:  daysToShow)
                        }

                        BodyPartSEDCard()
                        projectionSection
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Model Insights")
        }
    }
}

// ── Projection helper views ───────────────────────────────────

struct ProjectionWindowButton: View {
    let days: Int; let selected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            let bg: Color = selected ? .blue : Color.gray.opacity(0.06)
            let fg: Color = selected ? .white : .primary
            Text("\(days)d")
                .font(.caption).fontWeight(.semibold)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(bg).foregroundColor(fg).cornerRadius(8)
        }
    }
}

struct ProjectionC0Row: View {
    let level: Double
    var body: some View {
        let color: Color = level < 30 ? .red : level < 50 ? .orange : .green
        HStack {
            Text("Starting plasma (C₀)").font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(String(format: "%.0f nmol/L", level))
                .font(.caption).fontWeight(.semibold).foregroundColor(color)
            Text("· set in Profile").font(.caption2).foregroundColor(.secondary)
        }.padding(.horizontal)
    }
}

struct ProjectionStatsRow: View {
    let avgSED: Double; let windowDays: Int
    let escapeDay: Int?; let sufficiencyDay: Int?
    var body: some View {
        let eVal:  String = escapeDay.map      { "Day \($0)" } ?? "Not in 90d"
        let eCol:  Color  = escapeDay      != nil ? .green : .red
        let sVal:  String = sufficiencyDay.map { "Day \($0)" } ?? "Not in 90d"
        let sCol:  Color  = sufficiencyDay != nil ? .green : .red
        HStack(spacing: 10) {
            StatMiniCard(label: "Avg SED (\(windowDays)d)",
                         value: String(format: "%.4f", avgSED), color: .orange)
            StatMiniCard(label: "Escapes deficiency", sublabel: "(≥30 nmol/L)",
                         value: eVal, color: eCol)
            StatMiniCard(label: "Reaches sufficiency", sublabel: "(≥50 nmol/L)",
                         value: sVal, color: sCol)
        }.padding(.horizontal)
    }
}

struct ProjectionLegend: View {
    let hasDiff: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    Rectangle().fill(Color.teal).frame(width: 16, height: 2.5)
                    Text("Observed (corrected)").font(.caption2).foregroundColor(.secondary)
                }
                HStack(spacing: 5) {
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle().fill(Color.teal).frame(width: 4, height: 2.5)
                        }
                    }
                    Text("Projected (corrected)").font(.caption2).foregroundColor(.secondary)
                }
            }
            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    Rectangle().fill(Color.gray.opacity(0.5)).frame(width: 16, height: 2)
                    Text("Observed (auto only)").font(.caption2).foregroundColor(.secondary)
                }
                HStack(spacing: 5) {
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle().fill(Color.gray.opacity(0.5)).frame(width: 4, height: 2)
                        }
                    }
                    Text("Projected (auto only)").font(.caption2).foregroundColor(.secondary)
                }
                if !hasDiff {
                    Text("· lines identical").font(.caption2).foregroundColor(.secondary)
                }
            }
        }.padding(.horizontal)
    }
}

struct StatMiniCard: View {
    let label: String; var sublabel: String? = nil
    let value: String; let color: Color
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
    let data: [DataStore.DayModelResult]; let baseline: Double
    var minVal: Double { min(baseline-5, data.map{$0.total}.min() ?? baseline) }
    var maxVal: Double { max(baseline+20, data.map{$0.total}.max() ?? baseline+20) }
    var range:  Double { max(1, maxVal - minVal) }
    var endDateLabel: String {
        guard let last = data.last else { return "" }
        let fmt = DateFormatter(); fmt.dateFormat = "MMM d"; return fmt.string(from: last.date)
    }
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width; let h = geo.size.height - 24; let n = data.count
            ZStack(alignment: .bottomLeading) {
                let y50 = h - h * CGFloat((50 - minVal) / range)
                let y30 = h - h * CGFloat((30 - minVal) / range)
                Rectangle().fill(Color.green.opacity(0.25)).frame(height:1).offset(y:y50)
                Text("50").font(.system(size:8)).foregroundColor(.green).offset(x:2,y:y50-10)
                Rectangle().fill(Color.red.opacity(0.25)).frame(height:1).offset(y:y30)
                Text("30").font(.system(size:8)).foregroundColor(.red).offset(x:2,y:y30-10)
                if n >= 2 {
                    Path { path in
                        for i in 0..<n {
                            let x = w * CGFloat(i) / CGFloat(n-1)
                            let y = h - h * CGFloat((data[i].total - minVal) / range)
                            i == 0 ? path.move(to:.init(x:x,y:y)) : path.addLine(to:.init(x:x,y:y))
                        }
                    }.stroke(Color.teal, lineWidth: 2.5)
                }
                ForEach(0..<n, id: \.self) { i in
                    let x = w * CGFloat(i) / CGFloat(max(1,n-1))
                    let y = h - h * CGFloat((data[i].total - minVal) / range)
                    let dotColor: Color = data[i].total < 30 ? .red : data[i].total < 50 ? .orange : .teal
                    Circle().fill(dotColor).frame(width:8,height:8).position(x:x,y:y)
                    if i == 0 || i == n-1 || i % 2 == 0 {
                        Text(data[i].label).font(.system(size:8))
                            .foregroundColor(.secondary).position(x:x,y:h+12)
                    }
                }
                if !endDateLabel.isEmpty {
                    Text(endDateLabel).font(.system(size:9,weight:.semibold))
                        .foregroundColor(.teal).position(x:max(40,w-6),y:h+22)
                }
            }
        }
    }
}

// ── Projection chart ─────────────────────────────────────────
struct ProjectionChart: View {
    let observed:     [Double]
    var observedRaw:  [Double] = []
    let projected:    [Double]
    var projectedRaw: [Double]? = nil
    let startDate:    Date
    let endDate:      Date

    var allData: [Double] { observed + projected }
    var allRaw:  [Double] { observedRaw + (projectedRaw ?? projected) }
    var minVal:  Double   { 20.0 }
    var maxVal:  Double   { max(60, (allData + allRaw).max() ?? 60) }
    var range:   Double   { maxVal - minVal }
    var total:   Int      { observed.count + projected.count }

    func yPos(_ v: Double, h: CGFloat) -> CGFloat { h - h * CGFloat((v-minVal)/range) }
    func xPos(_ i: Int, w: CGFloat) -> CGFloat {
        total > 1 ? w * CGFloat(i) / CGFloat(total-1) : 0
    }
    func lineColor(_ v: Double) -> Color { v < 30 ? .red : v < 50 ? .orange : .teal }
    var endDateLabel: String {
        let fmt = DateFormatter(); fmt.dateFormat = "MMM d"; return fmt.string(from: endDate)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width; let h = geo.size.height - 32
            ZStack(alignment: .bottomLeading) {
                let y30 = yPos(30,h:h); let y50 = yPos(50,h:h)
                Rectangle().fill(Color.red.opacity(0.06)).frame(width:w,height:h-y30).offset(y:y30)
                Rectangle().fill(Color.green.opacity(0.06)).frame(width:w,height:y50)
                Rectangle().fill(Color.green.opacity(0.35)).frame(height:1).offset(y:y50)
                Text("50").font(.system(size:7)).foregroundColor(.green).offset(x:2,y:y50-8)
                Rectangle().fill(Color.red.opacity(0.35)).frame(height:1).offset(y:y30)
                Text("30").font(.system(size:7)).foregroundColor(.red).offset(x:2,y:y30-8)

                // Y-axis labels — evenly spaced from minVal to maxVal
                let yStep: Double = (maxVal - minVal) <= 20 ? 5 : 10
                ForEach(Array(stride(from: minVal, through: maxVal, by: yStep)), id: \.self) { val in
                    let yy = yPos(val, h: h)
                    if yy >= 0 && yy <= h {
                        Text(String(format: "%.0f", val))
                            .font(.system(size: 7))
                            .foregroundColor(.secondary)
                            .position(x: w - 16, y: yy)
                    }
                }

                if observed.count > 0 && projected.count > 0 {
                    let divX = xPos(observed.count-1, w:w)
                    Rectangle().fill(Color.gray.opacity(0.3)).frame(width:1,height:h).offset(x:divX)
                    Text("today").font(.system(size:7)).foregroundColor(.secondary)
                        .offset(x:divX-10, y:h+18)
                }

                let rawFull = observedRaw.isEmpty ? observed : observedRaw+(projectedRaw ?? projected)
                if rawFull.count >= 2 {
                    Path { p in
                        for i in 0..<rawFull.count {
                            let x = xPos(i,w:w); let y = yPos(rawFull[i],h:h)
                            i==0 ? p.move(to:.init(x:x,y:y)) : p.addLine(to:.init(x:x,y:y))
                        }
                    }.stroke(Color.gray.opacity(0.45), style:StrokeStyle(lineWidth:1.5,dash:[3,3]))
                }

                let corrFull = observed + projected
                ForEach(0..<max(0,corrFull.count-1), id:\.self) { i in
                    let isProjSegment = i >= observed.count - 1
                    let x1=xPos(i,w:w); let x2=xPos(i+1,w:w)
                    let y1=yPos(corrFull[i],h:h); let y2=yPos(corrFull[i+1],h:h)
                    Path { p in p.move(to:.init(x:x1,y:y1)); p.addLine(to:.init(x:x2,y:y2)) }
                        .stroke(lineColor(corrFull[i]),
                                style:StrokeStyle(lineWidth:isProjSegment ? 1.8:2.5,
                                                  dash:isProjSegment ? [5,3]:[]))
                }

                let step = total > 30 ? 14 : 7
                ForEach(Array(stride(from:0,to:total,by:step)), id:\.self) { i in
                    Text("D\(i+1)").font(.system(size:7)).foregroundColor(.secondary)
                        .position(x:xPos(i,w:w), y:h+10)
                }
                Text(endDateLabel).font(.system(size:8,weight:.semibold))
                    .foregroundColor(.secondary).position(x:w-22, y:h+22)
            }
        }
    }
}

// ── Combined contribution card ────────────────────────────────
struct CombinedContributionCard: View {
    let uvContrib, oralContrib, baseline, total: Double; let daysToShow: Int
    var netGain: Double { max(0.01, uvContrib + oralContrib) }
    var uvPct:   Double { uvContrib   / netGain * 100 }
    var orPct:   Double { oralContrib / netGain * 100 }

    var body: some View {
        let uvColor:  Color  = uvPct > 60 ? .green : .orange
        let uvIcon:   String = uvPct > 60 ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        let uvText:   String = uvPct > 60
            ? "UV dominant — matches literature (73–98%)"
            : "Oral dominant — possibly limited UV exposure recently"
        let totalColor: Color = total < 30 ? .red : total < 50 ? .orange : .green

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Vitamin D Contribution").font(.headline)
                Text("Cumulative over \(daysToShow)-day window · UV vs oral split")
                    .font(.caption2).foregroundColor(.secondary)
            }
            GeometryReader { geo in
                let w = geo.size.width
                let uvW = CGFloat(uvPct/100)*w; let orW = CGFloat(orPct/100)*w
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius:8).fill(Color.orange)
                        .frame(width:max(uvW,2),height:36)
                    RoundedRectangle(cornerRadius:8).fill(Color.blue)
                        .frame(width:max(orW,2),height:36).offset(x:uvW)
                    if uvW > 44 {
                        Text(String(format:"%.0f%%",uvPct))
                            .font(.system(size:12,weight:.bold)).foregroundColor(.white)
                            .offset(x:uvW/2-14)
                    }
                    if orW > 44 {
                        Text(String(format:"%.0f%%",orPct))
                            .font(.system(size:12,weight:.bold)).foregroundColor(.white)
                            .offset(x:uvW+orW/2-14)
                    }
                }
            }.frame(height:36)

            HStack(spacing:0) {
                HStack(spacing:6) {
                    Circle().fill(Color.orange).frame(width:8,height:8)
                    VStack(alignment:.leading,spacing:1) {
                        Text("UV synthesis").font(.caption2).foregroundColor(.secondary)
                        Text(String(format:"+%.3f nmol/L",uvContrib))
                            .font(.caption).fontWeight(.semibold).foregroundColor(.orange)
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
                HStack(spacing:6) {
                    Circle().fill(Color.blue).frame(width:8,height:8)
                    VStack(alignment:.leading,spacing:1) {
                        Text("Oral intake").font(.caption2).foregroundColor(.secondary)
                        Text(String(format:"+%.3f nmol/L",oralContrib))
                            .font(.caption).fontWeight(.semibold).foregroundColor(.blue)
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
                VStack(alignment:.trailing,spacing:1) {
                    Text("Total level").font(.caption2).foregroundColor(.secondary)
                    Text(String(format:"%.1f nmol/L",total))
                        .font(.caption).fontWeight(.semibold).foregroundColor(totalColor)
                }
            }
            HStack(spacing:4) {
                Image(systemName:uvIcon).font(.caption).foregroundColor(uvColor)
                Text(uvText).font(.caption2).foregroundColor(uvColor)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16).padding(.horizontal)
    }
}
