import SwiftUI

struct ContentView: View {
    @StateObject var location = LocationManager()
    @StateObject var store    = DataStore()
    @StateObject var tracker  = BackgroundTracker()

    var body: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("Today",
                          systemImage: "sun.max")
                }
            InsightsView()
                .tabItem {
                    Label("Insights",
                          systemImage:
                          "chart.line.uptrend.xyaxis")
                }
            HistoryView()
                .tabItem {
                    Label("History",
                          systemImage: "list.bullet")
                }
            ProfileView()
                .tabItem {
                    Label("Profile",
                          systemImage: "person.circle")
                }
        }
        .environmentObject(location)
        .environmentObject(store)
        .environmentObject(tracker)
    }
}
