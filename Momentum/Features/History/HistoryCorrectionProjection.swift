import Foundation
import MomentumCore

struct HistoryWorkoutDeletionPreview: Equatable {
    let before: WorkoutScheduleState
    let after: WorkoutScheduleState
    let beforeSummary: String
    let afterSummary: String
}

@MainActor
enum HistoryCorrectionProjection {
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
}
