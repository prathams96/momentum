import Foundation
import MomentumCore

enum HistoryCategory: String, CaseIterable, Identifiable, Sendable {
    case all
    case workouts
    case nutrition
    case care
    case measurements

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .workouts: "Workout"
        case .nutrition: "Nutrition"
        case .care: "Care"
        case .measurements: "Measurements"
        }
    }
}

struct HistoryAdherenceFact: Equatable, Sendable {
    let day: DomainDay
    let category: HistoryCategory
    let isCompleted: Bool
}

struct HistoryStreakSummary: Equatable, Sendable {
    let workout: Int
    let nutrition: Int
    let care: Int
}

enum HistoryProjection {
    @MainActor
    static func facts(
        sessions: [WorkoutSessionRecord],
        workoutEvents: [WorkoutDayEventRecord],
        nutritionDays: [NutritionDayRecord],
        careOccurrences: [CareOccurrenceRecord]
    ) -> [HistoryAdherenceFact] {
        let completedWorkouts = sessions.compactMap { session -> HistoryAdherenceFact? in
            guard session.deletedAt == nil,
                  session.finishedAt != nil,
                  let value = session.completionDomainDay,
                  let day = PersistedDomainDay.decode(value) else { return nil }
            return HistoryAdherenceFact(day: day, category: .workouts, isCompleted: true)
        }
        let workoutOutcomes = workoutEvents.compactMap { event -> HistoryAdherenceFact? in
            guard event.deletedAt == nil,
                  let day = PersistedDomainDay.decode(event.domainDay) else { return nil }
            return HistoryAdherenceFact(day: day, category: .workouts, isCompleted: false)
        }
        let nutrition = nutritionDays.compactMap { record -> HistoryAdherenceFact? in
            guard let day = PersistedDomainDay.decode(record.domainDay) else { return nil }
            return HistoryAdherenceFact(
                day: day,
                category: .nutrition,
                isCompleted: record.finalizedAt != nil
            )
        }
        let care = careOccurrences.compactMap { occurrence -> HistoryAdherenceFact? in
            guard occurrence.statusRaw != "repairedDuplicate",
                  let day = PersistedDomainDay.decode(occurrence.dueDomainDay) else { return nil }
            return HistoryAdherenceFact(
                day: day,
                category: .care,
                isCompleted: occurrence.statusRaw == "completed"
            )
        }
        return completedWorkouts + workoutOutcomes + nutrition + care
    }

    static func heatmapDays(
        endingOn day: DomainDay,
        calendar: Calendar,
        weekCount: Int = 16
    ) -> [DomainDay] {
        guard weekCount > 0,
              let date = PersistedDomainDay.date(for: day, calendar: calendar) else {
            return []
        }
        let weekday = calendar.component(.weekday, from: date)
        let daysSinceMonday = (weekday + 5) % 7
        let monday = day.adding(days: -daysSinceMonday, calendar: calendar)
        let sunday = monday.adding(days: 6, calendar: calendar)
        let count = weekCount * 7
        let firstDay = sunday.adding(days: -(count - 1), calendar: calendar)
        return (0..<count).map { firstDay.adding(days: $0, calendar: calendar) }
    }

    static func adherenceScore(
        on day: DomainDay,
        facts: [HistoryAdherenceFact],
        category: HistoryCategory
    ) -> DailyAdherenceScore {
        let selected = facts.filter {
            $0.day == day && (category == .all || $0.category == category)
        }
        guard category != .measurements else {
            return .noObligation
        }

        var activities: [DueAdherenceActivity] = []
        for groupedCategory in [HistoryCategory.workouts, .nutrition, .care] {
            let matching = selected.filter { $0.category == groupedCategory }
            guard !matching.isEmpty else { continue }
            if groupedCategory == .care {
                activities.append(contentsOf: matching.map {
                    DueAdherenceActivity(kind: .morningCare, isCompleted: $0.isCompleted)
                })
            } else {
                activities.append(DueAdherenceActivity(
                    kind: groupedCategory == .workouts ? .workout : .nutritionFinalization,
                    isCompleted: matching.contains(where: \.isCompleted)
                ))
            }
        }

        return AdherenceEngine().dailyScore(activities: activities)
    }

    static func streaks(
        facts: [HistoryAdherenceFact],
        calendar: Calendar
    ) -> HistoryStreakSummary {
        let workoutFacts = groupedByDay(facts.filter { $0.category == .workouts })
            .sorted { $0.key < $1.key }
            .map { group in
                group.value.contains(where: \.isCompleted)
                    ? WorkoutAdherenceOutcome.finished
                    : WorkoutAdherenceOutcome.missed
            }

        let nutritionFacts = groupedByDay(facts.filter { $0.category == .nutrition })
            .map { day, values in
                NutritionAdherenceDay(
                    day: day,
                    isFinalized: values.contains(where: \.isCompleted)
                )
            }

        let careFacts = groupedByDay(facts.filter { $0.category == .care })
            .map { day, values in
                CareAdherenceDay(
                    day: day,
                    dueCount: values.count,
                    completedCount: values.count(where: \.isCompleted)
                )
            }

        let engine = AdherenceEngine()
        return HistoryStreakSummary(
            workout: engine.workoutStreak(opportunities: workoutFacts),
            nutrition: engine.nutritionStreak(days: nutritionFacts, calendar: calendar),
            care: engine.careStreak(days: careFacts, calendar: calendar)
        )
    }

    private static func groupedByDay(
        _ facts: [HistoryAdherenceFact]
    ) -> [DomainDay: [HistoryAdherenceFact]] {
        Dictionary(grouping: facts, by: \.day)
    }
}
