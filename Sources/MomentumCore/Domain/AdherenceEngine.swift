import Foundation

public enum AdherenceActivityKind: Equatable, Sendable {
    case workout
    case nutritionFinalization
    case morningCare
    case nightCare
    case hairCare
    case postWorkoutCare
    case hydration
    /// Generic due activity for modules that score without domain-specific kinds.
    case categoryDue
}

public struct DueAdherenceActivity: Equatable, Sendable {
    public let kind: AdherenceActivityKind
    public let isCompleted: Bool

    public init(kind: AdherenceActivityKind, isCompleted: Bool) {
        self.kind = kind
        self.isCompleted = isCompleted
    }
}

public enum DailyAdherenceScore: Equatable, Sendable {
    case noObligation
    case score(completedCount: Int, dueCount: Int, percentage: Double)
}

public enum WorkoutAdherenceOutcome: Equatable, Sendable {
    case finished
    case missed
    case skipped
    /// Module-disabled opportunity: neither extends nor resets the streak.
    case paused
}

public struct NutritionAdherenceDay: Equatable, Sendable {
    public let day: DomainDay
    public let isFinalized: Bool
    public let isPaused: Bool

    public init(day: DomainDay, isFinalized: Bool, isPaused: Bool = false) {
        self.day = day
        self.isFinalized = isFinalized
        self.isPaused = isPaused
    }
}

public struct CareAdherenceDay: Equatable, Sendable {
    public let day: DomainDay
    public let dueCount: Int
    public let completedCount: Int
    public let isPaused: Bool

    public init(day: DomainDay, dueCount: Int, completedCount: Int, isPaused: Bool = false) {
        self.day = day
        self.dueCount = dueCount
        self.completedCount = completedCount
        self.isPaused = isPaused
    }
}

public struct HydrationAdherenceDay: Equatable, Sendable {
    public let day: DomainDay
    public let isTargetReached: Bool
    public let isPaused: Bool

    public init(day: DomainDay, isTargetReached: Bool, isPaused: Bool = false) {
        self.day = day
        self.isTargetReached = isTargetReached
        self.isPaused = isPaused
    }
}

public struct AdherenceEngine: Sendable {
    public init() {}

    public func dailyScore(activities: [DueAdherenceActivity]) -> DailyAdherenceScore {
        guard !activities.isEmpty else {
            return .noObligation
        }

        let completedCount = activities.count(where: \.isCompleted)
        return .score(
            completedCount: completedCount,
            dueCount: activities.count,
            percentage: Double(completedCount) / Double(activities.count) * 100
        )
    }

    /// Recovery days are neutral because this seam accepts Due Workout opportunities only.
    public func workoutStreak(opportunities: [WorkoutAdherenceOutcome]) -> Int {
        var streak = 0
        for outcome in opportunities {
            switch outcome {
            case .finished:
                streak += 1
            case .missed, .skipped:
                streak = 0
            case .paused:
                break
            }
        }
        return streak
    }

    public func nutritionStreak(
        days: [NutritionAdherenceDay],
        calendar: Calendar
    ) -> Int {
        streak(
            days: days.sorted { $0.day < $1.day },
            calendar: calendar,
            domainDay: \.day,
            outcome: { day in
                if day.isPaused { return .neutral }
                return day.isFinalized ? .completed : .incomplete
            }
        )
    }

    public func careStreak(
        days: [CareAdherenceDay],
        calendar: Calendar
    ) -> Int {
        streak(
            days: days.sorted { $0.day < $1.day },
            calendar: calendar,
            domainDay: \.day,
            outcome: { day in
                if day.isPaused { return .neutral }
                if day.dueCount <= 0 {
                    return .neutral
                }
                return day.completedCount >= day.dueCount ? .completed : .incomplete
            }
        )
    }

    /// Consecutive eligible days with the hydration target reached. Paused
    /// (module-disabled) days neither extend nor reset the streak.
    public func hydrationStreak(
        days: [HydrationAdherenceDay],
        calendar: Calendar
    ) -> Int {
        streak(
            days: days.sorted { $0.day < $1.day },
            calendar: calendar,
            domainDay: \.day,
            outcome: { day in
                if day.isPaused { return .neutral }
                return day.isTargetReached ? .completed : .incomplete
            }
        )
    }

    private func streak<Value>(
        days: [Value],
        calendar: Calendar,
        domainDay: KeyPath<Value, DomainDay>,
        outcome: (Value) -> StreakOutcome
    ) -> Int {
        var count = 0
        var previousDay: DomainDay?

        for value in days {
            let day = value[keyPath: domainDay]
            if let previousDay, day != previousDay.adding(days: 1, calendar: calendar) {
                count = 0
            }

            switch outcome(value) {
            case .completed:
                count += 1
            case .incomplete:
                count = 0
            case .neutral:
                break
            }
            previousDay = day
        }

        return count
    }
}

private enum StreakOutcome {
    case completed
    case incomplete
    case neutral
}
