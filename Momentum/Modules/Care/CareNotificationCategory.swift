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
