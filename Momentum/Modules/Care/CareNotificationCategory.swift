import Foundation
import MomentumCore
import SwiftData
import UserNotifications

extension CareModuleAdapter: NotificationCategoryProviding {
    func notificationCategory() -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: MomentumNotificationCategory.careDue,
            actions: [
                UNNotificationAction(
                    identifier: MomentumNotificationAction.markCareDone,
                    title: "Done"
                ),
                NotificationScheduler.remindInThirtyMinutesAction(),
                UNNotificationAction(
                    identifier: MomentumNotificationAction.skipToday,
                    title: "Skip today"
                ),
            ],
            intentIdentifiers: []
        )
    }
}
