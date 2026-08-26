import Foundation
import UserNotifications

enum MomentumNotificationCategory {
    static let workoutDue = "WORKOUT_DUE"
    static let careDue = "CARE_DUE"
    static let eveningCheckIn = "EVENING_CHECKIN"
    static let hydrationCheckIn = "HYDRATION_REMINDER"
}

enum MomentumNotificationAction {
    static let startWorkout = "START_WORKOUT"
    static let markCareDone = "MARK_CARE_DONE"
    static let openToday = "OPEN_TODAY"
    static let remindInThirtyMinutes = "REMIND_30_MINUTES"
    static let skipToday = "SKIP_TODAY"
}

struct ScheduledReminder: Hashable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let categoryIdentifier: String
    let dateComponents: DateComponents
    let repeats: Bool
    let userInfo: [String: String]

    init(
        identifier: String,
        title: String,
        body: String,
        categoryIdentifier: String,
        dateComponents: DateComponents,
        repeats: Bool = false,
        userInfo: [String: String] = [:]
    ) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.categoryIdentifier = categoryIdentifier
        self.dateComponents = dateComponents
        self.repeats = repeats
        self.userInfo = userInfo
    }
}

actor NotificationScheduler {
    private static let identifierPrefix = "momentum."
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    /// Registers the Core-owned evening check-in category plus every module-
    /// contributed category. Modules declare their own categories through
    /// `NotificationCategoryProviding`; adding a module never edits this file.
    static func coreCategories() -> [UNNotificationCategory] {
        [
            UNNotificationCategory(
                identifier: MomentumNotificationCategory.eveningCheckIn,
                actions: [
                    UNNotificationAction(
                        identifier: MomentumNotificationAction.openToday,
                        title: "Open Today",
                        options: [.foreground]
                    ),
                    UNNotificationAction(
                        identifier: MomentumNotificationAction.remindInThirtyMinutes,
                        title: "Remind in 30 minutes"
                    ),
                ],
                intentIdentifiers: []
            )
        ]
    }

    @MainActor
    static func registeredCategories(registry: ModuleRegistry = .standard) -> [UNNotificationCategory] {
        let moduleCategories = registry.modules
            .compactMap { $0 as? any NotificationCategoryProviding }
            .map { $0.notificationCategory() }
        return coreCategories() + moduleCategories
    }

    /// Registers the Core-owned evening check-in category plus every module-
    /// contributed category. Modules declare their own categories through
    /// `NotificationCategoryProviding`; adding a module never edits this file.
    /// MainActor-bound because category construction touches the registry and
    /// keeps non-Sendable values off other executors.
    @MainActor
    static func registerCategories(
        center: UNUserNotificationCenter = .current(),
        registry: ModuleRegistry = .standard
    ) {
        let moduleCategories = registry.modules
            .compactMap { $0 as? any NotificationCategoryProviding }
            .map { $0.notificationCategory() }
        center.setNotificationCategories(Set(coreCategories() + moduleCategories))
    }

    static func remindInThirtyMinutesAction() -> UNNotificationAction {
        UNNotificationAction(
            identifier: MomentumNotificationAction.remindInThirtyMinutes,
            title: "Remind in 30 minutes"
        )
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func reconcile(_ reminders: [ScheduledReminder]) async throws {
        let normalized = reminders.map { reminder in
            ScheduledReminder(
                identifier: Self.identifierPrefix + reminder.identifier,
                title: reminder.title,
                body: reminder.body,
                categoryIdentifier: reminder.categoryIdentifier,
                dateComponents: reminder.dateComponents,
                repeats: reminder.repeats,
                userInfo: reminder.userInfo
            )
        }
        let desiredIdentifiers = Set(normalized.map(\.identifier))
        let pending = await center.pendingNotificationRequests()
        let obsoleteIdentifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) && !desiredIdentifiers.contains($0) }

        if !obsoleteIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: obsoleteIdentifiers)
        }

        for reminder in normalized {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.categoryIdentifier = reminder.categoryIdentifier
            content.userInfo = reminder.userInfo

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: reminder.dateComponents,
                repeats: reminder.repeats
            )
            let request = UNNotificationRequest(
                identifier: reminder.identifier,
                content: content,
                trigger: trigger
            )
            try await center.add(request)
        }
    }

    func scheduleFollowUp(
        identifier: String,
        title: String,
        body: String,
        categoryIdentifier: String,
        userInfo: [String: String]
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = userInfo
        let request = UNNotificationRequest(
            identifier: Self.identifierPrefix + "followup." + identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 30 * 60, repeats: false)
        )
        try await center.add(request)
    }

    func cancelAllMomentumReminders() async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
