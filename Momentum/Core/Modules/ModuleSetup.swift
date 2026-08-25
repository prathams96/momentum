import Foundation
import MomentumCore
import SwiftData

/// Lazily creates a module's plan/defaults when it is enabled for the first
/// time or re-enabled (pre-launch spec §4 · Setup steps). Hydration already
/// creates its plan on first surface visit; this closes the same gap for a
/// nutrition target so later-enabled modules never render without defaults.
/// Workout and personal care plans are user-authored — their surfaces' empty
/// states are the intended first-run experience, so there is nothing to seed.
@MainActor
enum ModuleSetup {
    static func ensureDefaults(
        for newlyEnabled: Set<ModuleID>,
        unitSystemRaw: String,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        in context: ModelContext
    ) throws {
        if newlyEnabled.contains(BuiltInModuleID.hydration) {
            _ = HydrationPlanService.fetchOrCreate(
                in: context,
                now: now,
                unitSystemRaw: unitSystemRaw
            )
        }

        if newlyEnabled.contains(BuiltInModuleID.nutrition) {
            let currentDay = DomainDay.containing(now, calendar: calendar, cutoffMinutes: 180)
            let effectiveFrom = PersistedDomainDay.encode(currentDay)
            let targets = try context.fetch(FetchDescriptor<NutritionTargetRecord>())
            let hasOpenTarget = targets.contains { $0.effectiveTo == nil && $0.effectiveFrom <= effectiveFrom }
            if !hasOpenTarget {
                context.insert(NutritionTargetRecord(effectiveFrom: effectiveFrom))
            }
        }
    }
}
