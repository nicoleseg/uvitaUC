import SwiftUI
import UIKit

struct BodyPartSEDCard: View {
    @EnvironmentObject var store: DataStore

    var parts: [(String, Double)] {
        store.getBodyPartSEDTotals()
    }
    var maxVal: Double {
        parts.map { $0.1 }.max() ?? 1
    }
    var mostExposed: (String, Double) {
        store.getMostExposedBodyPart()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("UV Exposure by Body Part")
                    .font(.headline)
                Text("Cumulative SED · Lund-Browder coefficients · outdoor auto readings only")
                    .font(.caption2).foregroundColor(.secondary)
            }

            if mostExposed.1 > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "sun.max.fill")
                        .foregroundColor(.orange)
                    (Text("Most exposed: ")
                        .foregroundColor(.secondary)
                    + Text(mostExposed.0)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                    + Text(String(format: " (%.4f SED)", mostExposed.1))
                        .foregroundColor(.secondary))
                    .font(.caption)
                }
                .padding(8)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(8)
            }

            if parts.allSatisfy({ $0.1 == 0 }) {
                Text("No outdoor readings yet")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(parts, id: \.0) { name, value in
                    HStack(spacing: 8) {
                        Text(name)
                            .font(.caption)
                            .frame(width: 80, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(UIColor.systemGray5))
                                    .frame(height: 14)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(barColor(value))
                                    .frame(
                                        width: max(4,
                                            geo.size.width * CGFloat(
                                                maxVal > 0
                                                ? value / maxVal : 0)),
                                        height: 14)
                            }
                        }
                        .frame(height: 14)
                        Text(String(format: "%.4f", value))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .trailing)
                    }
                }
            }

            Text("Outdoor auto readings only · Log Now snapshots excluded")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding()
        .background(Color.secondaryBackground)
        .cornerRadius(16)
        .padding(.horizontal)
    }

    func barColor(_ value: Double) -> Color {
        guard maxVal > 0 else { return .gray }
        let ratio = value / maxVal
        return ratio > 0.7 ? .orange : ratio > 0.3 ? .yellow : .blue.opacity(0.6)
    }
}
