import SwiftUI
import AVFoundation

struct TodayView: View {
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var store:    DataStore
    @EnvironmentObject var tracker:  BackgroundTracker

    @State private var showOralSourceSheet = false
    @State private var showFoodLogSheet    = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {
                    GPSStatusCard()
                    TrackingToggleCard()
                    PlasmaCard()
                    DailyTotalCard()
                    TodayLogCard()
                    ClothingCard()
                    FoodSourceCard(
                        showSourceSheet: $showOralSourceSheet,
                        showFoodLog:     $showFoodLogSheet)
                    SupplementCard()
                }
                .padding(.vertical)
            }
            .navigationTitle("UVita")
            .onAppear {
                tracker.autoResume(location: location, store: store)
            }
            .sheet(isPresented: $showOralSourceSheet) {
                OralSourcePickerSheet().environmentObject(store)
            }
            .sheet(isPresented: $showFoodLogSheet) {
                FoodLogView().environmentObject(store)
            }
        }
    }
}

// ── GPS status + manual override toggle ──────────────────────
struct GPSStatusCard: View {
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var store:    DataStore
    @EnvironmentObject var tracker:  BackgroundTracker

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(location.ready ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(location.statusMessage)
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
            }

            if location.ready {
                HStack(spacing: 10) {
                    // Current state label
                    Label(
                        tracker.indoors ? "Indoors" : "Outdoors",
                        systemImage: tracker.indoors
                            ? "building.2.fill" : "sun.max.fill")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(tracker.indoors ? .orange : .green)

                    if tracker.manualIndoorOverride != nil {
                        Text("(manual)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Override toggle — for evaluation of detector accuracy
                    Button {
                        tracker.userOverrideIndoor(
                            !tracker.indoors,
                            location: location,
                            store: store)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption)
                            Text(tracker.indoors
                                 ? "Mark as outdoors"
                                 : "Mark as indoors")
                                .font(.caption)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color(.tertiarySystemBackground))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                    }
                }

                if tracker.manualIndoorOverride == nil {
                    Text("Auto-detected · tap to correct if wrong")
                        .font(.caption2).foregroundColor(.secondary)
                } else {
                    Text("Manually set · will revert when location changes")
                        .font(.caption2).foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16).padding(.horizontal)
    }
}

// ── Tracking toggle ───────────────────────────────────────────
struct TrackingToggleCard: View {
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var store:    DataStore
    @EnvironmentObject var tracker:  BackgroundTracker
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tracker.isTracking ? "Tracking active" : "Tracking paused")
                        .font(.headline)
                    Text(tracker.isTracking
                         ? "Logging every 5 min · \(tracker.todayCount) today"
                         : "Tap Start to begin logging")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button(tracker.isTracking ? "Stop" : "Start") {
                    if tracker.isTracking { tracker.stop() }
                    else { tracker.start(location: location, store: store) }
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
    }
}

