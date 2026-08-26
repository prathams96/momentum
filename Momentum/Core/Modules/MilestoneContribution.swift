import Foundation
import MomentumCore

/// A milestone-relevant fact emitted by the module that owns the underlying
/// records. Milestones are a true Core projection over these facts — Core
/// never reaches into module schema (pre-launch spec §7).
enum MilestoneFact {
    /// A finished Workout Session at its completion moment.
    case workoutCompleted(at: Date)
    /// A recorded missed/skipped Due Workout opportunity at its recording moment.
    case workoutOpportunityMissed(at: Date)
    /// One completed Working Set performance behind an exercise prescription.
    case exercisePerformance(
        prescriptionID: UUID,
        weightKg: Double,
        repetitions: Int,
        at: Date
    )
    /// A finalized nutrition day with its target-range snapshot and totals.
    case nutritionDayFinalized(
        day: DomainDay,
        finalizedAt: Date,
        calorieMinimum: Int,
        calorieMaximum: Int,
        proteinMinimum: Int,
        calories: Double,
        proteinGrams: Double
    )
    /// One calendar day's personal-care outcome across all due routines.
    case personalCareDay(day: DomainDay, isFullyCompleted: Bool, lastActivityAt: Date)
}

@MainActor
protocol MilestoneContributing: MomentumModule {
    func milestoneFacts(in context: ModuleContext) -> [MilestoneFact]
}
