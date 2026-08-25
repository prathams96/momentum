import Foundation
import MomentumCore
import SwiftData
import UserNotifications

extension WorkoutModuleAdapter: NotificationCategoryProviding {
    func notificationCategory() -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: MomentumNotificationCategory.workoutDue,
            actions: [
                UNNotificationAction(
                    identifier: MomentumNotificationAction.startWorkout,
                    title: "Start workout",
                    options: [.foreground]
                ),
                UNNotificationAction(
                    identifier: MomentumNotificationAction.remindInThirtyMinutes,
                    title: "Remind in 30 minutes"
                ),
                UNNotificationAction(
                    identifier: MomentumNotificationAction.skipToday,
                    title: "Skip today"
                ),
            ],
            intentIdentifiers: []
        )
    }
}
