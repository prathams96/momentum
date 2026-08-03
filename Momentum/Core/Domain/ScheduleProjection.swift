import Foundation
import MomentumCore

@MainActor
enum ScheduleProjection {
    static func currentDomainDay(
        settings: [AppSettingsRecord],
        now: Date,
        calendar: Calendar
    ) -> DomainDay {
        DomainDay.containing(
            now,
            calendar: calendar,
            cutoffMinutes: AppSettingsRecord.canonical(in: settings)?.domainDayCutoffMinutes ?? 180
        )
    }

    static func evaluate(
        workouts: [WorkoutTemplateRecord],
        anchors: [CycleAnchorRecord],
        sessions: [WorkoutSessionRecord],
        settings: [AppSettingsRecord],
        now: Date,
        calendar: Calendar
    ) -> WorkoutScheduleState {
        let currentDay = currentDomainDay(settings: settings, now: now, calendar: calendar)
        guard let anchor = anchors.max(by: { $0.updatedAt < $1.updatedAt }),
              let firstDueDay = PersistedDomainDay.decode(anchor.firstDueDomainDay) else {
            return .needsRepair(reason: .missingAnchorWorkout)
        }

        let openSessions = sessions.filter { $0.finishedAt == nil && $0.deletedAt == nil }
        if openSessions.count > 1 {
            return .needsRepair(reason: .duplicateActiveSessions)
        }

        let templates = workouts.filter { !$0.isArchived }.map {
            WorkoutTemplate(
                id: $0.id,
                name: $0.name,
                sequenceIndex: $0.sequenceIndex,
                recoveryDaysAfter: $0.recoveryDaysAfter
            )
        }
        let completedSessions = sessions
            .filter { $0.deletedAt == nil }
            .compactMap { session -> CompletedWorkoutSession? in
                guard let finishedAt = session.finishedAt,
                      let workoutID = session.workoutTemplateID,
                      let completionValue = session.completionDomainDay,
                      let completionDay = PersistedDomainDay.decode(completionValue) else {
                    return nil
                }
                return CompletedWorkoutSession(
                    id: session.id,
                    workoutTemplateID: workoutID,
                    completionDomainDay: completionDay,
                    finishedAt: finishedAt,
                    sequenceIndexSnapshot: session.sequenceIndexSnapshot,
                    recoveryDaysAfterSnapshot: session.recoveryDaysAfterSnapshot,
                    nextWorkoutTemplateIDSnapshot: session.nextWorkoutTemplateIDSnapshot
                )
            }

        return ScheduleEngine().evaluate(
            ScheduleInput(
                activeWorkoutTemplates: templates,
                cycleAnchor: CycleAnchor(
                    nextWorkoutID: anchor.nextWorkoutTemplateID,
                    firstDueDomainDay: firstDueDay
                ),
                completedSessions: completedSessions,
                currentDomainDay: currentDay,
                calendar: calendar,
                activeSessionID: openSessions.first?.id
            )
        )
    }
}
