import Foundation
import MomentumCore
import SwiftData

/// Workout-side day-rollover engine moved out of the monolithic reconciler.
/// Back-fills missed-workout events for every elapsed due opportunity. All
/// mutations are idempotent and never save; the orchestrator owns the single
/// save at the end of reconciliation.
@MainActor
enum WorkoutReconciliationEngine {
    static func reconcile(
        previousDay: DomainDay,
        currentDay: DomainDay,
        in context: ModuleContext
    ) throws {
        let modelContext = context.modelContext
        let workouts = try modelContext.fetch(FetchDescriptor<WorkoutTemplateRecord>())
        let anchors = try modelContext.fetch(FetchDescriptor<CycleAnchorRecord>())
        let sessions = try modelContext.fetch(FetchDescriptor<WorkoutSessionRecord>())
        let state = ScheduleProjection.evaluate(
            workouts: workouts,
            anchors: anchors,
            sessions: sessions,
            domainDayCutoffMinutes: context.domainDayCutoffMinutes,
            now: context.now,
            calendar: context.calendar
        )
        backfillMissedEvents(
            state: state,
            currentDay: currentDay,
            sessions: sessions,
            events: try modelContext.fetch(FetchDescriptor<WorkoutDayEventRecord>()),
            context: modelContext,
            now: context.now,
            calendar: context.calendar
        )
    }

    private static func backfillMissedEvents(
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
}

extension WorkoutModuleAdapter: ReconcilingModule {
    func reconcile(previousDay: DomainDay, currentDay: DomainDay, in context: ModuleContext) throws {
        try WorkoutReconciliationEngine.reconcile(
            previousDay: previousDay,
            currentDay: currentDay,
            in: context
        )
    }
}
