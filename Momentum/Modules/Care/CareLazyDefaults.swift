import Foundation
import MomentumCore
import SwiftData

/// Every module answers the lazy-setup requirement (pre-launch spec §4).
/// Personal care routines are authored content named by purpose or active
/// ingredient: the default is the authoring empty state, never placeholder
/// routines.
extension CareModuleAdapter: LazyDefaultProviding {
    func createDefaultsIfNeeded(in context: ModuleContext) throws {
        // Authored-content module: the authoring empty state is the default.
    }
}
