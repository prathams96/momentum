import Foundation
import SwiftUI

/// Wraps the existing workout domain behind the module contracts. The domain
/// keeps its records and engines; this adapter is the only thing shared
/// surfaces see.
@MainActor
final class WorkoutModuleAdapter: MomentumModule {
    let metadata = ModuleMetadata(
        id: BuiltInModuleID.workout,
        displayName: "Workout",
        symbolName: "figure.strengthtraining.traditional",
        tint: MomentumTheme.pulse,
        todayRank: 10
    )

    init() {}
}

@MainActor
final class NutritionModuleAdapter: MomentumModule {
    let metadata = ModuleMetadata(
        id: BuiltInModuleID.nutrition,
        displayName: "Nutrition",
        symbolName: "fork.knife",
        tint: MomentumTheme.success,
        todayRank: 20
    )

    init() {}
}

@MainActor
final class CareModuleAdapter: MomentumModule {
    let metadata = ModuleMetadata(
        id: BuiltInModuleID.care,
        displayName: "Care",
        symbolName: "sparkles",
        tint: MomentumTheme.dataCyan,
        todayRank: 30
    )

    init() {}
}
