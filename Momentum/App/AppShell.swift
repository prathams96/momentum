import SwiftUI
import SwiftData
import UIKit
import UserNotifications

struct AppShell: View {
    @State private var selectedTab: AppTab = .today
    @State private var notificationDelegate = MomentumNotificationDelegate()
    @Query private var settings: [AppSettingsRecord]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if settings.max(by: { $0.updatedAt < $1.updatedAt })?.onboardingCompleted == true {
            tabView
                .onAppear {
                    notificationDelegate.modelContext = modelContext
                    notificationDelegate.onOpenToday = { selectedTab = .today }
                    UNUserNotificationCenter.current().delegate = notificationDelegate
                    Task { await NotificationScheduler().configureCategories() }
                    reconcile()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { reconcile() }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    reconcile()
                }
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
                HistoryView()
            }
            .tabItem {
                Label(AppTab.history.title, systemImage: AppTab.history.symbol)
            }
            .tag(AppTab.history)

            NavigationStack {
                PlansView()
            }
            .tabItem {
                Label(AppTab.plans.title, systemImage: AppTab.plans.symbol)
            }
            .tag(AppTab.plans)

            NavigationStack {
                ProgressTabView()
            }
            .tabItem {
                Label(AppTab.progress.title, systemImage: AppTab.progress.symbol)
            }
            .tag(AppTab.progress)
        }
        .tint(MomentumTheme.pulse)
    }

    private func reconcile() {
        Task {
            try? await DailyReconciler.reconcileAndNotify(in: modelContext)
        }
    }
}
