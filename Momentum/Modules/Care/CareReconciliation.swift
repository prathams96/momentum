import Foundation
import MomentumCore
import SwiftData

/// Care-side day-rollover engine moved out of the monolithic reconciler.
/// Every mutation here is idempotent and never saves; the orchestrator owns
/// the single save at the end of reconciliation.
@MainActor
enum CareReconciliationEngine {
    /// Duplicate-occurrence repair, yesterday-pending → missed marking with
    /// roll-forward-once, and today-due occurrence materialization.
    static func reconcile(
        previousDay: DomainDay,
        currentDay: DomainDay,
        in context: ModuleContext
    ) throws {
        let modelContext = context.modelContext
        let now = context.now
        let calendar = context.calendar

        let routines = try modelContext.fetch(FetchDescriptor<CareRoutineTemplateRecord>())
            .filter { !$0.isArchived }
        var occurrences = try modelContext.fetch(FetchDescriptor<CareOccurrenceRecord>())
        repairDuplicateOccurrences(occurrences, now: now)

        for occurrence in occurrences where occurrence.dueDomainDay == PersistedDomainDay.encode(previousDay) && occurrence.statusRaw == "pending" {
            guard let routineID = occurrence.routineTemplateID,
                  let routine = routines.first(where: { $0.id == routineID }) else {
                occurrence.statusRaw = "missed"
                occurrence.updatedAt = now
                continue
            }

            occurrence.statusRaw = "missed"
            occurrence.updatedAt = now
            if routine.rollsForwardWhenMissed,
               !occurrences.contains(where: { $0.routineTemplateID == routine.id && $0.dueDomainDay == PersistedDomainDay.encode(currentDay) }) {
                let rolled = makeOccurrence(
                    for: routine,
                    domainDay: currentDay,
                    domainDayValue: PersistedDomainDay.encode(currentDay),
                    calendar: calendar,
                    rolledFrom: PersistedDomainDay.encode(previousDay)
                )
                modelContext.insert(rolled)
                try insertTaskSnapshots(for: routine, occurrenceID: rolled.id, context: modelContext)
                occurrences.append(rolled)
            }
        }

        for routine in routines where isDue(routine, on: currentDay, calendar: calendar, occurrences: occurrences) {
            guard !occurrences.contains(where: {
                $0.routineTemplateID == routine.id && $0.dueDomainDay == PersistedDomainDay.encode(currentDay)
            }) else { continue }

            let occurrence = makeOccurrence(
                for: routine,
                domainDay: currentDay,
                domainDayValue: PersistedDomainDay.encode(currentDay),
                calendar: calendar,
                rolledFrom: nil
            )
            modelContext.insert(occurrence)
            try insertTaskSnapshots(for: routine, occurrenceID: occurrence.id, context: modelContext)
            occurrences.append(occurrence)
        }
    }

    /// The mutation boundary used by notification actions. Saves once.
    static func completeOccurrence(
        occurrenceID: UUID,
        in context: ModelContext,
        now: Date,
        calendar: Calendar
    ) throws -> Bool {
        guard let occurrence = try context.fetch(FetchDescriptor<CareOccurrenceRecord>())
            .first(where: { $0.id == occurrenceID }),
              occurrence.statusRaw == "pending" else {
            return false
        }

        occurrence.statusRaw = "completed"
        occurrence.completedAt = now
        occurrence.skippedAt = nil
        occurrence.updatedAt = now

        let completions = try context.fetch(FetchDescriptor<CareTaskCompletionRecord>())
            .filter { $0.occurrenceID == occurrenceID }
        for completion in completions {
            completion.statusRaw = "completed"
            completion.completedAt = now
            completion.updatedAt = now
        }

        try advanceAlternatingRecurrenceIfNeeded(
            for: occurrence,
            in: context,
            now: now,
            calendar: calendar
        )
        try context.save()
        return true
    }

    static func repairDuplicateOccurrences(
        _ occurrences: [CareOccurrenceRecord],
        now: Date
    ) {
        let grouped = Dictionary(grouping: occurrences) { occurrence in
            [
                occurrence.routineTemplateID?.uuidString ?? "none",
                occurrence.routineRoleRaw,
                occurrence.sourceWorkoutSessionID?.uuidString ?? "none",
                occurrence.dueDomainDay
            ].joined(separator: "|")
        }
        for group in grouped.values where group.count > 1 {
            let ordered = group.sorted(by: survivorOrder)
            for duplicate in ordered.dropFirst() {
                duplicate.statusRaw = "repairedDuplicate"
                duplicate.updatedAt = now
            }
        }
    }

