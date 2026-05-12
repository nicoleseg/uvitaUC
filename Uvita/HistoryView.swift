import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: DataStore
    @State var selectedRange = 0
    let ranges = ["7 days", "30 days", "All time"]

    var daysToShow: Int {
        switch selectedRange {
        case 0:  return 7
        case 1:  return 30
        default: return 365
        }
    }

    var history: [(Date, Double)] {
        store.plasmaHistory(days: daysToShow)
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

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {


                    if !history.isEmpty {
                        HStack(spacing: 10) {
                            SummaryCard(
                                label: "Average",
                                value: String(format: "%.0f",
                                    history.map { $0.1 }
                                    .reduce(0,+) /
                                    Double(history.count)),
                                unit:  "nmol/L",
                                color: .blue)
                            SummaryCard(
                                label: "Days tracked",
                                value: "\(history.count)",
                                unit:  "days",
                                color: .purple)
                        }
                        .padding(.horizontal)
                    }
                    if !longitudinalData.isEmpty {

                        VStack(alignment: .leading,
                               spacing: 0) {

                            Text("All readings")
                                .font(.headline)
                                .padding()
                            HStack {
                                Text("Date")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 40,
                                           alignment: .leading)

                                Spacer()
                                Text("UV contrib")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                Spacer()
                                Text("Oral contrib")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                Spacer()
                                Text("C_total")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 70,
                                           alignment: .trailing)
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                            ForEach(
                                longitudinalData.indices,
                                id: \.self
                            ) { i in

                                let day = longitudinalData[i]

                                let cal = Calendar.current

                                let matchingReadings =
                                    store.readings
                                        .filter {
                                            cal.isDate(
                                                $0.date,
                                                inSameDayAs:
                                                    dateFromLabel(day.label)
                                            )
                                        }
                                        .sorted {
                                            $0.date > $1.date
                                        }

                                DisclosureGroup {

                                    VStack(spacing: 0) {

                                        ForEach(matchingReadings) { r in

                                            HStack {

                                                VStack(
                                                    alignment: .leading,
                                                    spacing: 3
                                                ) {

                                                    Text(
                                                        r.date.formatted(
                                                            .dateTime
                                                                .month()
                                                                .day()
                                                                .hour()
                                                                .minute()
                                                        )
                                                    )
                                                    .font(.caption)
                                                    .foregroundColor(
                                                        .secondary
                                                    )

                                                    Text(
                                                        String(
                                                            format:
                                                            "UVI %.1f · BSA %.0f%% · SED %.4f",
                                                            r.uvi,
                                                            r.bsaPercent,
                                                            r.sed
                                                        )
                                                    )
                                                    .font(.caption2)
                                                    .foregroundColor(
                                                        .secondary
                                                    )
                                                }

                                                Spacer()

                                                Text(
                                                    String(
                                                        format:
                                                        "%.0f nmol/L",
                                                        r.plasmaLevel
                                                    )
                                                )
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(
                                                    levelColor(
                                                        r.plasmaLevel
                                                    )
                                                )
                                            }
                                            .padding(.horizontal)
                                            .padding(.vertical, 8)

                                            Divider()
                                                .padding(.horizontal)
                                        }
                                    }

                                } label: {

                                    HStack {

                                        Text(day.label)
                                            .font(.caption2)
                                            .foregroundColor(
                                                .secondary
                                            )
                                            .frame(
                                                width: 40,
                                                alignment: .leading
                                            )

                                        Spacer()

                                        Text(
                                            String(
                                                format:
                                                "+%.2f",
                                                day.uvContrib
                                            )
                                        )
                                        .font(.caption2)
                                        .foregroundColor(.orange)

                                        Spacer()

                                        Text(
                                            String(
                                                format:
                                                "+%.2f",
                                                day.oralContrib
                                            )
                                        )
                                        .font(.caption2)
                                        .foregroundColor(.blue)

                                        Spacer()

                                        Text(
                                            String(
                                                format:
                                                "%.0f",
                                                day.total
                                            )
                                        )
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .frame(
                                            width: 70,
                                            alignment: .trailing
                                        )
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 10)
                                }

                                Divider()
                                    .padding(.horizontal)
                            }
                        }
                        .background(
                            Color(.secondarySystemBackground)
                        )
                        .cornerRadius(16)
                        .padding(.horizontal)
                    }
                    
                }
                .padding(.vertical)
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement:
                    .navigationBarTrailing) {
                    Button("Clear today") {
                        store.clearToday()
                    }
                    .foregroundColor(.red)
                }
            }
        }
    }
    
    func dateFromLabel(_ label: String) -> Date {

        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"

        let parsed =
            fmt.date(from: label) ?? Date()

        let currentYear =
            Calendar.current.component(
                .year,
                from: Date()
            )

        var comps =
            Calendar.current.dateComponents(
                [.month, .day],
                from: parsed
            )

        comps.year = currentYear

        return Calendar.current.date(
            from: comps
        ) ?? Date()
    }
    
    func levelColor(_ v: Double) -> Color {
        v < 30 ? .red : v < 50 ? .orange : .green
    }
}

// ── Summary card ──────────────────────────────────────────────
struct SummaryCard: View {
    let label: String
    let value: String
    let unit:  String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(unit)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }
}

// ── Bar chart ─────────────────────────────────────────────────
struct PlasmaChart: View {
    let data: [(Date, Double)]

    var maxVal: Double {
        max(80, data.map { $0.1 }.max() ?? 80)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("50 nmol/L — sufficient")
                    .font(.system(size: 9))
                    .foregroundColor(.green)
                Spacer()
                Text("30 nmol/L — deficient")
                    .font(.system(size: 9))
                    .foregroundColor(.red)
            }
            GeometryReader { geo in
                ZStack(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(Color.green.opacity(0.3))
                        .frame(height: 1)
                        .offset(y: -(geo.size.height *
                            CGFloat(50 / maxVal)))
                    Rectangle()
                        .fill(Color.red.opacity(0.3))
                        .frame(height: 1)
                        .offset(y: -(geo.size.height *
                            CGFloat(30 / maxVal)))
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(data.indices,
                                id: \.self) { i in
                            let (date, level) = data[i]
                            VStack(spacing: 2) {
                                Text(String(format: "%.0f",
                                            level))
                                    .font(.system(size: 8))
                                    .foregroundColor(
                                        .secondary)
                                RoundedRectangle(
                                    cornerRadius: 3)
                                    .fill(barColor(level))
                                    .frame(height: max(4,
                                        geo.size.height *
                                        CGFloat(level / maxVal)
                                        - 16))
                                Text(date.formatted(
                                    .dateTime
                                    .month(.abbreviated)
                                    .day()))
                                    .font(.system(size: 8))
                                    .foregroundColor(
                                        .secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    func barColor(_ v: Double) -> Color {
        v < 30 ? .red : v < 50 ? .orange : .green
    }
}
