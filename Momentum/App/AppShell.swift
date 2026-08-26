import CloudKit
import SwiftUI
import SwiftData
import UIKit
import UserNotifications

struct AppShell: View {
    @State private var selectedTab: AppTab = .today
    @State private var notificationDelegate = MomentumNotificationDelegate()
    @State private var pendingWorkoutRoute: WorkoutNotificationRoute?
    @State private var pendingTimeZoneChange: MaterialTimeZoneChange?
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
                    NotificationScheduler.registerCategories()
                    refreshCloudAccountState()
                    evaluateTimeZoneAndReconcile()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    refreshCloudAccountState()
                    evaluateTimeZoneAndReconcile()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    evaluateTimeZoneAndReconcile()
                }
                .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
                    refreshCloudAccountState()
                }
                .alert(
                    "Time zone changed",
                    isPresented: timeZoneAlertIsPresented,
                    presenting: pendingTimeZoneChange
                ) { change in
                    Button("Use New Time Zone") {
                        MaterialTimeZoneChangeStore.accept(change)
                        pendingTimeZoneChange = nil
                        reconcile()
                    }
                    Button("Later", role: .cancel) {
                        pendingTimeZoneChange = nil
                    }
                } message: { change in
                    Text(timeZoneChangeMessage(change))
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

    private func refreshCloudAccountState() {
        Task {
            try? await CloudAccountStateService.refresh(in: modelContext)
        }
    }

    private func evaluateTimeZoneAndReconcile() {
        if let change = MaterialTimeZoneChangeStore.evaluate() {
            pendingTimeZoneChange = change
        } else {
            pendingTimeZoneChange = nil
            reconcile()
        }
    }

    private var timeZoneAlertIsPresented: Binding<Bool> {
        Binding(
            get: { pendingTimeZoneChange != nil },
            set: { isPresented in
                if !isPresented { pendingTimeZoneChange = nil }
            }
        )
    }

    private func timeZoneChangeMessage(_ change: MaterialTimeZoneChange) -> String {
        let previous = timeZoneName(change.previousIdentifier)
        let current = timeZoneName(change.currentIdentifier)
        return "Momentum detected a move from \(previous) to \(current). Original timestamps stay unchanged. Use the new time zone to resume day, streak, schedule, and reminder reconciliation. Choose Later to keep logging while reconciliation remains deferred."
    }

    private func timeZoneName(_ identifier: String) -> String {
        TimeZone(identifier: identifier)?.localizedName(for: .generic, locale: .current) ?? identifier
    }
}
