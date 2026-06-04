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

    var longitudinalData: [DataStore.DayModelResult] {
        store.longitudinalModel(daysBack: daysToShow)
    }

    var averagePlasma: Double {
        guard !longitudinalData.isEmpty else { return 0 }
        return longitudinalData.map { $0.total }.reduce(0,+)
            / Double(longitudinalData.count)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {

                    Picker("Range", selection: $selectedRange) {
                        ForEach(0..<ranges.count, id: \.self) {
                            Text(ranges[$0]).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if !longitudinalData.isEmpty {
                        HStack(spacing: 10) {
                            SummaryCard(
                                label: "Latest",
                                value: String(format: "%.1f",
                                    longitudinalData.last?.total ?? 0),
                                unit:  "nmol/L",
                                color: levelColor(
                                    longitudinalData.last?.total ?? 0))
                            SummaryCard(
                                label: "Average",
                                value: String(format: "%.1f", averagePlasma),
                                unit:  "nmol/L",
                                color: .blue)
                            SummaryCard(
                                label: "Days tracked",
                                value: "\(longitudinalData.count)",
                                unit:  "days",
                                color: .purple)
                        }
                        .padding(.horizontal)

                        let totalSED = store
                            .studyWindowAggregates(days: daysToShow)
                            .map { $0.uvDose }
                            .reduce(0,+)
                        SummaryCard(
                            label: "Total UV dose",
                            value: String(format: "%.4f", totalSED),
                            unit:  "SED cumulative",
                            color: .orange)
                            .padding(.horizontal)
                    }

                    if !longitudinalData.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text("All readings")
                                    .font(.headline)
                                Spacer()
                                Text("UV contrib")
                                    .font(.caption2).foregroundColor(.orange)
                                    .frame(width: 64, alignment: .trailing)
                                Text("Oral")
                                    .font(.caption2).foregroundColor(.blue)
                                    .frame(width: 44, alignment: .trailing)
                                Text("C_total")
                                    .font(.caption2).foregroundColor(.secondary)
                                    .frame(width: 54, alignment: .trailing)
                            }
                            .padding(.horizontal).padding(.vertical, 10)

                            ForEach(longitudinalData, id: \.date) { day in
                                DayHistoryRow(
                                    day: day,
                                    longitudinalData: longitudinalData
                                )
                                Divider().padding(.horizontal)
                            }
                        }
                        .background(Color.secondaryBackground)
                        .cornerRadius(16).padding(.horizontal)
                    } else {
                        Text("No readings yet")
                            .font(.caption).foregroundColor(.secondary)
                            .padding(32)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear today") { store.clearToday() }
                        .foregroundColor(.red)
                }
            }
        }
    }

    func levelColor(_ v: Double) -> Color {
        v < 30 ? .red : v < 50 ? .orange : .green
    }
}

struct DayHistoryRow: View {
    @EnvironmentObject var store: DataStore
    let day: DataStore.DayModelResult
    let longitudinalData: [DataStore.DayModelResult]
    var readingsForDay: [DayReading] {
        let cal = Calendar.current
        return store.readings
            .filter { cal.isDate($0.date, inSameDayAs: day.date) }
            .sorted { $0.date > $1.date }
    }

    var foodForDay: [FoodLogEntry] {
        let cal = Calendar.current
        return store.foodLog
            .filter { cal.isDate($0.date, inSameDayAs: day.date) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        DisclosureGroup {
            VStack(spacing: 0) {

                if !foodForDay.isEmpty {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Diet vitamin D")
                                .font(.caption).fontWeight(.semibold)
                                .foregroundColor(.blue)
                            Spacer()
                            Text(String(format: "%.1f µg total",
                                foodForDay.reduce(0) { $0 + $1.vitaminDug }))
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        .padding(.horizontal).padding(.vertical, 6)

                        ForEach(foodForDay) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.name)
                                        .font(.caption).fontWeight(.medium)
                                    Text(entry.brand.isEmpty
                                         ? entry.servingDesc
                                         : "\(entry.brand) · \(entry.servingDesc)")
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(String(format: "+%.1f µg", entry.vitaminDug))
                                    .font(.caption).foregroundColor(.blue)
                            }
                            .padding(.horizontal).padding(.vertical, 5)
                            Divider().padding(.horizontal)
                        }
                    }
                    .background(Color.blue.opacity(0.04))
                }

                ForEach(readingsForDay) { r in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(r.date.formatted(
                                    .dateTime.hour().minute()))
                                    .font(.caption2).foregroundColor(.secondary)
                                if r.label != nil {
                                    Text("● manual")
                                        .font(.system(size: 9))
                                        .foregroundColor(.purple)
                                }
                                if r.isUncertain {
                                    Text("uncertain")
                                        .font(.system(size: 9))
                                        .foregroundColor(.orange)
                                }
                            }
                            Text(String(format:
                                "UVI %.1f · BSA %.0f%% · SED %.5f · %@",
                                r.uvi, r.bsaPercent, r.sed,
                                r.indoors ? "indoors" : "outdoors"))
                                .font(.caption2).foregroundColor(.secondary)
                            if let label = r.label {
                                Text("Label: \(label)")
                                    .font(.caption2).foregroundColor(.purple)
                            }
                        }
                        Spacer()
                        Text(String(format: "%.1f nmol/L", displayedPlasma))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(levelColor(displayedPlasma))
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                    Divider().padding(.horizontal)
                }
            }
        } label: {
            HStack {
                Text(day.label)
                    .font(.caption2).foregroundColor(.secondary)
                    .frame(width: 40, alignment: .leading)
                Spacer()
                Text(String(format: "+%.3f", day.uvContrib))
                    .font(.caption2).foregroundColor(.orange)
                    .frame(width: 64, alignment: .trailing)
                Text(String(format: "+%.3f", day.oralContrib))
                    .font(.caption2).foregroundColor(.blue)
                    .frame(width: 44, alignment: .trailing)
                Text(String(format: "%.1f", day.total))
                    .font(.caption2).foregroundColor(levelColor(day.total))
                    .frame(width: 54, alignment: .trailing)
            }
            .padding(.horizontal).padding(.vertical, 10)
        }
    }

    func levelColor(_ v: Double) -> Color {
        v < 30 ? .red : v < 50 ? .orange : .green
    }
    var displayedPlasma: Double {
        let history = longitudinalData

        guard let idx =
            history.firstIndex(where: {
                Calendar.current.isDate(
                    $0.date,
                    inSameDayAs: day.date
                )
            })
        else {
            return store.profile.initialLevel
        }

        return idx == 0
            ? store.profile.initialLevel
            : history[idx - 1].total
    }
}

struct SummaryCard: View {
    let label: String
    let value: String
    let unit:  String
    let color: Color
    var body: some View {
        VStack(spacing: 3) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.title2).fontWeight(.bold).foregroundColor(color)
            Text(unit).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(Color.tertiaryBackground).cornerRadius(12)
    }
}
