import Foundation
import MomentumCore
import SwiftData

@MainActor
enum DailyReconciler {
    static func reconcile(in context: ModelContext, now: Date = .now) throws {
        let settings = try context.fetch(FetchDescriptor<AppSettingsRecord>())
            .max { $0.updatedAt < $1.updatedAt }
        let cutoff = settings?.domainDayCutoffMinutes ?? 180
        let calendar = Calendar.autoupdatingCurrent
        let today = DomainDay.containing(now, calendar: calendar, cutoffMinutes: cutoff)
        let yesterday = today.adding(days: -1, calendar: calendar)
        let todayValue = PersistedDomainDay.encode(today)
        let yesterdayValue = PersistedDomainDay.encode(yesterday)

        let routines = try context.fetch(FetchDescriptor<CareRoutineTemplateRecord>())
            .filter { !$0.isArchived }
        var occurrences = try context.fetch(FetchDescriptor<CareOccurrenceRecord>())

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

        try context.save()
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
