import MomentumCore
import SwiftData
import Foundation

/// Shared plan-mutation services. They live outside any feature view because
/// multiple modules and surfaces (Plans, Progress, Onboarding) use them.
@MainActor
enum NutritionPlanService {
    enum SaveError: LocalizedError {
        case invalidRange

        var errorDescription: String? {
            "The display target must be inside the calorie range, and all targets must be non-negative."
        }
    }

    static func target(for day: DomainDay, in targets: [NutritionTargetRecord]) -> NutritionTargetRecord? {
        let value = PersistedDomainDay.encode(day)
        return targets
            .filter { $0.effectiveFrom <= value && ($0.effectiveTo == nil || $0.effectiveTo! >= value) }
            .max { ($0.effectiveFrom, $0.updatedAt, $0.id.uuidString) < ($1.effectiveFrom, $1.updatedAt, $1.id.uuidString) }
    }

    static func saveTarget(
        effectiveFrom day: DomainDay,
        displayTarget: Int,
        calorieMinimum: Int,
        calorieMaximum: Int,
        proteinMinimum: Int,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        in context: ModelContext
    ) throws {
        guard calorieMinimum >= 0, calorieMaximum >= calorieMinimum,
              displayTarget >= calorieMinimum, displayTarget <= calorieMaximum,
              proteinMinimum >= 0 else { throw SaveError.invalidRange }

        let dayValue = PersistedDomainDay.encode(day)
        let previousDay = PersistedDomainDay.encode(day.adding(days: -1, calendar: calendar))
        let targets = try context.fetch(FetchDescriptor<NutritionTargetRecord>())
        let sameDay = targets.filter { $0.effectiveFrom == dayValue }.sorted {
            ($0.updatedAt, $0.id.uuidString) > ($1.updatedAt, $1.id.uuidString)
        }
        let target = sameDay.first ?? NutritionTargetRecord(effectiveFrom: dayValue)
        if sameDay.isEmpty { context.insert(target) }
        for duplicate in sameDay.dropFirst() { context.delete(duplicate) }

        for existing in targets where existing.id != target.id {
            if existing.effectiveFrom < dayValue,
               existing.effectiveTo == nil || existing.effectiveTo! >= dayValue {
                existing.effectiveTo = previousDay
                existing.updatedAt = now
            } else if existing.effectiveFrom > dayValue {
                context.delete(existing)
            }
        }

        target.effectiveTo = nil
        target.calorieDisplayTarget = displayTarget
        target.calorieMinimum = calorieMinimum
        target.calorieMaximum = calorieMaximum
        target.proteinMinimumGrams = proteinMinimum
        target.updatedAt = now
        do { try context.save() }
        catch { context.rollback(); throw error }
    }
}

@MainActor
enum PlanEditingService {
    static func reorderWorkouts(_ workouts: [WorkoutTemplateRecord], now: Date = .now, in context: ModelContext) throws {
        for (index, workout) in workouts.enumerated() {
            workout.sequenceIndex = index
            workout.updatedAt = now
        }
        try save(context)
    }

    static func chooseNextWorkout(
        _ workout: WorkoutTemplateRecord,
        canonicalAnchor: CycleAnchorRecord?,
        currentDay: DomainDay,
        now: Date = .now,
        in context: ModelContext
    ) throws {
        let anchor = canonicalAnchor ?? CycleAnchorRecord(
            nextWorkoutTemplateID: workout.id,
            firstDueDomainDay: PersistedDomainDay.encode(currentDay)
        )
        anchor.nextWorkoutTemplateID = workout.id
        anchor.updatedAt = now
        if canonicalAnchor == nil { context.insert(anchor) }
        try save(context)
    }

    static func save(_ context: ModelContext) throws {
        do { try context.save() }
        catch { context.rollback(); throw error }
    }
}
