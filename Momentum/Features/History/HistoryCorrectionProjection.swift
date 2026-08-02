import Foundation
import MomentumCore

struct HistoryWorkoutDeletionPreview: Equatable {
    let before: WorkoutScheduleState
    let after: WorkoutScheduleState
    let beforeSummary: String
    let afterSummary: String
}

struct HistoryWorkoutTimestampPreview: Equatable {
    let before: WorkoutScheduleState
    let after: WorkoutScheduleState
    let beforeSummary: String
    let afterSummary: String
    let proposedCompletionDay: DomainDay
}

@MainActor
enum HistoryCorrectionProjection {
    static func workoutCompletionPreview(
        sessionID: UUID,
        proposedFinishedAt: Date,
        workouts: [WorkoutTemplateRecord],
        anchors: [CycleAnchorRecord],
        sessions: [WorkoutSessionRecord],
        settings: [AppSettingsRecord],
        now: Date,
        calendar: Calendar
    ) -> HistoryWorkoutTimestampPreview? {
        guard sessions.contains(where: {
            $0.id == sessionID && $0.finishedAt != nil && $0.deletedAt == nil
        }) else {
            return nil
        }
        let cutoff = AppSettingsRecord.canonical(in: settings)?.domainDayCutoffMinutes ?? 180
        let proposedDay = DomainDay.containing(
            proposedFinishedAt,
            calendar: calendar,
            cutoffMinutes: cutoff
        )
        let completedSessions = sessions.filter { $0.finishedAt != nil }
        let before = ScheduleProjection.evaluate(
            workouts: workouts,
            anchors: anchors,
            sessions: completedSessions,
            settings: settings,
            now: now,
            calendar: calendar
        )
        guard let after = evaluate(
            workouts: workouts,
            anchors: anchors,
            sessions: completedSessions,
            settings: settings,
            overridingSessionID: sessionID,
            proposedFinishedAt: proposedFinishedAt,
            proposedCompletionDay: proposedDay,
            now: now,
            calendar: calendar
        ) else {
            return nil
        }

        return HistoryWorkoutTimestampPreview(
            before: before,
            after: after,
            beforeSummary: summary(for: before, workouts: workouts),
            afterSummary: summary(for: after, workouts: workouts),
            proposedCompletionDay: proposedDay
        )
    }

    static func workoutDeletionPreview(
        sessionID: UUID,
        workouts: [WorkoutTemplateRecord],
        anchors: [CycleAnchorRecord],
        sessions: [WorkoutSessionRecord],
        settings: [AppSettingsRecord],
        now: Date,
        calendar: Calendar
    ) -> HistoryWorkoutDeletionPreview? {
        guard sessions.contains(where: {
            $0.id == sessionID && $0.finishedAt != nil && $0.deletedAt == nil
        }) else {
            return nil
        }

        // Open sessions intentionally stay out of the preview so both sides describe
        // the underlying next workout and due day, not the transient resume state.
        let completedSessions = sessions.filter { $0.finishedAt != nil }
        let before = ScheduleProjection.evaluate(
            workouts: workouts,
            anchors: anchors,
            sessions: completedSessions,
            settings: settings,
            now: now,
            calendar: calendar
        )
        let after = ScheduleProjection.evaluate(
            workouts: workouts,
            anchors: anchors,
            sessions: completedSessions.filter { $0.id != sessionID },
            settings: settings,
            now: now,
            calendar: calendar
        )

        return HistoryWorkoutDeletionPreview(
            before: before,
            after: after,
            beforeSummary: summary(for: before, workouts: workouts),
            afterSummary: summary(for: after, workouts: workouts)
        )
    }

    private static func summary(
        for state: WorkoutScheduleState,
        workouts: [WorkoutTemplateRecord]
    ) -> String {
        switch state {
        case let .due(workoutID, dueDay, _):
            return "\(workoutName(workoutID, in: workouts)) · due \(PersistedDomainDay.encode(dueDay))"
        case let .recovery(workoutID, eligibleDay, _):
            return "\(workoutName(workoutID, in: workouts)) · due \(PersistedDomainDay.encode(eligibleDay))"
        case .active:
            return "Active workout session"
        case .needsRepair:
            return "Schedule needs repair"
        }
    }

    private static func workoutName(
        _ id: UUID,
        in workouts: [WorkoutTemplateRecord]
    ) -> String {
        workouts.first(where: { $0.id == id })?.name ?? "Workout"
    }

    private static func evaluate(
        workouts: [WorkoutTemplateRecord],
        anchors: [CycleAnchorRecord],
        sessions: [WorkoutSessionRecord],
        settings: [AppSettingsRecord],
        overridingSessionID: UUID,
        proposedFinishedAt: Date,
        proposedCompletionDay: DomainDay,
        now: Date,
        calendar: Calendar
    ) -> WorkoutScheduleState? {
        guard let anchor = anchors.max(by: { $0.updatedAt < $1.updatedAt }),
              let firstDueDay = PersistedDomainDay.decode(anchor.firstDueDomainDay) else {
            return nil
        }
        let templates = workouts.filter { !$0.isArchived }.map {
            WorkoutTemplate(
                id: $0.id,
                name: $0.name,
                sequenceIndex: $0.sequenceIndex,
                recoveryDaysAfter: $0.recoveryDaysAfter
            )
        }
        let completed = sessions.compactMap { session -> CompletedWorkoutSession? in
            guard session.deletedAt == nil,
                  let workoutID = session.workoutTemplateID,
                  let originalFinishedAt = session.finishedAt,
                  let completionValue = session.completionDomainDay,
                  let originalDay = PersistedDomainDay.decode(completionValue) else {
                return nil
            }
            let isOverride = session.id == overridingSessionID
            return CompletedWorkoutSession(
                id: session.id,
                workoutTemplateID: workoutID,
                completionDomainDay: isOverride ? proposedCompletionDay : originalDay,
                finishedAt: isOverride ? proposedFinishedAt : originalFinishedAt,
                sequenceIndexSnapshot: session.sequenceIndexSnapshot,
                recoveryDaysAfterSnapshot: session.recoveryDaysAfterSnapshot,
                nextWorkoutTemplateIDSnapshot: session.nextWorkoutTemplateIDSnapshot
            )
        }
        let currentDay = ScheduleProjection.currentDomainDay(
            settings: settings,
            now: now,
            calendar: calendar
        )
        return ScheduleEngine().evaluate(ScheduleInput(
            activeWorkoutTemplates: templates,
            cycleAnchor: CycleAnchor(
                nextWorkoutID: anchor.nextWorkoutTemplateID,
                firstDueDomainDay: firstDueDay
            ),
            completedSessions: completed,
            currentDomainDay: currentDay,
            calendar: calendar
        ))
    }
}
