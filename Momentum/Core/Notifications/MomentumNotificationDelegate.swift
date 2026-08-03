import Foundation
import MomentumCore
import SwiftData
import UIKit
import UserNotifications

struct WorkoutNotificationRoute: Equatable, Sendable {
    let workoutID: UUID
    let domainDay: DomainDay

    init?(userInfo: [String: String]) {
        guard let workoutValue = userInfo["workoutID"],
              let workoutID = UUID(uuidString: workoutValue),
              let dayValue = userInfo["domainDay"],
              let domainDay = PersistedDomainDay.decode(dayValue) else {
            return nil
        }
        self.workoutID = workoutID
        self.domainDay = domainDay
    }
}

@MainActor
final class MomentumNotificationDelegate: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    var modelContext: ModelContext?
    var onOpenToday: (() -> Void)?
    /// AppShell supplies this to turn a notification action into the actual target workout flow.
    var onStartWorkout: ((WorkoutNotificationRoute) -> Void)?

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

        if action == MomentumNotificationAction.startWorkout {
            if let route = WorkoutNotificationRoute(userInfo: info), let onStartWorkout {
                onStartWorkout(route)
            } else {
                onOpenToday?()
            }
            return
        }

        if action == MomentumNotificationAction.openToday || action == UNNotificationDefaultActionIdentifier {
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
                  (try? DailyReconciler.completeCareOccurrence(
                    occurrenceID: occurrenceID,
                    in: modelContext
                  )) == true else { return }
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
