import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var store: DataStore
    @State private var ageText = ""

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("About you") {
                    HStack {
                        Text("Age")
                        Spacer()
                        TextField("21", text: $ageText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button("Done") { dismissKeyboard() }
                                }
                            }
                            .onChange(of: ageText) {
                                if let a = Int(ageText) {
                                    store.profile.age = a
                                    store.saveProfile()
                                }
                            }
                    }
                    Text(String(format:
                        "Age factor f_age = %.3f (Eq. 10)",
                        VitaminDEngine.ageFactor(store.profile.age)))
                        .font(.caption).foregroundColor(.secondary)

                    Picker("Skin type", selection: $store.profile.skinType) {
                        ForEach(SkinType.allCases) { s in
                            VStack(alignment: .leading) {
                                Text(s.rawValue)
                                Text(s.description).font(.caption).foregroundColor(.secondary)
                            }.tag(s)
                        }
                    }
                    .onChange(of: store.profile.skinType) { store.saveProfile() }
                    Text(String(format:
                        "Skin factor f_skin = %.4f (Eq. 9)",
                        store.profile.skinType.factor))
                        .font(.caption).foregroundColor(.secondary)
                }

                Section("Baseline assumption") {
                    HStack {
                        Text("Starting 25(OH)D (C₀)")
                        Spacer()
                        TextField("30",
                            value: $store.profile.initialLevel,
                            format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .textFieldStyle(.roundedBorder)
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button("Done") { dismissKeyboard() }
                                }
                            }
                            .onChange(of: store.profile.initialLevel) {
                                store.saveProfile()
                            }
                        Text("nmol/L").foregroundColor(.secondary)
                    }
                    Text(store.profile.initialLevel < 30
                         ? "Deficient starting point."
                         : store.profile.initialLevel < 50
                         ? "Insufficient starting point."
                         : "Sufficient — enter your actual blood test result for accuracy.")
                        .font(.caption)
                        .foregroundColor(store.profile.initialLevel < 30 ? .red
                            : store.profile.initialLevel < 50 ? .orange : .green)
                    Text("Default 30 nmol/L = deficiency threshold. Enter your actual serum result for a personalized projection.")
                        .font(.caption2).foregroundColor(.secondary)
                    Button("Reset to 30 nmol/L (default)") {
                        store.profile.initialLevel = 30
                        store.saveProfile()
                    }.foregroundColor(.orange)
                }

                Section("Oral vitamin D source") {
                    Picker("Source", selection: $store.profile.oralSource) {
                        ForEach(OralIntakeSource.allCases, id: \.self) { src in
                            Text(src.rawValue).tag(src)
                        }
                    }
                    .onChange(of: store.profile.oralSource) { store.saveProfile() }

                    if store.profile.oralSource == .manualIU {
                        HStack {
                            Text("Supplement dose")
                            Spacer()
                            TextField("0", value: $store.profile.oralIU, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                                .toolbar {
                                    ToolbarItemGroup(placement: .keyboard) {
                                        Spacer()
                                        Button("Done") { dismissKeyboard() }
                                    }
                                }
                                .onChange(of: store.profile.oralIU) { store.saveProfile() }
                            Text("IU/day").foregroundColor(.secondary)
                        }
                        Text(String(format: "= %.2f µg/day", store.profile.oralIU / 40.0))
                            .font(.caption2).foregroundColor(.secondary)
                    }

                    Text(oralSourceNote).font(.caption2).foregroundColor(.secondary)
                }

                Section("Data") {
                    Button("Clear today's readings") {
                        store.clearToday()
                    }.foregroundColor(.orange)
                    Button("Clear all readings") {
                        store.clearAll()
                    }.foregroundColor(.red)
                }
            }
            .navigationTitle("Profile")
            .onAppear { ageText = String(store.profile.age) }
        }
    }

    var oralSourceNote: String {
        switch store.profile.oralSource {
        case .healthKit:
            return "Reads dietary vitamin D automatically from Apple Health. Make sure your food tracking app (Cal AI, MyFitnessPal, etc.) has Health sync enabled."
        case .manualLog:
            return "Log individual foods from the Today tab using the food search or barcode scanner."
        case .manualIU:
            return "Enter your daily supplement dose above. Food vitamin D is not counted separately."
        case .useEstimate:
            return "Uses 5 µg/day (~200 IU) — the average dietary vitamin D intake for Western adults. No food logging needed."
        case .assumeZero:
            return "No oral vitamin D is counted. The model uses UV synthesis only."
        }
    }
}