// ── Plasma card ───────────────────────────────────────────────
struct PlasmaCard: View {
    @EnvironmentObject var store: DataStore
    var level: Double { store.currentPlasmaLevel() }
    var color: Color { level < 30 ? .red : level < 50 ? .orange : .green }
    var label: String {
        level < 30 ? "Deficient  (<30 nmol/L)"
        : level < 50 ? "Insufficient  (30–50 nmol/L)"
        : "Sufficient  (50+ nmol/L)"
    }
    var body: some View {
        VStack(spacing: 6) {
            Text("Estimated plasma 25(OH)D")
                .font(.caption).foregroundColor(.secondary)
            Text(String(format: "%.1f", level))
                .font(.system(size: 68, weight: .black)).foregroundColor(color)
            Text("nmol/L").font(.subheadline).foregroundColor(.secondary)
            Text(label)
                .font(.caption).fontWeight(.semibold)
                .padding(.horizontal, 14).padding(.vertical, 5)
                .background(color.opacity(0.12)).foregroundColor(color)
                .cornerRadius(99)
            if store.todayReadings.last?.uvi == 0 {
                Text("UV was 0 today — indoors or awaiting outdoor confirmation")
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
                    Text("UV dose").font(.caption2).foregroundColor(.secondary)
                    Text(String(format: "%.4f", store.todaySED()))
                        .font(.title3).fontWeight(.bold).foregroundColor(.orange)
                    Text("SED today").font(.caption2).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                Divider().frame(height: 40)
                VStack(spacing: 3) {
                    Text("Oral intake").font(.caption2).foregroundColor(.secondary)
                    Text(String(format: "%.1f µg", store.dailyOralUg()))
                        .font(.title3).fontWeight(.bold).foregroundColor(.blue)
                    Text("today").font(.caption2).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                Divider().frame(height: 40)
                VStack(spacing: 3) {
                    Text("Est. plasma").font(.caption2).foregroundColor(.secondary)
                    let level = store.currentPlasmaLevel()
                    Text(String(format: "%.1f", level))
                        .font(.title3).fontWeight(.bold)
                        .foregroundColor(level < 30 ? .red : level < 50 ? .orange : .green)
                    Text("nmol/L").font(.caption2).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text("Progress toward sufficiency (50 nmol/L)")
                    .font(.caption2).foregroundColor(.secondary)
                let level = store.currentPlasmaLevel()
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5)).frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(level < 30 ? Color.red
                                : level < 50 ? Color.orange : Color.green)
                            .frame(
                                width: geo.size.width * CGFloat(min(1.0, level / 50.0)),
                                height: 8)
                    }
                }.frame(height: 8)
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

// ── Today log ─────────────────────────────────────────────────
struct TodayLogCard: View {
    @EnvironmentObject var store: DataStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.todayReadings.isEmpty {
                Text("No readings yet — tap Start above")
                    .font(.caption).foregroundColor(.secondary).padding(.horizontal)
            } else {
                DisclosureGroup {
                    ForEach(store.todayReadings.sorted { $0.date > $1.date }) { r in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.date.formatted(.dateTime.hour().minute()))
                                    .font(.caption2).foregroundColor(.secondary)
                                Text(String(format:
                                    "UVI %.1f · BSA %.0f%% · SED %.5f%@",
                                    r.uvi, r.bsaPercent, r.sed,
                                    r.indoors ? " · indoors" : ""))
                                    .font(.caption)
                            }
                            Spacer()
                            Text(String(format: "%.1f nmol/L", r.plasmaLevel))
                                .font(.caption).fontWeight(.semibold)
                        }
                        .padding(.horizontal).padding(.vertical, 8)
                        Divider().padding(.horizontal)
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

// ── Food source card ──────────────────────────────────────────
struct FoodSourceCard: View {
    @EnvironmentObject var store: DataStore
    @Binding var showSourceSheet: Bool
    @Binding var showFoodLog: Bool

    var todayFoodUg: Double { store.todayOralUgFromFoodLog() }
    var sourceLabel: String {
        switch store.profile.oralSource {
        case .healthKit:   return "Apple Health"
        case .manualLog:   return "Food log"
        case .manualIU:    return "Manual IU entry"
        case .useEstimate: return "Population avg (5 µg/day)"
        case .assumeZero:  return "Assumed 0"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Oral vitamin D — O(t)").font(.headline)
                Spacer()
                Button("Change") { showSourceSheet = true }
                    .font(.caption).foregroundColor(.blue)
            }

            let isDefault = store.profile.oralSource == .useEstimate
                         || store.profile.oralSource == .assumeZero

            if isDefault {
                Text("Choose how to track dietary vitamin D today:")
                    .font(.caption).foregroundColor(.secondary)
                Button { showSourceSheet = true } label: {
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
                        Text("Today total").font(.caption2).foregroundColor(.secondary)
                        Text(String(format: "%.1f µg", store.dailyOralUg()))
                            .font(.subheadline).fontWeight(.bold).foregroundColor(.blue)
                    }
                }
                .padding(12)
                .background(Color(.tertiarySystemBackground)).cornerRadius(10)
            }

            // If manualLog, show today's food entries + button
            if store.profile.oralSource == .manualLog {
                if !store.todayFoodLog.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(store.todayFoodLog.sorted { $0.date > $1.date }) { e in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(e.name).font(.caption).fontWeight(.medium)
                                    Text(e.brand.isEmpty ? e.servingDesc
                                         : "\(e.brand) · \(e.servingDesc)")
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(String(format: "+%.1f µg", e.vitaminDug))
                                    .font(.caption).foregroundColor(.blue)
                                Button {
                                    store.removeFoodLog(e)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary).font(.caption)
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding(8)
                    .background(Color(.tertiarySystemBackground)).cornerRadius(10)
                }

                Button { showFoodLog = true } label: {
                    HStack {
                        Image(systemName: "barcode.viewfinder").foregroundColor(.blue)
                        Text("Log food / scan barcode")
                            .font(.subheadline).fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color(.tertiarySystemBackground)).cornerRadius(10)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16).padding(.horizontal)
    }
}

// ── Oral source picker ────────────────────────────────────────
struct OralSourcePickerSheet: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationView {
            List {
                Section("Choose how to track dietary vitamin D") {
                    SourceRow(icon: "heart.text.square.fill", iconColor: .red,
                              title: "Apple Health (auto)",
                              subtitle: "Reads from Cal AI, MyFitnessPal, Cronometer etc.",
                              selected: store.profile.oralSource == .healthKit) {
                        store.profile.oralSource = .healthKit; store.saveProfile()
                    }
                    SourceRow(icon: "barcode.viewfinder", iconColor: .blue,
                              title: "Log food in UVita",
                              subtitle: "Search foods or scan a barcode",
                              selected: store.profile.oralSource == .manualLog) {
                        store.profile.oralSource = .manualLog; store.saveProfile()
                    }
                    SourceRow(icon: "pencil.circle.fill", iconColor: .orange,
                              title: "Enter IU/day manually",
                              subtitle: "Fixed supplement dose",
                              selected: store.profile.oralSource == .manualIU) {
                        store.profile.oralSource = .manualIU; store.saveProfile()
                    }
                    SourceRow(icon: "chart.bar.fill", iconColor: .purple,
                              title: "Population average (5 µg/day)",
                              subtitle: "~200 IU/day typical Western dietary intake",
                              selected: store.profile.oralSource == .useEstimate) {
                        store.profile.oralSource = .useEstimate; store.saveProfile()
                    }
                    SourceRow(icon: "xmark.circle.fill", iconColor: .gray,
                              title: "Assume 0",
                              subtitle: "UV synthesis only — no oral intake counted",
                              selected: store.profile.oralSource == .assumeZero) {
                        store.profile.oralSource = .assumeZero; store.saveProfile()
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
    let icon: String; let iconColor: Color
    let title: String; let subtitle: String
    let selected: Bool; let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title3)
                    .foregroundColor(iconColor).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.blue)
                }
            }.padding(.vertical, 4)
        }
    }
}

