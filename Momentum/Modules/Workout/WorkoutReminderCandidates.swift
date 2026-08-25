import Foundation
import MomentumCore
import SwiftData

extension WorkoutModuleAdapter: ReminderCandidateProviding {
    func reminderCandidates(in context: ModuleContext) -> [ScheduledReminder] {
        let workouts = (try? context.modelContext.fetch(FetchDescriptor<WorkoutTemplateRecord>())) ?? []
        let anchors = (try? context.modelContext.fetch(FetchDescriptor<CycleAnchorRecord>())) ?? []
        let sessions = (try? context.modelContext.fetch(FetchDescriptor<WorkoutSessionRecord>())) ?? []
        let state = ScheduleProjection.evaluate(
            workouts: workouts,
            anchors: anchors,
            sessions: sessions,
            currentDomainDay: context.currentDomainDay,
            now: context.now,
            calendar: context.calendar
        )
        guard case let .due(workoutID, _, _) = state,
              let date = Self.reminderDate(
                for: context.currentDomainDay,
                minutes: context.workoutNotificationMinutes,
                now: context.now,
                calendar: context.calendar
              ) else {
            return []
        }
        let domainDay = PersistedDomainDay.encode(context.currentDomainDay)
        return [ScheduledReminder(
            identifier: "workout.due.\(workoutID.uuidString).\(domainDay)",
            title: "Workout due",
            body: "Your next workout is ready when you are.",
            categoryIdentifier: MomentumNotificationCategory.workoutDue,
            dateComponents: context.calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: date
            ),
            userInfo: [
                "kind": "workoutDue",
                "workoutID": workoutID.uuidString,
                "domainDay": domainDay
            ]
        )]
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
