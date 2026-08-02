import Foundation

public struct WorkoutTemplate: Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let sequenceIndex: Int
    public let recoveryDaysAfter: Int

    public init(
        id: UUID,
        name: String,
        sequenceIndex: Int,
        recoveryDaysAfter: Int
    ) {
        self.id = id
        self.name = name
        self.sequenceIndex = sequenceIndex
        self.recoveryDaysAfter = recoveryDaysAfter
    }
}

public struct CycleAnchor: Equatable, Sendable {
    public let nextWorkoutID: UUID
    public let firstDueDomainDay: DomainDay

    public init(nextWorkoutID: UUID, firstDueDomainDay: DomainDay) {
        self.nextWorkoutID = nextWorkoutID
        self.firstDueDomainDay = firstDueDomainDay
    }
}

public struct CompletedWorkoutSession: Equatable, Sendable {
    public let id: UUID
    public let workoutTemplateID: UUID
    public let completionDomainDay: DomainDay
    public let finishedAt: Date

    public init(
        id: UUID,
        workoutTemplateID: UUID,
        completionDomainDay: DomainDay,
        finishedAt: Date
    ) {
        self.id = id
        self.workoutTemplateID = workoutTemplateID
        self.completionDomainDay = completionDomainDay
        self.finishedAt = finishedAt
    }
}

public struct ScheduleInput: Sendable {
    public let activeWorkoutTemplates: [WorkoutTemplate]
    public let cycleAnchor: CycleAnchor
    public let completedSessions: [CompletedWorkoutSession]
    public let currentDomainDay: DomainDay
    public let calendar: Calendar
    public let activeSessionID: UUID?

    public init(
        activeWorkoutTemplates: [WorkoutTemplate],
        cycleAnchor: CycleAnchor,
        completedSessions: [CompletedWorkoutSession],
        currentDomainDay: DomainDay,
        calendar: Calendar = Calendar(identifier: .gregorian),
        activeSessionID: UUID? = nil
    ) {
        self.activeWorkoutTemplates = activeWorkoutTemplates
        self.cycleAnchor = cycleAnchor
        self.completedSessions = completedSessions
        self.currentDomainDay = currentDomainDay
        self.calendar = calendar
        self.activeSessionID = activeSessionID
    }
}

public enum ScheduleRepairReason: Equatable, Sendable {
    case noActiveWorkoutTemplates
    case missingAnchorWorkout
    case invalidSequenceIndices
    case invalidRecoveryDays
    case completedSessionReferencesMissingWorkout
}

public enum WorkoutScheduleState: Equatable, Sendable {
    case due(workoutID: UUID, dueDay: DomainDay, overdueBy: Int)
    case recovery(nextWorkoutID: UUID, eligibleDay: DomainDay, daysRemaining: Int)
    case active(sessionID: UUID)
    case needsRepair(reason: ScheduleRepairReason)
}

public struct ScheduleEngine: Sendable {
    public init() {}

    public func evaluate(_ input: ScheduleInput) -> WorkoutScheduleState {
        if let activeSessionID = input.activeSessionID {
            return .active(sessionID: activeSessionID)
        }

        guard !input.activeWorkoutTemplates.isEmpty else {
            return .needsRepair(reason: .noActiveWorkoutTemplates)
        }

        let templates = input.activeWorkoutTemplates.sorted { lhs, rhs in
            lhs.sequenceIndex < rhs.sequenceIndex
        }
        guard templates.map(\.sequenceIndex).elementsEqual(0..<templates.count) else {
            return .needsRepair(reason: .invalidSequenceIndices)
        }
        guard templates.allSatisfy({ $0.recoveryDaysAfter >= 0 }) else {
            return .needsRepair(reason: .invalidRecoveryDays)
        }
        guard templates.contains(where: { $0.id == input.cycleAnchor.nextWorkoutID }) else {
            return .needsRepair(reason: .missingAnchorWorkout)
        }
        guard input.completedSessions.allSatisfy({ session in
            templates.contains(where: { $0.id == session.workoutTemplateID })
        }) else {
            return .needsRepair(reason: .completedSessionReferencesMissingWorkout)
        }

        guard let latestSession = input.completedSessions.max(by: { lhs, rhs in
            if lhs.finishedAt != rhs.finishedAt {
                return lhs.finishedAt < rhs.finishedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }) else {
            return state(
                workoutID: input.cycleAnchor.nextWorkoutID,
                dueDay: input.cycleAnchor.firstDueDomainDay,
                currentDay: input.currentDomainDay,
                calendar: input.calendar
            )
        }

        guard let completedIndex = templates.firstIndex(where: {
            $0.id == latestSession.workoutTemplateID
        }) else {
            return .needsRepair(reason: .completedSessionReferencesMissingWorkout)
        }
        let completedWorkout = templates[completedIndex]
        let nextIndex = (completedIndex + 1) % templates.count
        let nextWorkout = templates[nextIndex]
        let eligibleDay = latestSession.completionDomainDay.adding(
            days: completedWorkout.recoveryDaysAfter + 1,
            calendar: input.calendar
        )

        return state(
            workoutID: nextWorkout.id,
            dueDay: eligibleDay,
            currentDay: input.currentDomainDay,
            calendar: input.calendar
        )
    }

    private func state(
        workoutID: UUID,
        dueDay: DomainDay,
        currentDay: DomainDay,
        calendar: Calendar
    ) -> WorkoutScheduleState {
        if currentDay < dueDay {
            return .recovery(
                nextWorkoutID: workoutID,
                eligibleDay: dueDay,
                daysRemaining: distance(from: currentDay, to: dueDay, calendar: calendar)
            )
        }

        return .due(
            workoutID: workoutID,
            dueDay: dueDay,
            overdueBy: distance(from: dueDay, to: currentDay, calendar: calendar)
        )
    }

    private func distance(
        from start: DomainDay,
        to end: DomainDay,
        calendar: Calendar
    ) -> Int {
        calendar.dateComponents(
            [.day],
            from: start.foundationDate(calendar: calendar),
            to: end.foundationDate(calendar: calendar)
        ).day ?? 0
    }
}

private extension DomainDay {
    func foundationDate(calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: 12
        ))!
    }
}
