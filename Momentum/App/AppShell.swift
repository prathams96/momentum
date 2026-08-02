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
                TodayView()
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

private struct PlaceholderTabView: View {
    let title: String
    let symbol: String

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: symbol,
            description: Text(description)
        )
        .navigationTitle(title)
    }

    private var description: String {
        switch title {
        case "History": "Completed days and the context around them will gather here."
        case "Plans": "Tune your workout cycle, nutrition targets, and care routines here."
        default: "Measurements, trends, and adherence will appear as you log your days."
        }
    }
}
