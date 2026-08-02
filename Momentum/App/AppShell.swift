import SwiftUI
import SwiftData

struct AppShell: View {
    @State private var selectedTab: AppTab = .today
    @Query private var settings: [AppSettingsRecord]

    var body: some View {
        if settings.first?.onboardingCompleted == true {
            tabView
        } else {
            OnboardingView()
        }
    }

    private var tabView: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayPlaceholderView()
            }
            .tabItem {
                Label(AppTab.today.title, systemImage: AppTab.today.symbol)
            }
            .tag(AppTab.today)

            NavigationStack {
                PlaceholderTabView(title: AppTab.history.title, symbol: AppTab.history.symbol)
            }
            .tabItem {
                Label(AppTab.history.title, systemImage: AppTab.history.symbol)
            }
            .tag(AppTab.history)

            NavigationStack {
                PlaceholderTabView(title: AppTab.plans.title, symbol: AppTab.plans.symbol)
            }
            .tabItem {
                Label(AppTab.plans.title, systemImage: AppTab.plans.symbol)
            }
            .tag(AppTab.plans)

            NavigationStack {
                PlaceholderTabView(title: AppTab.progress.title, symbol: AppTab.progress.symbol)
            }
            .tabItem {
                Label(AppTab.progress.title, systemImage: AppTab.progress.symbol)
            }
            .tag(AppTab.progress)
        }
        .tint(MomentumTheme.pulse)
    }
}

private struct TodayPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Today is taking shape",
            systemImage: "checklist",
            description: Text("Your next workout, nutrition, and care routines will appear here.")
        )
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape") {}
                    .accessibilityLabel("Settings")
            }
        }
    }
}

private struct PlaceholderTabView: View {
    let title: String
    let symbol: String

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: symbol,
            description: Text("This area will be added in the next implementation stages.")
        )
        .navigationTitle(title)
    }
}
