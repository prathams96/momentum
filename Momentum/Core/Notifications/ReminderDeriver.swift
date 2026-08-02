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

        if case let .due(workoutID, _, _) = scheduleState,
           let settings,
           let date = reminderDate(
               for: currentDay,
               minutes: settings.workoutNotificationMinutes,
               now: now,
               calendar: calendar
           ) {
            reminders.append(ScheduledReminder(
                identifier: "workout.\(workoutID.uuidString).\(PersistedDomainDay.encode(currentDay))",
                title: "Workout due",
                body: "Your next workout is ready when you are.",
                categoryIdentifier: MomentumNotificationCategory.workoutDue,
                dateComponents: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date),
                userInfo: [
                    "kind": "workoutDue",
                    "workoutID": workoutID.uuidString,
                    "domainDay": PersistedDomainDay.encode(currentDay)
                ]
            ))
        }

        let dueCare = occurrences
            .filter { $0.dueDomainDay == PersistedDomainDay.encode(currentDay) && $0.statusRaw == "pending" }
            .sorted { ($0.dueAt, $0.id.uuidString) < ($1.dueAt, $1.id.uuidString) }
        let nutritionOpen = nutritionDay?.finalizedAt == nil
        let nutritionMinutes = settings?.nutritionReminderMinutes ?? 22 * 60
        let coalescedNightCare = nutritionOpen ? dueCare.filter {
            $0.routineRoleRaw == "night" && minutesSinceMidnight($0.dueAt, calendar: calendar) == nutritionMinutes
        } : []
        let coalescedOccurrenceIDs = Set(coalescedNightCare.map(\.id))

        for occurrence in dueCare where occurrence.dueAt > now && !coalescedOccurrenceIDs.contains(occurrence.id) {
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

        if nutritionOpen {
            if let date = reminderDate(for: currentDay, minutes: nutritionMinutes, now: now, calendar: calendar) {
                var userInfo = [
                    "kind": "eveningCheckIn",
                    "domainDay": PersistedDomainDay.encode(currentDay)
                ]
                if let occurrence = coalescedNightCare.first {
                    userInfo["occurrenceID"] = occurrence.id.uuidString
                }
                reminders.append(ScheduledReminder(
                    identifier: "evening.\(PersistedDomainDay.encode(currentDay))",
                    title: "Evening check-in",
                    body: !coalescedNightCare.isEmpty
                        ? "Finish logging food and check your night care routine."
                        : "Finish logging today’s food.",
                    categoryIdentifier: MomentumNotificationCategory.eveningCheckIn,
                    dateComponents: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date),
                    userInfo: userInfo
                ))
            }
        }

        return reminders
    }

    private static func minutesSinceMidnight(_ date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
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
