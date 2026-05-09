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

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {

                    Picker("Range",
                           selection: $selectedRange) {
                        ForEach(0..<ranges.count,
                                id: \.self) {
                            Text(ranges[$0]).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if !history.isEmpty {
                        HStack(spacing: 10) {
                            SummaryCard(
                                label: "Latest",
                                value: String(format: "%.0f",
                                    history.last?.1 ?? 0),
                                unit:  "nmol/L",
                                color: levelColor(
                                    history.last?.1 ?? 0))
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

                    if !history.isEmpty {
                        VStack(alignment: .leading,
                               spacing: 8) {
                            Text("Plasma 25(OH)D over time")
                                .font(.headline)
                                .padding(.horizontal)
                            PlasmaChart(data: history)
                                .frame(height: 200)
                                .padding(.horizontal)
                        }
                        .padding(.vertical)
                        .background(Color(
                            .secondarySystemBackground))
                        .cornerRadius(16)
                        .padding(.horizontal)
                    } else {
                        Text("No data yet — keep tracking to see your trend.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Today")
                            .font(.headline)
                            .padding(.horizontal)
                        HStack(spacing: 10) {
                            SummaryCard(
                                label: "Readings",
                                value: "\(store.todayReadings.count)",
                                unit:  "logged",
                                color: .teal)
                            SummaryCard(
                                label: "Total SED",
                                value: String(format: "%.3f",
                                    store.todaySED()),
                                unit:  "UV dose",
                                color: .orange)
                            SummaryCard(
                                label: "Avg 25(OH)D",
                                value: String(format: "%.0f",
                                    store.todayAvgPlasma()),
                                unit:  "nmol/L",
                                color: levelColor(
                                    store.todayAvgPlasma()))
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                    .background(Color(
                        .secondarySystemBackground))
                    .cornerRadius(16)
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("All readings")
                            .font(.headline).padding()
                        if store.readings.isEmpty {
                            Text("No readings yet — start tracking on the Today tab.")
                                .foregroundColor(.secondary)
                                .font(.caption).padding()
                        } else {
                            ForEach(
                                store.readings.sorted {
                                    $0.date > $1.date
                                }) { r in
                                HStack {
                                    VStack(
                                        alignment: .leading,
                                        spacing: 3) {
                                        Text(r.date.formatted(
                                            .dateTime
                                            .month().day()
                                            .hour().minute()))
                                            .font(.caption)
                                            .foregroundColor(
                                                .secondary)
                                        Text(String(format:
                                            "UVI %.1f · BSA %.0f%% · SED %.4f",
                                            r.uvi,
                                            r.bsaPercent,
                                            r.sed))
                                            .font(.caption2)
                                            .foregroundColor(
                                                .secondary)
                                    }
                                    Spacer()
                                    Text(String(format:
                                        "%.0f nmol/L",
                                        r.plasmaLevel))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(
                                            levelColor(
                                                r.plasmaLevel))
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                Divider()
                                    .padding(.horizontal)
                            }
                        }
                    }
                    .background(Color(
                        .secondarySystemBackground))
                    .cornerRadius(16)
                    .padding(.horizontal)
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
