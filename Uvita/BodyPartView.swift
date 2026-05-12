import SwiftUI

struct BodyPartSEDCard: View {
    @EnvironmentObject var store: DataStore

    var totals: [String: Double] {
        store.cumulativeBodyPartSED()
    }

    var maxVal: Double {
        totals.values.max() ?? 1
    }

    var mostExposed: (String, Double) {
        store.mostExposedBodyPart
    }

    var sorted: [(String, Double)] {
        totals.sorted { $0.value > $1.value }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            VStack(alignment: .leading, spacing: 2) {
                Text("UV Exposure by Body Part")
                    .font(.headline)

                Text("Cumulative SED per region")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if mostExposed.1 > 0 {
                HStack(spacing: 8) {

                    Image(systemName: "sun.max.fill")
                        .foregroundColor(.orange)

                    (
                        Text("Most exposed: ")
                            .foregroundColor(.secondary)

                        +

                        Text(mostExposed.0)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)

                        +

                        Text(
                            String(format: " (%.4f SED)",
                                   mostExposed.1)
                        )
                            .foregroundColor(.secondary)
                    )
                    .font(.caption)
                }
                .padding(8)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(8)
            }

            ForEach(sorted, id: \.0) { name, value in

                HStack(spacing: 8) {

                    Text(name)
                        .font(.caption)
                        .frame(width: 80, alignment: .leading)

                    GeometryReader { geo in

                        ZStack(alignment: .leading) {

                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(.systemGray5))
                                .frame(height: 14)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(barColor(value))
                                .frame(
                                    width: max(
                                        4,
                                        geo.size.width *
                                        CGFloat(
                                            maxVal > 0
                                            ? value / maxVal
                                            : 0
                                        )
                                    ),
                                    height: 14
                                )
                        }
                    }
                    .frame(height: 14)

                    Text(String(format: "%.4f", value))
                        .font(.system(size: 10,
                                      design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 60,
                               alignment: .trailing)
                }
            }

            Text("Only outdoor readings counted.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .padding(.horizontal)
    }

    func barColor(_ value: Double) -> Color {

        guard maxVal > 0 else {
            return .gray
        }

        let ratio = value / maxVal

        if ratio > 0.7 {
            return .orange
        }

        if ratio > 0.3 {
            return .yellow
        }

        return .blue.opacity(0.6)
    }
}
