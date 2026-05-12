import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var store: DataStore
    @Binding var isComplete: Bool
    @State var page = 0

    var body: some View {
        ZStack {
            Color(red: 0.24, green: 0.39, blue: 0.50)
                .ignoresSafeArea()

            switch page {
            case 0: WelcomePage(onNext: { page = 1 })
            case 1: SkinTypePage(onNext: { page = 2 })
            case 2: AgePage(onNext: { page = 3 })
            case 3: ClothingPage(onNext: { page = 4 })
            case 4: BaselinePage(onNext: {
                store.profile.onboardingComplete = true
                store.saveProfile()
                isComplete = true
            })
            default: EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: page)
    }
}

// ── Progress dots ─────────────────────────────────────────────
struct ProgressDots: View {
    let total:   Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i == current
                          ? Color.white
                          : Color.white.opacity(0.3))
                    .frame(width: i == current ? 10 : 7,
                           height: i == current ? 10 : 7)
                    .animation(.spring(), value: current)
            }
        }
    }
}

// ── Shared button style ───────────────────────────────────────
struct PrimaryButton: View {
    let label:  String
    let action: () -> Void
    var disabled = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(disabled
                    ? Color.white.opacity(0.25)
                    : Color.white)
                .foregroundColor(disabled
                    ? Color.white.opacity(0.5)
                    : Color(red: 0.02, green: 0.50, blue: 0.56))
                .cornerRadius(16)
        }
        .disabled(disabled)
        .padding(.horizontal, 32)
    }
}

// ── Page 0 — Welcome ──────────────────────────────────────────
struct WelcomePage: View {
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("☀️").font(.system(size: 80)).padding(.bottom, 24)
            Text("Welcome to UVita")
                .font(.system(size: 34, weight: .black))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text("Your personal vitamin D tracker.\nWe'll ask you 3 quick questions to\npersonalize your estimates.")
                .font(.system(size: 17))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.top, 16).padding(.horizontal, 32)
            Spacer()
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "location.fill")
                        .foregroundColor(.white.opacity(0.7))
                    Text("GPS tracks your UV exposure")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                }
                HStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundColor(.white.opacity(0.7))
                    Text("Diffey/Holick model estimates plasma 25(OH)D")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                }
                HStack(spacing: 12) {
                    Image(systemName: "building.2.fill")
                        .foregroundColor(.white.opacity(0.7))
                    Text("Detects when you're indoors")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                }
            }
            .padding(.horizontal, 36).padding(.bottom, 32)
            PrimaryButton(label: "Get started", action: onNext)
                .padding(.bottom, 52)
        }
    }
}

// ── Page 1 — Skin type ────────────────────────────────────────
struct SkinTypePage: View {
    @EnvironmentObject var store: DataStore
    var onNext: () -> Void

