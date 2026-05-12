import SwiftUI

struct TodayView: View {
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var store:    DataStore
    @EnvironmentObject var tracker:  BackgroundTracker

    @State private var showOralSourceSheet = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {

                    // GPS + indoor status
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(location.ready ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(location.statusMessage)
                                    .font(.caption).foregroundColor(.secondary)
                                if location.ready {
                                    Text(tracker.indoors
                                         ? "🏠 Indoors — UV set to 0"
                                         : "☀ Outdoors")
                                        .font(.caption)
                                        .foregroundColor(tracker.indoors ? .orange : .green)
                                }
                            }
                            Spacer()
                        }
                    }
                    .padding(.horizontal)

                    // Tracking toggle
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tracker.isTracking
                                     ? "Tracking active"
                                     : "Tracking paused")
                                    .font(.headline)
                                // Interval string matches BackgroundTracker.logInterval (10 min)
                                Text(tracker.isTracking
                                     ? "Logging every 10 min · \(tracker.todayCount) today"
                                     : "Tap Start — stays on until you tap Stop")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(tracker.isTracking ? "Stop" : "Start") {
                                if tracker.isTracking {
                                    tracker.stop()
                                } else {
                                    tracker.start(location: location, store: store)
                                }
                            }
                            .disabled(!location.ready)
                            .buttonStyle(.borderedProminent)
                            .tint(tracker.isTracking ? .red : .green)
                        }
                        if let t = tracker.lastLogTime {
                            Text("Last logged: \(t.formatted(.relative(presentation: .named)))")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(16).padding(.horizontal)

                    PlasmaCard()
                    DailyTotalCard()
                    TodayLogCard()
                    ClothingCard()

                    // Daily oral intake prompt
                    FoodSourceCard(showSheet: $showOralSourceSheet)

                    SupplementCard()
                }
                .padding(.vertical)
            }
            .navigationTitle("UVita")
            .onAppear {
                tracker.autoResume(location: location, store: store)
            }
            .sheet(isPresented: $showOralSourceSheet) {
                OralSourcePickerSheet()
                    .environmentObject(store)
            }
        }
    }
}

// ── Plasma level ──────────────────────────────────────────────
struct PlasmaCard: View {
    @EnvironmentObject var store: DataStore

    var level: Double { store.currentPlasmaLevel() }
    var color: Color {
        level < 30 ? .red : level < 50 ? .orange : .green
    }
    var label: String {
        level < 30 ? "Deficient  (<30 nmol/L)"
        : level < 50 ? "Insufficient  (30–50 nmol/L)"
        : "Sufficient  (50+ nmol/L)"
    }

    var body: some View {
        VStack(spacing: 6) {
            Text("Estimated plasma 25(OH)D")
                .font(.caption).foregroundColor(.secondary)
            Text(String(format: "%.0f", level))
                .font(.system(size: 68, weight: .black))
                .foregroundColor(color)
            Text("nmol/L").font(.subheadline).foregroundColor(.secondary)
            Text(label)
                .font(.caption).fontWeight(.semibold)
                .padding(.horizontal, 14).padding(.vertical, 5)
                .background(color.opacity(0.12)).foregroundColor(color)
                .cornerRadius(99)
            if store.todayReadings.last?.uvi == 0 {
                Text("UV was 0 — indoors or night")
                    .font(.caption2).foregroundColor(.secondary).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity).padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16).padding(.horizontal)
    }
}

