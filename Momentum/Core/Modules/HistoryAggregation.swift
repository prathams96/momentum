import Foundation
import MomentumCore

/// Cross-module adherence math over module-provided facts. Shared surfaces
/// call these; they contain no domain knowledge of their own.
enum ModuleHistoryMath {
    /// Category Streak for one category's facts, ending at `through`.
    static func categoryStreak(
        facts: [HistoryAdherenceFact],
        category: HistoryCategory,
        through day: DomainDay,
        calendar: Calendar
    ) -> Int {
        let scoped = facts.filter { $0.category == category && $0.day <= day }
        switch category {
        case .workouts:
            let outcomes: [WorkoutAdherenceOutcome] = groupedByDay(scoped)
                .sorted { $0.key < $1.key }
                .map { group in
                    group.value.contains(where: \.isCompleted)
                        ? .finished
                        : .missed
                }
            return AdherenceEngine().workoutStreak(opportunities: outcomes)
        case .nutrition:
            let days = groupedByDay(scoped).map { day, values in
                NutritionAdherenceDay(
                    day: day,
                    isFinalized: values.contains(where: \.isCompleted)
                )
            }
            return AdherenceEngine().nutritionStreak(days: days, calendar: calendar)
        default:
            let days = groupedByDay(scoped).map { day, values in
                CareAdherenceDay(
                    day: day,
                    dueCount: values.count,
                    completedCount: values.count(where: \.isCompleted)
                )
            }
            return AdherenceEngine().careStreak(days: days, calendar: calendar)
        }
    }

    private static func groupedByDay(
        _ facts: [HistoryAdherenceFact]
    ) -> [DomainDay: [HistoryAdherenceFact]] {
        Dictionary(grouping: facts, by: \.day)
    }
}
