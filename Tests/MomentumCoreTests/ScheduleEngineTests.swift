import Foundation
import Testing
@testable import MomentumCore

struct ScheduleEngineTests {
    @Test
    func test_finishingUpperAMakesLowerADueNextDomainDay() {
        let upperAID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let lowerAID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let upperBID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let lowerBID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let completionDay = DomainDay(year: 2026, month: 8, day: 2)

        let input = ScheduleInput(
            activeWorkoutTemplates: [
                WorkoutTemplate(id: lowerBID, name: "Lower B", sequenceIndex: 3, recoveryDaysAfter: 2),
                WorkoutTemplate(id: upperBID, name: "Upper B", sequenceIndex: 2, recoveryDaysAfter: 0),
                WorkoutTemplate(id: upperAID, name: "Upper A", sequenceIndex: 0, recoveryDaysAfter: 0),
                WorkoutTemplate(id: lowerAID, name: "Lower A", sequenceIndex: 1, recoveryDaysAfter: 1)
            ],
            cycleAnchor: CycleAnchor(
                nextWorkoutID: upperAID,
                firstDueDomainDay: completionDay
            ),
            completedSessions: [
                CompletedWorkoutSession(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
                    workoutTemplateID: upperAID,
                    completionDomainDay: completionDay,
                    finishedAt: Date(timeIntervalSince1970: 10)
                )
            ],
            currentDomainDay: completionDay.adding(days: 1, calendar: Calendar(identifier: .gregorian))
        )

        let result = ScheduleEngine().evaluate(input)

        #expect(result == .due(
            workoutID: lowerAID,
            dueDay: DomainDay(year: 2026, month: 8, day: 3),
            overdueBy: 0
        ))
    }

    @Test
    func test_finishingLowerARequiresOneRecoveryDayBeforeUpperB() {
        let lowerAID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let upperBID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let completionDay = DomainDay(year: 2026, month: 8, day: 2)

        let result = ScheduleEngine().evaluate(makeInput(
            completedWorkoutID: lowerAID,
            currentDay: DomainDay(year: 2026, month: 8, day: 3),
            finishedAt: 20
        ))

        #expect(result == .recovery(
            nextWorkoutID: upperBID,
            eligibleDay: completionDay.adding(
                days: 2,
                calendar: Calendar(identifier: .gregorian)
            ),
            daysRemaining: 1
        ))
    }

    @Test
    func test_finishingUpperBRequiresNoRecoveryDayBeforeLowerB() {
        let upperBID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let lowerBID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!

        let result = ScheduleEngine().evaluate(makeInput(
            completedWorkoutID: upperBID,
            currentDay: DomainDay(year: 2026, month: 8, day: 3),
            finishedAt: 20
        ))

        #expect(result == .due(
            workoutID: lowerBID,
            dueDay: DomainDay(year: 2026, month: 8, day: 3),
            overdueBy: 0
        ))
    }

    @Test
    func test_finishingLowerBRequiresTwoRecoveryDaysBeforeUpperA() {
        let lowerBID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let upperAID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        let result = ScheduleEngine().evaluate(makeInput(
            completedWorkoutID: lowerBID,
            currentDay: DomainDay(year: 2026, month: 8, day: 4),
            finishedAt: 20
        ))

        #expect(result == .recovery(
            nextWorkoutID: upperAID,
            eligibleDay: DomainDay(year: 2026, month: 8, day: 5),
            daysRemaining: 1
        ))
    }

    @Test
    func test_unsortedCompletedSessionsUseTheLatestFinishedSession() {
        let upperAID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let lowerAID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let completionDay = DomainDay(year: 2026, month: 8, day: 2)
        let input = makeInput(
            completedWorkoutID: upperAID,
            currentDay: DomainDay(year: 2026, month: 8, day: 3),
            finishedAt: 20,
            additionalSessions: [CompletedWorkoutSession(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
                workoutTemplateID: lowerAID,
                completionDomainDay: completionDay,
                finishedAt: Date(timeIntervalSince1970: 10)
            )]
        )

        let result = ScheduleEngine().evaluate(input)

        #expect(result == .due(
            workoutID: lowerAID,
            dueDay: DomainDay(year: 2026, month: 8, day: 3),
            overdueBy: 0
        ))
    }

    @Test
    func test_longGapLeavesTheSameWorkoutDueWithoutCatchUp() {
        let upperAID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        let result = ScheduleEngine().evaluate(makeInput(
            completedWorkoutID: upperAID,
            currentDay: DomainDay(year: 2026, month: 8, day: 10),
            finishedAt: 20
        ))

        #expect(result == .due(
            workoutID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            dueDay: DomainDay(year: 2026, month: 8, day: 3),
            overdueBy: 7
        ))
    }

    @Test
    func test_initialAnchorMakesUpperADueOnItsFirstDueDomainDay() {
        let upperAID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let firstDueDay = DomainDay(year: 2026, month: 8, day: 2)
        let input = makeInput(
            completedWorkoutID: upperAID,
            currentDay: firstDueDay,
            finishedAt: 20
        )
        let initialInput = ScheduleInput(
            activeWorkoutTemplates: input.activeWorkoutTemplates,
            cycleAnchor: input.cycleAnchor,
            completedSessions: [],
            currentDomainDay: firstDueDay
        )

        let result = ScheduleEngine().evaluate(initialInput)

        #expect(result == .due(
            workoutID: upperAID,
            dueDay: firstDueDay,
            overdueBy: 0
        ))
    }

    @Test
    func test_activeSessionTakesPrecedenceOverScheduleState() {
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!
        var input = makeInput(
            completedWorkoutID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            currentDay: DomainDay(year: 2026, month: 8, day: 2),
            finishedAt: 20
        )
        input = ScheduleInput(
            activeWorkoutTemplates: input.activeWorkoutTemplates,
            cycleAnchor: input.cycleAnchor,
            completedSessions: input.completedSessions,
            currentDomainDay: input.currentDomainDay,
            activeSessionID: sessionID
        )

        #expect(ScheduleEngine().evaluate(input) == .active(sessionID: sessionID))
    }

    @Test
    func test_nonContiguousSequenceNeedsRepair() {
        let input = ScheduleInput(
            activeWorkoutTemplates: [
                WorkoutTemplate(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    name: "Upper A",
                    sequenceIndex: 0,
                    recoveryDaysAfter: 0
                ),
                WorkoutTemplate(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                    name: "Lower A",
                    sequenceIndex: 2,
                    recoveryDaysAfter: 1
                )
            ],
            cycleAnchor: CycleAnchor(
                nextWorkoutID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                firstDueDomainDay: DomainDay(year: 2026, month: 8, day: 2)
            ),
            completedSessions: [],
            currentDomainDay: DomainDay(year: 2026, month: 8, day: 2)
        )

        #expect(ScheduleEngine().evaluate(input) == .needsRepair(reason: .invalidSequenceIndices))
    }

    private func makeInput(
        completedWorkoutID: UUID,
        currentDay: DomainDay,
        finishedAt: TimeInterval,
        additionalSessions: [CompletedWorkoutSession] = []
    ) -> ScheduleInput {
        let completionDay = DomainDay(year: 2026, month: 8, day: 2)
        let sessions = [CompletedWorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            workoutTemplateID: completedWorkoutID,
            completionDomainDay: completionDay,
            finishedAt: Date(timeIntervalSince1970: finishedAt)
        )] + additionalSessions
        let upperAID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let lowerAID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let upperBID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let lowerBID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!

        return ScheduleInput(
            activeWorkoutTemplates: [
                WorkoutTemplate(id: lowerBID, name: "Lower B", sequenceIndex: 3, recoveryDaysAfter: 2),
                WorkoutTemplate(id: upperBID, name: "Upper B", sequenceIndex: 2, recoveryDaysAfter: 0),
                WorkoutTemplate(id: upperAID, name: "Upper A", sequenceIndex: 0, recoveryDaysAfter: 0),
                WorkoutTemplate(id: lowerAID, name: "Lower A", sequenceIndex: 1, recoveryDaysAfter: 1)
            ],
            cycleAnchor: CycleAnchor(
                nextWorkoutID: upperAID,
                firstDueDomainDay: completionDay
            ),
            completedSessions: sessions,
            currentDomainDay: currentDay
        )
    }
}
