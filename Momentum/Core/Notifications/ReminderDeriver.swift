import Foundation
import MomentumCore

@MainActor
enum ReminderDeriver {
    static func reminders(
        scheduleState: WorkoutScheduleState,
        settings: AppSettingsRecord?,
        occurrences: [CareOccurrenceRecord],
        nutritionDay: NutritionDayRecord?,
        now: Date,
        calendar: Calendar
    ) -> [ScheduledReminder] {
        let currentDay = DomainDay.containing(
            now,
            calendar: calendar,
            cutoffMinutes: settings?.domainDayCutoffMinutes ?? 180
        )
        var reminders: [ScheduledReminder] = []

        if case let .due(workoutID, dueDay, _) = scheduleState,
           let settings,
           let date = reminderDate(
               for: currentDay,
               minutes: settings.workoutNotificationMinutes,
               now: now,
               calendar: calendar
           ) {
            reminders.append(ScheduledReminder(
                identifier: "workout.\(workoutID.uuidString).\(PersistedDomainDay.encode(dueDay))",
                title: "Workout due",
                body: "Your next workout is ready when you are.",
                categoryIdentifier: MomentumNotificationCategory.workoutDue,
                dateComponents: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date),
                userInfo: [
                    "kind": "workoutDue",
                    "workoutID": workoutID.uuidString,
                    "domainDay": PersistedDomainDay.encode(dueDay)
                ]
            ))
        }

        let dueCare = occurrences
            .filter { $0.dueDomainDay == PersistedDomainDay.encode(currentDay) && $0.statusRaw == "pending" }
            .sorted { ($0.dueAt, $0.id.uuidString) < ($1.dueAt, $1.id.uuidString) }
        for occurrence in dueCare where occurrence.dueAt > now {
            reminders.append(ScheduledReminder(
                identifier: "care.\(occurrence.id.uuidString)",
                title: occurrence.routineNameSnapshot,
                body: "Your care routine is ready.",
                categoryIdentifier: MomentumNotificationCategory.careDue,
                dateComponents: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: occurrence.dueAt),
                userInfo: [
                    "kind": "careDue",
                    "occurrenceID": occurrence.id.uuidString,
                    "domainDay": occurrence.dueDomainDay
                ]
            ))
        }

        let nutritionOpen = nutritionDay?.finalizedAt == nil
        let nightCareDue = dueCare.contains { $0.routineNameSnapshot.hasPrefix("Night care") }
        if nutritionOpen || nightCareDue {
            let minutes = settings?.nutritionReminderMinutes ?? 22 * 60
            if let date = reminderDate(for: currentDay, minutes: minutes, now: now, calendar: calendar) {
                reminders.append(ScheduledReminder(
                    identifier: "evening.\(PersistedDomainDay.encode(currentDay))",
                    title: "Evening check-in",
                    body: nutritionOpen && nightCareDue
                        ? "Finish logging food and check your night care routine."
                        : nutritionOpen ? "Finish logging today’s food." : "Check your night care routine.",
                    categoryIdentifier: MomentumNotificationCategory.eveningCheckIn,
                    dateComponents: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date),
                    userInfo: [
                        "kind": "eveningCheckIn",
                        "domainDay": PersistedDomainDay.encode(currentDay)
                    ]
                ))
            }
        }

        return reminders
    }

    private static func reminderDate(
        for day: DomainDay,
        minutes: Int,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let candidate = PersistedDomainDay.date(
            for: day,
            calendar: calendar,
            hour: minutes / 60,
            minute: minutes % 60
        )
        return candidate.flatMap { $0 > now ? $0 : nil }
    }
}
