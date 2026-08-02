import Foundation
import SwiftData
import UIKit
import UserNotifications

@MainActor
final class MomentumNotificationDelegate: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    var modelContext: ModelContext?
    var onOpenToday: (() -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor [weak self] in
            await self?.handle(response)
            completionHandler()
        }
    }

    private func handle(_ response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let request = response.notification.request
        let info = request.content.userInfo.reduce(into: [String: String]()) { result, item in
            if let value = item.value as? String { result[String(describing: item.key)] = value }
        }

        if action == MomentumNotificationAction.openToday || action == MomentumNotificationAction.startWorkout {
            onOpenToday?()
        }

        if action == MomentumNotificationAction.remindInThirtyMinutes {
            try? await NotificationScheduler().scheduleFollowUp(
                identifier: request.identifier,
                title: request.content.title,
                body: request.content.body,
                categoryIdentifier: request.content.categoryIdentifier,
                userInfo: info
            )
            return
        }

        guard let modelContext else { return }
        switch action {
        case MomentumNotificationAction.markCareDone:
            guard let id = info["occurrenceID"], let occurrenceID = UUID(uuidString: id),
                  let occurrence = (try? modelContext.fetch(FetchDescriptor<CareOccurrenceRecord>()))?.first(where: { $0.id == occurrenceID }),
                  occurrence.statusRaw == "pending" else { return }
            occurrence.statusRaw = "completed"
            occurrence.completedAt = Date.now
            occurrence.updatedAt = Date.now
            let completions = ((try? modelContext.fetch(FetchDescriptor<CareTaskCompletionRecord>())) ?? [])
                .filter { $0.occurrenceID == occurrenceID }
            for completion in completions {
                completion.statusRaw = "completed"
                completion.completedAt = Date.now
                completion.updatedAt = Date.now
            }
        case MomentumNotificationAction.skipToday:
            if info["kind"] == "careDue",
               let id = info["occurrenceID"], let occurrenceID = UUID(uuidString: id),
               let occurrence = (try? modelContext.fetch(FetchDescriptor<CareOccurrenceRecord>()))?.first(where: { $0.id == occurrenceID }),
               occurrence.statusRaw == "pending" {
                occurrence.statusRaw = "skipped"
                occurrence.skippedAt = Date.now
                occurrence.updatedAt = Date.now
            } else if info["kind"] == "workoutDue",
                      let workout = info["workoutID"], let workoutID = UUID(uuidString: workout),
                      let day = info["domainDay"] {
                let existing = ((try? modelContext.fetch(FetchDescriptor<WorkoutDayEventRecord>())) ?? [])
                    .contains { $0.domainDay == day && $0.dueWorkoutTemplateID == workoutID && $0.deletedAt == nil }
                guard !existing else { return }
                modelContext.insert(WorkoutDayEventRecord(domainDay: day, dueWorkoutTemplateID: workoutID, kindRaw: "skipped"))
            }
        default:
            break
        }

        try? modelContext.save()
        try? await DailyReconciler.reconcileAndNotify(in: modelContext)
    }
}