// ── Supplement card ───────────────────────────────────────────
// Saves oralIU to profile and calls saveProfile() so the value
// is immediately reflected in dailyOralUg() for the model.
struct SupplementCard: View {
    @EnvironmentObject var store: DataStore
    @State private var iuText = ""
    @State private var saved  = false

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily vitamin D supplement").font(.headline)
            Text("Sets O(t) for manualIU source — enter 0 if none")
                .font(.caption).foregroundColor(.secondary)

            HStack {
                TextField("e.g. 1000", text: $iuText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { dismissKeyboard() }
                        }
                    }
                Text("IU/day").foregroundColor(.secondary)

                Button("Save") {
                    let val = Double(iuText) ?? 0
                    store.profile.oralIU = val
                    // Switch source to manualIU if not already
                    // on a manual mode so the save actually takes effect
                    if store.profile.oralSource == .useEstimate
                       || store.profile.oralSource == .assumeZero {
                        store.profile.oralSource = .manualIU
                    }
                    store.saveProfile()
                    dismissKeyboard()
                    saved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        saved = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(saved ? .green : .blue)

                if saved {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
            }

            HStack {
                Text(String(format: "= %.2f µg/day  ·  currently active: %@",
                    store.profile.oralIU / 40.0,
                    store.profile.oralSource == .manualIU ? "yes" : "no (change source above)"))
                    .font(.caption2).foregroundColor(.secondary)
            }
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
                Text("Sets exposed body surface area A(t)")
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

// ── Food log view — barcode + search ─────────────────────────
struct FoodLogView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) var dismiss
    @State private var searchText   = ""
    @State private var results:     [FoodItem] = []
    @State private var isSearching  = false
    @State private var showScanner  = false
    @State private var searchError  = ""
    @State private var addedToast   = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {

                // Search bar
                HStack(spacing: 10) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search food…", text: $searchText)
                            .submitLabel(.search)
                            .onSubmit { search() }
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)

                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                            .font(.title2).foregroundColor(.blue)
                    }
                }
                .padding()

                if !searchError.isEmpty {
                    Text(searchError).font(.caption).foregroundColor(.red)
                        .padding(.horizontal)
                }

                if isSearching {
                    ProgressView("Searching…").padding()
                    Spacer()
                } else if results.isEmpty && !searchText.isEmpty {
                    Text("No results found").font(.caption)
                        .foregroundColor(.secondary).padding()
                    Spacer()
                } else {
                    List(results) { item in
                        FoodItemRow(item: item) {
                            addFood(item)
                        }
                    }
                    .listStyle(.plain)
                }

                // Today's log
                if !store.todayFoodLog.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Today's food log")
                            .font(.headline).padding(.horizontal).padding(.top, 12)
                        Divider()
                        ForEach(store.todayFoodLog.sorted { $0.date > $1.date }) { e in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(e.name).font(.subheadline)
                                    Text(e.brand.isEmpty ? e.servingDesc
                                         : "\(e.brand) · \(e.servingDesc)")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(String(format: "+%.1f µg", e.vitaminDug))
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundColor(.blue)
                                Button {
                                    store.removeFoodLog(e)
                                } label: {
                                    Image(systemName: "trash").foregroundColor(.red)
                                        .font(.caption)
                                }
                            }
                            .padding(.horizontal).padding(.vertical, 8)
                            Divider().padding(.horizontal)
                        }
                        HStack {
                            Text("Total today")
                                .font(.subheadline).fontWeight(.semibold)
                            Spacer()
                            Text(String(format: "%.1f µg / %.0f IU",
                                store.todayOralUgFromFoodLog(),
                                store.todayOralUgFromFoodLog() * 40))
                                .font(.subheadline).fontWeight(.bold).foregroundColor(.blue)
                        }.padding()
                    }
                    .background(Color(.secondarySystemBackground))
                }
            }
            .navigationTitle("Log Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showScanner) {
                BarcodeScannerView { barcode in
                    showScanner = false
                    lookupBarcode(barcode)
                }
            }
            .overlay(
                addedToast
                ? Text("Added ✓")
                    .font(.subheadline).fontWeight(.semibold)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Color.green).foregroundColor(.white)
                    .cornerRadius(20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                : nil,
                alignment: .top)
        }
    }

    func search() {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        else { return }
        isSearching = true
        searchError = ""
        results     = []
        Task {
            do {
                results = try await FoodSearchService.search(query: searchText)
            } catch {
                searchError = "Search failed — check connection"
            }
            isSearching = false
        }
    }

    func lookupBarcode(_ barcode: String) {
        isSearching = true
        searchError = ""
        Task {
            do {
                if let item = try await FoodSearchService.lookup(barcode: barcode) {
                    results = [item]
                } else {
                    searchError = "Barcode not found in database"
                }
            } catch {
                searchError = "Lookup failed — check connection"
            }
            isSearching = false
        }
    }

    func addFood(_ item: FoodItem) {
        let entry = FoodLogEntry(
            name:        item.name,
            brand:       item.brand,
            vitaminDug:  item.vitaminDug,
            servingDesc: item.servingDesc,
            date:        Date())
        store.addFoodLog(entry)
        withAnimation { addedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { addedToast = false }
        }
    }
}

