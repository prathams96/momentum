import Foundation
import MomentumCore
import SwiftData

/// Lazy setup for the hydration module: the singleton plan is created on
/// first need with unit-aware canonical values.
extension HydrationModuleAdapter: LazyDefaultProviding {
    func createDefaultsIfNeeded(in context: ModuleContext) throws {
        _ = HydrationPlanService.fetchOrCreate(
            in: context.modelContext,
            now: context.now,
            unitSystemRaw: context.unitSystemRaw
        )
    }
}