    let types: [(roman: String, label: String, desc: String,
                 example: String, emoji: String,
                 modelTier: SkinType)] = [
        ("I",  "Very fair", "Always burns, never tans",
         "Pale white skin, often freckles", "👱🏻", .typeI_II),
        ("II", "Fair", "Usually burns, tans minimally",
         "White skin, light hair", "🧑🏼", .typeI_II),
        ("III","Medium", "Sometimes burns, tans gradually",
         "Light brown skin", "🧑🏽", .typeIII_VI),
        ("IV", "Olive", "Rarely burns, tans easily",
         "Moderate brown skin", "🧑🏾", .typeIII_VI),
        ("V",  "Brown", "Very rarely burns, tans darkly",
         "Dark brown skin", "🧑🏿", .typeIII_VI),
        ("VI", "Dark", "Never burns, deeply pigmented",
         "Very dark brown/black skin", "🧿", .typeIII_VI),
    ]
    @State var selectedIndex: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                ProgressDots(total: 3, current: 0).padding(.top, 60)
                Text("What's your skin type?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white).padding(.top, 16)
                Text("This determines how much vitamin D\nyour skin produces per UV dose.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center).padding(.top, 4)
            }.padding(.horizontal, 24)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(types.indices, id: \.self) { i in
                        let t = types[i]
                        let selected = selectedIndex == i
                        Button {
                            selectedIndex = i
                            store.profile.skinType = t.modelTier
                        } label: {
                            HStack(spacing: 14) {
                                Text(t.emoji).font(.system(size: 36)).frame(width: 48)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text("Type \(t.roman)")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(selected
                                                ? Color(red: 0.02, green: 0.50, blue: 0.56)
                                                : .white)
                                        Text(t.label)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(selected
                                                ? Color(red: 0.02, green: 0.50, blue: 0.56)
                                                : .white)
                                    }
                                    Text(t.desc).font(.caption)
                                        .foregroundColor(selected
                                            ? Color(red: 0.02, green: 0.50, blue: 0.56).opacity(0.7)
                                            : .white.opacity(0.65))
                                    Text(t.example).font(.caption2)
                                        .foregroundColor(selected
                                            ? Color(red: 0.02, green: 0.50, blue: 0.56).opacity(0.55)
                                            : .white.opacity(0.5))
                                }
                                Spacer()
                                Text(t.modelTier == .typeI_II
                                     ? "f_skin = 1.00" : "f_skin = 0.74")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(selected
                                        ? Color(red: 0.02, green: 0.50, blue: 0.56).opacity(0.6)
                                        : .white.opacity(0.4))
                                if selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Color(red: 0.02, green: 0.50, blue: 0.56))
                                        .font(.title3)
                                }
                            }
                            .padding(14)
                            .background(selected ? Color.white : Color.white.opacity(0.12))
                            .cornerRadius(14)
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 8)
            }

            if let i = selectedIndex {
                let tier = types[i].modelTier
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").font(.caption)
                    Text(tier == .typeI_II
                         ? "Types I–II: standard UV sensitivity (f_skin = 1.00, Eq. 9)"
                         : "Types III–VI: 35% more UV needed for same synthesis (f_skin = 1/1.35, Eq. 9)")
                        .font(.caption)
                }
                .foregroundColor(.white.opacity(0.65))
                .padding(.horizontal, 28).padding(.vertical, 8)
            }

            PrimaryButton(
                label: "Continue",
                action: { store.saveProfile(); onNext() },
                disabled: selectedIndex == nil)
            .padding(.bottom, 40)
        }
    }
}

// ── Page 2 — Age ──────────────────────────────────────────────
struct AgePage: View {
    @EnvironmentObject var store: DataStore
    var onNext: () -> Void
    @State var age: Double = 22

    var ageFactor: Double { max(0.1, 1.0 - 0.013 * (age - 20)) }
    var ageLabel: String {
        switch Int(age) {
        case ..<18:   return "Teenager"
        case 18..<25: return "Young adult"
        case 25..<40: return "Adult"
        case 40..<60: return "Middle-aged adult"
        case 60..<75: return "Older adult"
        default:      return "Senior"
        }
    }
    var synthesisNote: String {
        let pct = Int((1.0 - ageFactor) * 100)
        if pct <= 0 { return "Peak vitamin D synthesis" }
        return "~\(pct)% lower synthesis than age 20 (Eq. 10)"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                ProgressDots(total: 3, current: 1).padding(.top, 60)
                Text("How old are you?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white).padding(.top, 16)
                Text("Vitamin D synthesis declines about\n1.3% per year after age 20.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center).padding(.top, 4)
            }.padding(.horizontal, 24)
            Spacer()
            VStack(spacing: 6) {
                Text("\(Int(age))")
                    .font(.system(size: 96, weight: .black, design: .rounded))
                    .foregroundColor(.white).animation(.none, value: age)
                Text(ageLabel)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }.padding(.vertical, 24)
            VStack(spacing: 8) {
                Slider(value: $age, in: 13...90, step: 1)
                    .tint(.white).padding(.horizontal, 32)
                    .onChange(of: age) { store.profile.age = Int(age) }
                HStack {
                    Text("13").font(.caption).foregroundColor(.white.opacity(0.5))
                    Spacer()
                    Text("90").font(.caption).foregroundColor(.white.opacity(0.5))
                }.padding(.horizontal, 36)
            }
            Spacer()
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Age factor (f_age)").font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                        Text(String(format: "%.3f", ageFactor))
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Effect").font(.caption).foregroundColor(.white.opacity(0.6))
                        Text(synthesisNote).font(.caption)
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.trailing)
                    }
                }
                .padding(16).background(Color.white.opacity(0.12)).cornerRadius(14)
                .padding(.horizontal, 28)
                Text("You can update your age each year in Profile settings.")
                    .font(.caption2).foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
            }.padding(.bottom, 24)
            PrimaryButton(label: "Continue", action: {
                store.profile.age = Int(age)
                store.saveProfile()
                onNext()
            }).padding(.bottom, 40)
        }
    }
}