struct FoodItemRow: View {
    let item: FoodItem
    let onAdd: () -> Void
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.subheadline).fontWeight(.medium)
                Text(item.brand.isEmpty ? item.servingDesc
                     : "\(item.brand) · \(item.servingDesc)")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f µg", item.vitaminDug))
                    .font(.subheadline).fontWeight(.bold).foregroundColor(.blue)
                Text(String(format: "%.0f IU", item.vitaminDug * 40))
                    .font(.caption2).foregroundColor(.secondary)
            }
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2).foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

// ── Barcode scanner ───────────────────────────────────────────
struct BarcodeScannerView: UIViewControllerRepresentable {
    var onFound: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerVC {
        let vc = ScannerVC(); vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ uiViewController: ScannerVC,
                                 context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var onFound: (String) -> Void
        var found   = false
        init(onFound: @escaping (String) -> Void) { self.onFound = onFound }
        func metadataOutput(_ output: AVCaptureMetadataOutput,
                             didOutput metadataObjects: [AVMetadataObject],
                             from connection: AVCaptureConnection) {
            guard !found,
                  let obj  = metadataObjects.first,
                  let code = obj as? AVMetadataMachineReadableCodeObject,
                  let str  = code.stringValue else { return }
            found = true
            DispatchQueue.main.async { self.onFound(str) }
        }
    }
}

