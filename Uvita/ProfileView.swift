import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var store: DataStore
    @State private var ageText = ""

    var body: some View {
        NavigationView {
            Form {
                Section("About you") {
                    HStack {
                        Text("Age")
                        Spacer()
<<<<<<< HEAD
                        TextField("22", text: $ageText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            onChange(of: ageText) {
=======
                        TextField("21", text: $ageText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .onChange(of: ageText) {
>>>>>>> a566aef (Fix onboarding, insights redesign, dropdown history, tracking behavior, and profile updates)
                                if let a = Int(ageText) {
                                    store.profile.age = a
                                    store.saveProfile()
                                }
                            }
                    }
                    Text(String(format:
                        "Age factor f_age = %.3f (Eq. 10)",
                        VitaminDEngine.ageFactor(store.profile.age)))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Skin type",
                           selection: $store.profile.skinType) {
                        ForEach(SkinType.allCases) { s in
                            VStack(alignment: .leading) {
                                Text(s.rawValue)
                                Text(s.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }.tag(s)
                        }
                    }
                    .onChange(of: store.profile.skinType) {
                        store.saveProfile()
                    }
                    Text(String(format:
                        "Skin factor f_skin = %.4f (Eq. 9)",
                        store.profile.skinType.factor))
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                            .onChange(of: store.profile.initialLevel) {
                                store.saveProfile()
                            }
                        Text("nmol/L")
                            .foregroundColor(.secondary)
                    }
                    Text(store.profile.initialLevel < 30
                         ? "Deficient starting point — model will show recovery trajectory."
                         : store.profile.initialLevel < 50
                         ? "Insufficient starting point."
                         : "Sufficient starting point — enter your actual blood test result for accuracy.")
                        .font(.caption)
                        .foregroundColor(
                            store.profile.initialLevel < 30 ? .red
                            : store.profile.initialLevel < 50 ? .orange
                            : .green)
                    Text("Default 30 nmol/L = deficiency threshold. Enter your actual serum result from a blood test for a personalized projection.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Button("Reset to 30 nmol/L (default)") {
                        store.profile.initialLevel = 30
                        store.saveProfile()
                    }
                    .foregroundColor(.orange)
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

    func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption)
            Spacer()
            Text(value).font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