// ── Daily total ───────────────────────────────────────────────
struct DailyTotalCard: View {
    @EnvironmentObject var store: DataStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today's vitamin D").font(.headline)
            HStack(spacing: 0) {
                VStack(spacing: 3) {
                    Text("UV Dose").font(.caption2).foregroundColor(.secondary)
                    Text(String(format: "%.3f", store.todaySED()))
                        .font(.title3).fontWeight(.bold).foregroundColor(.orange)
                    Text("SED today").font(.caption2).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                Divider().frame(height: 40)
                VStack(spacing: 3) {
                    Text("Readings").font(.caption2).foregroundColor(.secondary)
                    Text("\(store.todayReadings.count)")
                        .font(.title3).fontWeight(.bold).foregroundColor(.blue)
                    Text("logged today").font(.caption2).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                Divider().frame(height: 40)
                VStack(spacing: 3) {
                    Text("Est. 25(OH)D").font(.caption2).foregroundColor(.secondary)
                    Text(String(format: "%.0f", store.currentPlasmaLevel()))
                        .font(.title3).fontWeight(.bold)
                        .foregroundColor(store.currentPlasmaLevel() < 30 ? .red
                            : store.currentPlasmaLevel() < 50 ? .orange : .green)
                    Text("nmol/L").font(.caption2).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text("Progress toward sufficiency (50 nmol/L)")
                    .font(.caption2).foregroundColor(.secondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5)).frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(store.currentPlasmaLevel() < 30 ? Color.red
                                : store.currentPlasmaLevel() < 50 ? Color.orange
                                : Color.green)
                            .frame(
                                width: geo.size.width * CGFloat(
                                    min(1.0, store.currentPlasmaLevel() / 50.0)),
                                height: 8)
                    }
                }
                .frame(height: 8)
                Text(String(format: "%.0f%% of sufficient level",
                    min(100, store.currentPlasmaLevel() / 50.0 * 100)))
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16).padding(.horizontal)
    }
}

// ── Today's log ───────────────────────────────────────────────
struct TodayLogCard: View {
    @EnvironmentObject var store: DataStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.todayReadings.isEmpty {
                Text("No readings yet — tap Start above")
                    .font(.caption).foregroundColor(.secondary).padding(.horizontal)
            } else {
                DisclosureGroup {
                    VStack(spacing: 0) {
                        ForEach(store.todayReadings.sorted { $0.date > $1.date }) { r in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.date.formatted(.dateTime.hour().minute()))
                                        .font(.caption2).foregroundColor(.secondary)
                                    Text(String(format:
                                        "UVI %.1f · BSA %.0f%% · SED %.4f",
                                        r.uvi, r.bsaPercent, r.sed))
                                        .font(.caption)
                                }
                                Spacer()
                                Text(String(format: "%.0f nmol/L", r.plasmaLevel))
                                    .font(.caption).fontWeight(.semibold)
                            }
                            .padding(.horizontal).padding(.vertical, 8)
                            Divider().padding(.horizontal)
                        }
                    }
                } label: {
                    HStack {
                        Text("Today's readings").font(.headline)
                        Spacer()
                        Text("\(store.todayReadings.count)")
                            .font(.caption).foregroundColor(.secondary)
                    }.padding(.horizontal)
                }
            }
        }
        .padding(.vertical)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16).padding(.horizontal)
    }
}

// ── Food / oral source card ───────────────────────────────────
// Shown every day. If no diet data is set up, prompts the user
// to choose a source. Once chosen, shows today's logged total.
struct FoodSourceCard: View {
    @EnvironmentObject var store: DataStore
    @Binding var showSheet: Bool

    var todayOralUg: Double { store.todayOralUgFromFoodLog() }

    var sourceLabel: String {
        switch store.profile.oralSource {
        case .healthKit:   return "Apple Health"
        case .manualLog:   return "Food log"
        case .manualIU:    return "Manual entry"
        case .useEstimate: return "Population avg (5 µg/day)"
        case .assumeZero:  return "Assumed 0"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Oral vitamin D intake (O(t))")
                    .font(.headline)
                Spacer()
                Button("Change") { showSheet = true }
                    .font(.caption).foregroundColor(.blue)
            }

            // If still on default (useEstimate) or assumeZero and
            // no food data logged, show the daily prompt
            let noDataLogged = store.profile.oralSource == .useEstimate
                || store.profile.oralSource == .assumeZero

            if noDataLogged {
                Text("How should the model handle your dietary vitamin D today?")
                    .font(.caption).foregroundColor(.secondary)
                Button {
                    showSheet = true
                } label: {
                    HStack {
                        Image(systemName: "fork.knife.circle.fill")
                            .foregroundColor(.blue)
                        Text("Choose oral intake source")
                            .font(.subheadline).fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(10)
                }
            } else {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Source").font(.caption2).foregroundColor(.secondary)
                        Text(sourceLabel).font(.subheadline).fontWeight(.semibold)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Today").font(.caption2).foregroundColor(.secondary)
                        Text(String(format: "%.1f µg", todayOralUg))
                            .font(.subheadline).fontWeight(.bold).foregroundColor(.blue)
                    }
                }
                .padding(12)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(10)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16).padding(.horizontal)
    }
}

// ── Oral source picker sheet ──────────────────────────────────
// Presented modally — lets user choose daily oral intake method
struct OralSourcePickerSheet: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("Choose how to track dietary vitamin D") {