class ScannerVC: UIViewController {
    var delegate: AVCaptureMetadataOutputObjectsDelegate?
    private var session: AVCaptureSession?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let session   = AVCaptureSession()
        self.session  = session
        guard let device = AVCaptureDevice.default(for: .video),
              let input  = try? AVCaptureDeviceInput(device: device)
        else {
            showError("Camera not available"); return
        }
        session.addInput(input)
        let meta = AVCaptureMetadataOutput()
        session.addOutput(meta)
        meta.setMetadataObjectsDelegate(delegate,
            queue: DispatchQueue.main)
        meta.metadataObjectTypes = [
            .ean8, .ean13, .upce, .qr, .code128, .code39
        ]
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame           = view.bounds
        preview.videoGravity    = .resizeAspectFill
        view.layer.addSublayer(preview)

        // Aim box overlay
        let box      = UIView(frame: .zero)
        box.layer.borderColor = UIColor.white.cgColor
        box.layer.borderWidth = 2
        box.backgroundColor   = .clear
        view.addSubview(box)
        box.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            box.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            box.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            box.widthAnchor.constraint(equalToConstant: 260),
            box.heightAnchor.constraint(equalToConstant: 160)
        ])

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    private func showError(_ msg: String) {
        let lbl = UILabel()
        lbl.text          = msg
        lbl.textColor     = .white
        lbl.textAlignment = .center
        view.addSubview(lbl)
        lbl.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session?.stopRunning()
    }
}

// ── Food search service ───────────────────────────────────────
struct FoodItem: Identifiable {
    let id:          String
    let name:        String
    let brand:       String
    let vitaminDug:  Double   // µg per serving
    let servingDesc: String
}

struct FoodSearchService {

    // Search Open Food Facts first, fall back to USDA FoodData Central
    static func search(query: String) async throws -> [FoodItem] {
        var items = try await searchOpenFoodFacts(query: query)
        if items.isEmpty {
            items = try await searchUSDA(query: query)
        }
        return items
    }