// ── Page 3 — Clothing ─────────────────────────────────────────
struct ClothingPage: View {
    @EnvironmentObject var store: DataStore
    var onNext: () -> Void
    @State var selected: ClothingOption? = nil

    let options: [(opt: ClothingOption, emoji: String, desc: String)] = [
        (.fullyCovered,      "🧥", "Full coverage — coat, hoodie, long everything"),
        (.longSleevesPants,  "👔", "Long sleeves + pants — office or cool day"),
        (.tshirtPants,       "👕", "T-shirt + pants — typical casual"),
        (.tshirtShorts,      "🩳", "T-shirt + shorts — warm day"),
        (.tankShorts,        "💪", "Tank top + shorts — hot day, beach"),
        (.swimwear,          "🩱", "Swimwear — pool, beach, sunbathing"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                ProgressDots(total: 3, current: 2).padding(.top, 60)
                Text("What do you\ntypically wear outdoors?")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white).multilineTextAlignment(.center).padding(.top, 16)
                Text("Sets your exposed body surface area (BSA).\nYou can change this every day from the Today tab.")
                    .font(.subheadline).foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center).padding(.top, 4).padding(.horizontal, 20)
            }.padding(.horizontal, 24)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(options, id: \.opt) { item in
                        let isSelected = selected == item.opt
                        Button {
                            selected = item.opt
                            store.profile.clothing = item.opt
                        } label: {
                            HStack(spacing: 12) {
                                Text(item.emoji).font(.system(size: 30)).frame(width: 42)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.opt.rawValue)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(isSelected
                                            ? Color(red: 0.02, green: 0.50, blue: 0.56) : .white)
                                    Text(item.desc).font(.caption)
                                        .foregroundColor(isSelected
                                            ? Color(red: 0.02, green: 0.50, blue: 0.56).opacity(0.7)
                                            : .white.opacity(0.6))
                                }
                                Spacer()
                                Text("BSA \(Int(item.opt.bsaPercent))%")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(isSelected
                                        ? Color(red: 0.02, green: 0.50, blue: 0.56)
                                        : .white.opacity(0.5))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(isSelected ? Color.white : Color.white.opacity(0.1))
                                    .cornerRadius(8)
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Color(red: 0.02, green: 0.50, blue: 0.56))
                                }
                            }
                            .padding(12)
                            .background(isSelected ? Color.white : Color.white.opacity(0.1))
                            .cornerRadius(14)
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 8)
            }

            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.caption)
                Text("Change this daily from the Today tab — it affects your vitamin D estimate directly.")
                    .font(.caption)
            }
            .foregroundColor(.white.opacity(0.6))
            .padding(.horizontal, 28).padding(.bottom, 12)

            PrimaryButton(
                label: "Continue",
                action: { store.saveProfile(); onNext() },
                disabled: selected == nil)
            .padding(.bottom, 40)
        }
    }
}

// ── Page 4 — Baseline ─────────────────────────────────────────
struct BaselinePage: View {
    @EnvironmentObject var store: DataStore
    var onNext: () -> Void

    @State var knowsLevel = false
    @State var levelText  = ""
    @State var useDefault = true

