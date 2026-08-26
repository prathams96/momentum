import Foundation
import MomentumCore
import SwiftData

/// Every module answers the lazy-setup requirement (pre-launch spec §4).
/// Workout plans are authored content: there is no meaningful default plan
/// to install, so the default is the Plans surface's authoring empty state —
/// creating placeholder templates would violate user ownership of the cycle.
extension WorkoutModuleAdapter: LazyDefaultProviding {
    func createDefaultsIfNeeded(in context: ModuleContext) throws {
        // Authored-content module: the authoring empty state is the default.
    }
}
