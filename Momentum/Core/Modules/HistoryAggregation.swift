import Foundation
import MomentumCore

/// Cross-module adherence math over module-provided facts. Shared surfaces
/// call these; they contain no domain knowledge of their own.
enum ModuleHistoryMath {
    /// Category Streak for one category's facts, ending at `through`.
    ///
    /// `pausedDays` are module-disabled days (parent spec §3.3): they are
    /// injected as neutral entries so the streak pauses across them instead
    /// of breaking, without changing the semantics of unrecorded gaps.
    static func categoryStreak(
        facts: [HistoryAdherenceFact],
        category: HistoryCategory,
        through day: DomainDay,
        calendar: Calendar,
        pausedDays: Set<DomainDay> = []
    ) -> Int {
        let scoped = facts.filter { $0.category == category && $0.day <= day }
        switch category {
        case .workouts:
            let outcomeByDay = Dictionary(grouping: scoped, by: \.day).mapValues { group in
                group.contains(where: \.isCompleted)
                    ? WorkoutAdherenceOutcome.finished
                    : WorkoutAdherenceOutcome.missed
            }
            var timeline: [(DomainDay, WorkoutAdherenceOutcome)] = outcomeByDay.map { ($0.key, $0.value) }
            timeline.append(contentsOf: pausedDays.filter { $0 <= day }.map { ($0, .paused) })
            timeline.sort { $0.0 < $1.0 }
            return AdherenceEngine().workoutStreak(opportunities: timeline.map(\.1))
        case .nutrition:
            let recorded = groupedByDay(scoped).map { factDay, values in
                NutritionAdherenceDay(
                    day: factDay,
                    isFinalized: values.contains(where: \.isCompleted)
                )
            }
            let recordedDays = Set(recorded.map(\.day))
            let paused = pausedDays
                .filter { $0 <= day && !recordedDays.contains($0) }
                .map { NutritionAdherenceDay(day: $0, isFinalized: false, isPaused: true) }
            return AdherenceEngine().nutritionStreak(days: recorded + paused, calendar: calendar)
        default:
            let recorded = groupedByDay(scoped).map { factDay, values in
                CareAdherenceDay(
                    day: factDay,
                    dueCount: values.count,
                    completedCount: values.count(where: \.isCompleted)
                )
            }
            let recordedDays = Set(recorded.map(\.day))
            let paused = pausedDays
                .filter { $0 <= day && !recordedDays.contains($0) }
                .map { CareAdherenceDay(day: $0, dueCount: 0, completedCount: 0, isPaused: true) }
            return AdherenceEngine().careStreak(days: recorded + paused, calendar: calendar)
        }
    }

    private static func groupedByDay(
        _ facts: [HistoryAdherenceFact]
    ) -> [DomainDay: [HistoryAdherenceFact]] {
        Dictionary(grouping: facts, by: \.day)
    }
}
