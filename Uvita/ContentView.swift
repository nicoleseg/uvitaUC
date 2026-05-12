import SwiftUI

struct ContentView: View {

    @StateObject var location = LocationManager()
    @StateObject var store    = DataStore()
    @StateObject var tracker  = BackgroundTracker()

    @State private var showOnboarding = false

    var body: some View {
        Group {
            if showOnboarding {
                OnboardingView(isComplete: Binding(
                    get: { showOnboarding },
                    set: { showOnboarding = !$0 }
                ))
                .environmentObject(store)
            } else {
                TabView {
                    TodayView()
                        .tabItem { Label("Today", systemImage: "sun.max") }

                    InsightsView()
                        .tabItem { Label("Insights",
                            systemImage: "chart.line.uptrend.xyaxis") }

                    HistoryView()
                        .tabItem { Label("History", systemImage: "list.bullet") }

                    ProfileView()
                        .tabItem { Label("Profile", systemImage: "person.circle") }
                }
                .environmentObject(location)
                .environmentObject(store)
                .environmentObject(tracker)
            }
        }
        .onAppear {
            // Apply safe defaults if profile was never saved
            if store.profile.age == 0 {
                store.profile.age = 20
            }
            if store.profile.initialLevel == 0 {
                store.profile.initialLevel = 30
            }
            showOnboarding = !store.profile.onboardingComplete
        }
    }
}