    // Barcode lookup — Open Food Facts by barcode
    static func lookup(barcode: String) async throws -> FoodItem? {
        let url  = URL(string:
            "https://world.openfoodfacts.org/api/v0/product/\(barcode).json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data)
            as! [String: Any]
        guard let product = json["product"] as? [String: Any]
        else { return nil }
        return parseFoodFactsProduct(product)
    }

    // ── Open Food Facts search ────────────────────────────────
    private static func searchOpenFoodFacts(
        query: String) async throws -> [FoodItem] {
        var comps = URLComponents(
            string: "https://world.openfoodfacts.org/cgi/search.pl")!
        comps.queryItems = [
            .init(name: "search_terms",  value: query),
            .init(name: "search_simple", value: "1"),
            .init(name: "action",        value: "process"),
            .init(name: "json",          value: "1"),
            .init(name: "page_size",     value: "20"),
            .init(name: "fields",
                  value: "product_name,brands,nutriments,serving_size,quantity")
        ]
        let (data, _) = try await URLSession.shared
            .data(from: comps.url!)
        let json = try JSONSerialization.jsonObject(with: data)
            as! [String: Any]
        let products = json["products"] as? [[String: Any]] ?? []
        return products.compactMap { parseFoodFactsProduct($0) }
    }

    private static func parseFoodFactsProduct(
        _ p: [String: Any]) -> FoodItem? {
        guard let name = p["product_name"] as? String,
              !name.isEmpty else { return nil }
        let nutrients   = p["nutriments"] as? [String: Any] ?? [:]
        // vitamin-d_value is µg per 100g in Open Food Facts
        let vitDper100g = nutrients["vitamin-d_value"] as? Double
            ?? nutrients["vitamin-d"] as? Double ?? 0.0
        // Convert to per-serving
        let servingG    = parseGrams(p["serving_size"] as? String ?? "")
            ?? parseGrams(p["quantity"]    as? String ?? "")
            ?? 100.0
        let vitDug      = vitDper100g * servingG / 100.0
        let brand       = p["brands"] as? String ?? ""
        let serving     = p["serving_size"] as? String ?? "1 serving"
        return FoodItem(
            id:          name + brand,
            name:        name,
            brand:       brand,
            vitaminDug:  vitDug,
            servingDesc: serving)
    }

    // ── USDA FoodData Central ─────────────────────────────────
    private static func searchUSDA(
        query: String) async throws -> [FoodItem] {
        // USDA FoodData Central demo key — replace with real key
        // in production (https://fdc.nal.usda.gov/api-key-signup)
        let apiKey = "DEMO_KEY"
        var comps  = URLComponents(
            string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        comps.queryItems = [
            .init(name: "query",    value: query),
            .init(name: "pageSize", value: "20"),
            .init(name: "api_key",  value: apiKey)
        ]
        let (data, _) = try await URLSession.shared
            .data(from: comps.url!)
        let json  = try JSONSerialization.jsonObject(with: data)
            as! [String: Any]
        let foods = json["foods"] as? [[String: Any]] ?? []
        return foods.compactMap { parseUSDAFood($0) }
    }

    private static func parseUSDAFood(
        _ f: [String: Any]) -> FoodItem? {
        guard let name = f["description"] as? String else { return nil }
        let brand      = f["brandOwner"] as? String ?? ""
        let nutrients  = f["foodNutrients"] as? [[String: Any]] ?? []
        // USDA nutrient ID 1110 = Vitamin D (D2+D3) in µg
        let vitDug = nutrients.first(where: {
            ($0["nutrientId"] as? Int) == 1110
                || ($0["nutrientNumber"] as? String) == "1110"
        }).flatMap { $0["value"] as? Double } ?? 0.0
        let servingSize = f["servingSize"] as? Double ?? 100
        let servingUnit = f["servingSizeUnit"] as? String ?? "g"
        return FoodItem(
            id:          "\(f["fdcId"] ?? name)",
            name:        name,
            brand:       brand,
            vitaminDug:  vitDug,
            servingDesc: String(format: "%.0f %@", servingSize, servingUnit))
    }

    // Parse gram value from strings like "100g", "1 cup (240ml)"
    private static func parseGrams(_ s: String) -> Double? {
        let num = s.components(separatedBy: CharacterSet
            .decimalDigits.inverted
            .subtracting(.init(charactersIn: ".")))
            .joined()
        return Double(num)
    }
}
