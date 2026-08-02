import SwiftUI
import SwiftData
import UIKit
import UserNotifications

struct AppShell: View {
    @State private var selectedTab: AppTab = .today
    @State private var notificationDelegate = MomentumNotificationDelegate()
    @State private var pendingWorkoutRoute: WorkoutNotificationRoute?
    @Query private var settings: [AppSettingsRecord]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if AppSettingsRecord.canonical(in: settings)?.onboardingCompleted == true {
            tabView
                .preferredColorScheme(preferredColorScheme)
                .onAppear {
                    notificationDelegate.modelContext = modelContext
                    notificationDelegate.onOpenToday = { selectedTab = .today }
                    notificationDelegate.onStartWorkout = { route in
                        selectedTab = .today
                        pendingWorkoutRoute = route
                    }
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
                TodayView(notificationWorkoutRoute: $pendingWorkoutRoute)
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

    private var preferredColorScheme: ColorScheme? {
        switch AppSettingsRecord.canonical(in: settings)?.selectedAppearanceRaw {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    private func reconcile() {
        Task {
            try? await DailyReconciler.reconcileAndNotify(in: modelContext)
        }
    }
}