    // Dismiss the numeric keyboard
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle().fill(Color.white.opacity(0.15))
                    .frame(width: 120, height: 120)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72)).foregroundColor(.white)
            }.padding(.bottom, 28)

            Text("Almost done!")
                .font(.system(size: 32, weight: .black))
                .foregroundColor(.white)
            Text("One last thing — do you know your current vitamin D level from a blood test?")
                .font(.subheadline).foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36).padding(.top, 12)
            Spacer()

            VStack(spacing: 12) {
                // Option A — enter blood test
                Button {
                    knowsLevel = true
                    useDefault = false
                } label: {
                    HStack {
                        Image(systemName: "drop.fill")
                            .foregroundColor(knowsLevel
                                ? Color(red: 0.02, green: 0.50, blue: 0.56) : .white)
                        Text("Yes — I have a blood test result")
                            .fontWeight(.semibold)
                            .foregroundColor(knowsLevel
                                ? Color(red: 0.02, green: 0.50, blue: 0.56) : .white)
                        Spacer()
                        if knowsLevel {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(red: 0.02, green: 0.50, blue: 0.56))
                        }
                    }
                    .padding(16)
                    .background(knowsLevel ? Color.white : Color.white.opacity(0.12))
                    .cornerRadius(14)
                }

                // Blood level input — keyboard trap fixed:
                // toolbar Done button dismisses keyboard,
                // and the "Start tracking" button also
                // dismisses before proceeding.
                if knowsLevel {
                    HStack {
                        TextField("e.g. 45", text: $levelText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .frame(width: 100)
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button("Done") { dismissKeyboard() }
                                        .foregroundColor(Color(red: 0.02, green: 0.50, blue: 0.56))
                                        .fontWeight(.semibold)
                                }
                            }
                        Text("nmol/L")
                            .font(.title3).foregroundColor(.white.opacity(0.7))
                    }
                    .padding(16).background(Color.white.opacity(0.1)).cornerRadius(14)

                    if let val = Double(levelText) {
                        Text(val < 30
                             ? "Deficient — model will show your recovery trajectory"
                             : val < 50
                             ? "Insufficient — getting closer to sufficiency"
                             : "Sufficient — model will show how to maintain this")
                            .font(.caption)
                            .foregroundColor(val < 30
                                ? Color(red: 1, green: 0.4, blue: 0.4)
                                : val < 50
                                ? Color(red: 1, green: 0.7, blue: 0.2)
                                : Color(red: 0.4, green: 0.9, blue: 0.5))
                            .multilineTextAlignment(.center)
                    }
                }

                // Option B — use default 30 nmol/L
                Button {
                    knowsLevel = false
                    useDefault = true
                    levelText  = ""
                    dismissKeyboard()
                } label: {
                    HStack {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(useDefault
                                ? Color(red: 0.02, green: 0.50, blue: 0.56) : .white)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No — use the default")
                                .fontWeight(.semibold)
                                .foregroundColor(useDefault
                                    ? Color(red: 0.02, green: 0.50, blue: 0.56) : .white)
                            Text("We'll start at 30 nmol/L — the deficiency threshold")
                                .font(.caption)
                                .foregroundColor(useDefault
                                    ? Color(red: 0.02, green: 0.50, blue: 0.56).opacity(0.7)
                                    : .white.opacity(0.6))
                        }
                        Spacer()
                        if useDefault {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(red: 0.02, green: 0.50, blue: 0.56))
                        }
                    }
                    .padding(16)
                    .background(useDefault ? Color.white : Color.white.opacity(0.12))
                    .cornerRadius(14)
                }
            }
            .padding(.horizontal, 28)
            Spacer()

            // Dismiss keyboard before proceeding so the
            // button is always tappable even if number
            // keyboard is up
            PrimaryButton(
                label: "Start tracking",
                action: {
                    dismissKeyboard()
                    if knowsLevel,
                       let val = Double(levelText), val > 0 {
                        store.profile.initialLevel = val
                    } else {
                        store.profile.initialLevel = 30.0
                    }
                    store.saveProfile()
                    onNext()
                },
                disabled: knowsLevel && Double(levelText) == nil)
            .padding(.bottom, 52)
        }
    }
}