                    SourceRow(
                        icon: "heart.text.square.fill",
                        iconColor: .red,
                        title: "Apple Health (auto)",
                        subtitle: "Reads from Cal AI, MyFitnessPal, Cronometer, or any app that writes to Health",
                        selected: store.profile.oralSource == .healthKit
                    ) {
                        store.profile.oralSource = .healthKit
                        store.saveProfile()
                    }

                    SourceRow(
                        icon: "barcode.viewfinder",
                        iconColor: .blue,
                        title: "Log food in UVita",
                        subtitle: "Search foods or scan a barcode — data written back to Apple Health",
                        selected: store.profile.oralSource == .manualLog
                    ) {
                        store.profile.oralSource = .manualLog
                        store.saveProfile()
                    }

                    SourceRow(
                        icon: "pencil.circle.fill",
                        iconColor: .orange,
                        title: "Enter IU/day manually",
                        subtitle: "Set a fixed supplement dose in IU",
                        selected: store.profile.oralSource == .manualIU
                    ) {
                        store.profile.oralSource = .manualIU
                        store.saveProfile()
                    }

                    SourceRow(
                        icon: "chart.bar.fill",
                        iconColor: .purple,
                        title: "Population average (5 µg/day)",
                        subtitle: "Uses ~200 IU/day — the typical dietary intake from food in Western adults",
                        selected: store.profile.oralSource == .useEstimate
                    ) {
                        store.profile.oralSource = .useEstimate
                        store.saveProfile()
                    }

                    SourceRow(
                        icon: "xmark.circle.fill",
                        iconColor: .gray,
                        title: "Assume 0",
                        subtitle: "No dietary vitamin D counted — UV synthesis only",
                        selected: store.profile.oralSource == .assumeZero
                    ) {
                        store.profile.oralSource = .assumeZero
                        store.saveProfile()
                    }
                }
            }
            .navigationTitle("Oral intake source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct SourceRow: View {
    let icon:      String
    let iconColor: Color
    let title:     String
    let subtitle:  String
    let selected:  Bool
    let onTap:     () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3).foregroundColor(iconColor)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// ── Supplement ────────────────────────────────────────────────
struct SupplementCard: View {
    @EnvironmentObject var store: DataStore
    @State private var iuText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily vitamin D supplement")
                .font(.headline)
            Text("O(t) oral input — enter 0 if none")
                .font(.caption).foregroundColor(.secondary)
            HStack {
                TextField("e.g. 1000", text: $iuText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") {
                                UIApplication.shared.sendAction(
                                    #selector(UIResponder.resignFirstResponder),
                                    to: nil, from: nil, for: nil)
                            }
                        }
                    }
                Text("IU/day").foregroundColor(.secondary)
                Button("Save") {
                    store.profile.oralIU = Double(iuText) ?? 0
                    store.saveProfile()
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil)
                }
                .buttonStyle(.borderedProminent)
            }
            Text(String(format: "= %.2f µg/day",
                        store.profile.oralIU / 40.0))
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16).padding(.horizontal)
        .onAppear {
            iuText = store.profile.oralIU == 0
                ? "" : String(Int(store.profile.oralIU))
        }
    }
}

// ── Clothing picker ───────────────────────────────────────────
struct ClothingCard: View {
    @EnvironmentObject var store:    DataStore
    @EnvironmentObject var tracker:  BackgroundTracker
    @EnvironmentObject var location: LocationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("What are you wearing?").font(.headline)
                Text("Sets exposed body surface area")
                    .font(.caption).foregroundColor(.secondary)
            }
            ForEach(ClothingOption.allCases, id: \.rawValue) { opt in
                Button {
                    store.profile.clothing = opt
                    store.saveProfile()
                    Task {
                        await tracker.logNow(location: location, store: store)
                    }
                } label: {
                    HStack {
                        Text(opt.rawValue).foregroundColor(.primary)
                        Spacer()
                        Text("BSA \(Int(opt.bsaPercent))%")
                            .font(.caption).foregroundColor(.secondary)
                        if store.profile.clothing == opt {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(10)
                    .background(store.profile.clothing == opt
                        ? Color.blue.opacity(0.08)
                        : Color(.tertiarySystemBackground))
                    .cornerRadius(10)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16).padding(.horizontal)
    }
}
