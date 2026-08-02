import Foundation
import MomentumCore
import SwiftData

@MainActor
enum DailyReconciler {
    static func reconcile(
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) throws {
        let settings = AppSettingsRecord.canonical(
            in: try context.fetch(FetchDescriptor<AppSettingsRecord>())
        )
        let cutoff = settings?.domainDayCutoffMinutes ?? 180
        let today = DomainDay.containing(now, calendar: calendar, cutoffMinutes: cutoff)
        let yesterday = today.adding(days: -1, calendar: calendar)
        let todayValue = PersistedDomainDay.encode(today)
        let yesterdayValue = PersistedDomainDay.encode(yesterday)

        let routines = try context.fetch(FetchDescriptor<CareRoutineTemplateRecord>())
            .filter { !$0.isArchived }
        var occurrences = try context.fetch(FetchDescriptor<CareOccurrenceRecord>())
        repairDuplicateOccurrences(occurrences, now: now)

        for occurrence in occurrences where occurrence.dueDomainDay == yesterdayValue && occurrence.statusRaw == "pending" {
            guard let routineID = occurrence.routineTemplateID,
                  let routine = routines.first(where: { $0.id == routineID }) else {
                occurrence.statusRaw = "missed"
                occurrence.updatedAt = now
                continue
            }

            occurrence.statusRaw = "missed"
            occurrence.updatedAt = now
            if routine.rollsForwardWhenMissed,
               !occurrences.contains(where: { $0.routineTemplateID == routine.id && $0.dueDomainDay == todayValue }) {
                let rolled = makeOccurrence(
                    for: routine,
                    domainDay: today,
                    domainDayValue: todayValue,
                    calendar: calendar,
                    rolledFrom: yesterdayValue
                )
                context.insert(rolled)
                try insertTaskSnapshots(for: routine, occurrenceID: rolled.id, context: context)
                occurrences.append(rolled)
            }
        }

        for routine in routines where isDue(routine, on: today, calendar: calendar, occurrences: occurrences) {
            guard !occurrences.contains(where: {
                $0.routineTemplateID == routine.id && $0.dueDomainDay == todayValue
            }) else { continue }

            let occurrence = makeOccurrence(
                for: routine,
                domainDay: today,
                domainDayValue: todayValue,
                calendar: calendar,
                rolledFrom: nil
            )
            context.insert(occurrence)
            try insertTaskSnapshots(for: routine, occurrenceID: occurrence.id, context: context)
            occurrences.append(occurrence)
        }

        let workouts = try context.fetch(FetchDescriptor<WorkoutTemplateRecord>())
        let anchors = try context.fetch(FetchDescriptor<CycleAnchorRecord>())
        let sessions = try context.fetch(FetchDescriptor<WorkoutSessionRecord>())
        reconcileWorkoutEvents(
            state: ScheduleProjection.evaluate(
                workouts: workouts,
                anchors: anchors,
                sessions: sessions,
                settings: settings.map { [$0] } ?? [],
                now: now,
                calendar: calendar
            ),
            currentDay: today,
            sessions: sessions,
            events: try context.fetch(FetchDescriptor<WorkoutDayEventRecord>()),
            context: context,
            now: now,
            calendar: calendar
        )

        try context.save()
    }

    static func reconcileAndNotify(
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) async throws {
        try reconcile(in: context, now: now, calendar: calendar)

        let settings = AppSettingsRecord.canonical(
            in: try context.fetch(FetchDescriptor<AppSettingsRecord>())
        )
        let occurrences = try context.fetch(FetchDescriptor<CareOccurrenceRecord>())
        let nutritionDays = try context.fetch(FetchDescriptor<NutritionDayRecord>())
        let workouts = try context.fetch(FetchDescriptor<WorkoutTemplateRecord>())
        let anchors = try context.fetch(FetchDescriptor<CycleAnchorRecord>())
        let sessions = try context.fetch(FetchDescriptor<WorkoutSessionRecord>())
        let state = ScheduleProjection.evaluate(
            workouts: workouts,
            anchors: anchors,
            sessions: sessions,
            settings: settings.map { [$0] } ?? [],
            now: now,
            calendar: calendar
        )
        let currentDay = DomainDay.containing(
            now,
            calendar: calendar,
            cutoffMinutes: settings?.domainDayCutoffMinutes ?? 180
        )
        let reminders = ReminderDeriver.reminders(
            scheduleState: state,
            settings: settings,
            occurrences: occurrences,
            nutritionDay: nutritionDays.first { $0.domainDay == PersistedDomainDay.encode(currentDay) },
            now: now,
            calendar: calendar
        )
        do {
            try await NotificationScheduler().reconcile(reminders)
            settings?.notificationSchedulingStatusRaw = "healthy"
            try context.save()
        } catch {
            settings?.notificationSchedulingStatusRaw = "failed"
            try? context.save()
            throw error
        }
    }

    /// Completes a Care Routine through the same mutation boundary used by notification actions.
    /// Returns `false` when the action was already applied or the occurrence no longer exists.
    @discardableResult
    static func completeCareOccurrence(
        occurrenceID: UUID,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
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

    private static func repairDuplicateOccurrences(
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

    private static func reconcileWorkoutEvents(
        state: WorkoutScheduleState,
        currentDay: DomainDay,
        sessions: [WorkoutSessionRecord],
        events: [WorkoutDayEventRecord],
        context: ModelContext,
        now: Date,
        calendar: Calendar
    ) {
        let opportunity: (workoutID: UUID, dueDay: DomainDay)?
        switch state {
        case let .due(workoutID, dueDay, _):
            opportunity = (workoutID, dueDay)
        case let .active(sessionID):
            let activeSession = sessions.first(where: {
                $0.id == sessionID && $0.deletedAt == nil && $0.finishedAt == nil
            })
            if let activeSession,
               let workoutID = activeSession.workoutTemplateID,
               let scheduledDay = PersistedDomainDay.decode(activeSession.scheduledDomainDay) {
                opportunity = (workoutID, scheduledDay)
            } else {
                opportunity = nil
            }
        case .recovery, .needsRepair:
            opportunity = nil
        }
        guard let opportunity, opportunity.dueDay < currentDay else { return }
        let workoutID = opportunity.workoutID
        let dueDay = opportunity.dueDay
        var elapsedOpportunity = dueDay
        while elapsedOpportunity < currentDay {
            let dayValue = PersistedDomainDay.encode(elapsedOpportunity)
            let alreadyRecorded = events.contains {
                $0.deletedAt == nil &&
                $0.domainDay == dayValue &&
                $0.dueWorkoutTemplateID == workoutID &&
                ($0.kindRaw == "missed" || $0.kindRaw == "skipped")
            }
            let completedForOpportunity = sessions.contains {
                $0.deletedAt == nil &&
                $0.finishedAt != nil &&
                ($0.completionDomainDay == dayValue || $0.scheduledDomainDay == dayValue)
            }
            if !alreadyRecorded, !completedForOpportunity {
                context.insert(WorkoutDayEventRecord(
                    domainDay: dayValue,
                    dueWorkoutTemplateID: workoutID,
                    kindRaw: "missed",
                    createdAt: now,
                    updatedAt: now
                ))
            }
            elapsedOpportunity = elapsedOpportunity.adding(days: 1, calendar: calendar)
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
