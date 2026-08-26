import Foundation
import MomentumCore
import SwiftData
import UserNotifications

extension HydrationModuleAdapter: NotificationCategoryProviding {
    func notificationCategory() -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: MomentumNotificationCategory.hydrationCheckIn,
            actions: [
                UNNotificationAction(
                    identifier: MomentumNotificationAction.openToday,
                    title: "Open Momentum",
                    options: [.foreground]
                ),
                NotificationScheduler.remindInThirtyMinutesAction(),
            ],
            intentIdentifiers: []
        )
    }
}
