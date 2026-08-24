import Foundation
import MomentumCore
import SwiftData

extension CareModuleAdapter: ReminderCandidateProviding {
    func reminderCandidates(in context: ModuleContext) -> [ScheduledReminder] {
        let occurrences = (try? context.modelContext.fetch(FetchDescriptor<CareOccurrenceRecord>())) ?? []
        let currentDay = PersistedDomainDay.encode(context.currentDomainDay)
        let dueCare = occurrences
            .filter { $0.dueDomainDay == currentDay && $0.statusRaw == "pending" }
            .sorted { ($0.dueAt, $0.id.uuidString) < ($1.dueAt, $1.id.uuidString) }
        return dueCare
            .filter { $0.dueAt > context.now }
            .map { occurrence in
                ScheduledReminder(
                    identifier: "care.due.\(occurrence.id.uuidString)",
                    title: occurrence.routineNameSnapshot,
                    body: "Your care routine is ready.",
                    categoryIdentifier: MomentumNotificationCategory.careDue,
                    dateComponents: context.calendar.dateComponents(
                        [.year, .month, .day, .hour, .minute],
                        from: occurrence.dueAt
                    ),
                    userInfo: [
                        "kind": "careDue",
                        "actionKind": "careDue",
                        "occurrenceID": occurrence.id.uuidString,
                        "domainDay": occurrence.dueDomainDay
                    ]
                )
            }
    }
}
