import Foundation
import MomentumCore
import SwiftData

/// Lazy setup for the nutrition module: an open Nutrition Target effective
/// today exists so adherence evaluation and Today's progress rows work from
/// the first surface visit.
extension NutritionModuleAdapter: LazyDefaultProviding {
    func createDefaultsIfNeeded(in context: ModuleContext) throws {
        let modelContext = context.modelContext
        let targets = (try? modelContext.fetch(FetchDescriptor<NutritionTargetRecord>())) ?? []
        let today = PersistedDomainDay.encode(context.currentDomainDay)
        let hasOpenTarget = targets.contains { $0.effectiveTo == nil && $0.effectiveFrom <= today }
        if !hasOpenTarget {
            modelContext.insert(NutritionTargetRecord(effectiveFrom: today))
        }
    }
}