    /// Preserve the strongest recorded intent, then resolve ties without relying on fetch order.
    private static func survivorOrder(
        _ lhs: CareOccurrenceRecord,
        _ rhs: CareOccurrenceRecord
    ) -> Bool {
        let lhsRank = occurrenceStatusRank(lhs.statusRaw)
        let rhsRank = occurrenceStatusRank(rhs.statusRaw)
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func occurrenceStatusRank(_ status: String) -> Int {
        switch status {
        case "completed": 0
        case "skipped": 1
        case "missed": 2
        case "pending": 3
        default: 4
        }
    }

    private static func advanceAlternatingRecurrenceIfNeeded(
        for occurrence: CareOccurrenceRecord,
        in context: ModelContext,
        now: Date,
        calendar: Calendar
    ) throws {
        guard let routineID = occurrence.routineTemplateID,
              let routine = try context.fetch(FetchDescriptor<CareRoutineTemplateRecord>())
                .first(where: { $0.id == routineID }),
              routine.recurrenceKindRaw == "alternatingInterval",
              let data = routine.recurrencePayload.data(using: .utf8),
              let payload = try? JSONDecoder().decode(CareRecurrencePayload.self, from: data) else {
            return
        }
        let settings = try context.fetch(FetchDescriptor<AppSettingsRecord>())
            .max { $0.updatedAt < $1.updatedAt }
        let completionDay = DomainDay.containing(
            now,
            calendar: calendar,
            cutoffMinutes: settings?.domainDayCutoffMinutes ?? 180
        )
        guard let advanced = CareScheduleEngine().advancedAlternatingPayload(
            afterCompletionOn: completionDay,
            payload: payload,
            calendar: calendar
        ),
        let encoded = try? JSONEncoder().encode(advanced),
        let value = String(data: encoded, encoding: .utf8) else {
            return
        }

        occurrence.recurrencePayloadBeforeCompletion = routine.recurrencePayload
        routine.recurrencePayload = value
        routine.updatedAt = now
    }

    private static func isDue(
        _ routine: CareRoutineTemplateRecord,
        on day: DomainDay,
        calendar: Calendar,
        occurrences: [CareOccurrenceRecord]
    ) -> Bool {
        if let data = routine.recurrencePayload.data(using: .utf8),
           let payload = try? JSONDecoder().decode(CareRecurrencePayload.self, from: data) {
            switch CareScheduleEngine().evaluate(payload, on: day, calendar: calendar) {
            case .due: return true
            case .notDue, .needsRepair: return false
            }
        }

        if routine.recurrenceKindRaw == "weekdaySet" {
            guard let date = PersistedDomainDay.date(for: day, calendar: calendar) else { return false }
            let zeroBasedWeekday = (calendar.component(.weekday, from: date) + 6) % 7
            let weekdays = routine.recurrencePayload
                .replacingOccurrences(of: "weekdays:", with: "")
                .split(separator: ",")
                .compactMap { Int($0) }
            return weekdays.contains(zeroBasedWeekday)
        }

        guard routine.recurrenceKindRaw == "alternatingInterval" else { return false }
        let completed = occurrences
            .filter { $0.routineTemplateID == routine.id && $0.statusRaw == "completed" }
            .sorted { $0.dueAt < $1.dueAt }
        guard let latest = completed.last,
              let latestDay = PersistedDomainDay.decode(latest.dueDomainDay) else {
            guard let date = PersistedDomainDay.date(for: day, calendar: calendar) else { return false }
            let weekday = (calendar.component(.weekday, from: date) + 6) % 7
            return weekday == 3 || weekday == 6
        }

        let completionWeekday = PersistedDomainDay.date(for: latestDay, calendar: calendar)
            .map { (calendar.component(.weekday, from: $0) + 6) % 7 }
        let nextInterval = completionWeekday == 3 ? 3 : 4
        return latestDay.adding(days: nextInterval, calendar: calendar) == day
    }

    private static func makeOccurrence(
        for routine: CareRoutineTemplateRecord,
        domainDay: DomainDay,
        domainDayValue: String,
        calendar: Calendar,
        rolledFrom: String?
    ) -> CareOccurrenceRecord {
        let hour = routine.notificationMinutes / 60
        let minute = routine.notificationMinutes % 60
        let dueAt = PersistedDomainDay.date(
            for: domainDay,
            calendar: calendar,
            hour: hour,
            minute: minute
        ) ?? .now
        return CareOccurrenceRecord(
            routineTemplateID: routine.id,
            routineNameSnapshot: routine.name,
            routineRoleRaw: routine.routineRoleRaw,
            dueDomainDay: domainDayValue,
            dueAt: dueAt,
            rolledFromDomainDay: rolledFrom
        )
    }

    private static func insertTaskSnapshots(
        for routine: CareRoutineTemplateRecord,
        occurrenceID: UUID,
        context: ModelContext
    ) throws {
        let tasks = try context.fetch(FetchDescriptor<CareTaskTemplateRecord>())
            .filter { $0.routineTemplateID == routine.id && !$0.isArchived }
        for task in tasks {
            context.insert(CareTaskCompletionRecord(
                occurrenceID: occurrenceID,
                taskTemplateID: task.id,
                labelSnapshot: task.label,
                instructionSnapshot: task.instruction
            ))
        }
    }
}

extension CareModuleAdapter: ReconcilingModule {
    func reconcile(previousDay: DomainDay, currentDay: DomainDay, in context: ModuleContext) throws {
        try CareReconciliationEngine.reconcile(
            previousDay: previousDay,
            currentDay: currentDay,
            in: context
        )
    }
}
