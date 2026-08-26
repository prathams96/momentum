import Foundation
import MomentumCore
import SwiftData

/// Runs every enabled module's lazy setup (pre-launch spec §4 · Setup
/// steps). Registry-driven: a fifth module conforms to `LazyDefaultProviding`
/// and is covered without edits here. Idempotent; runs on every
/// reconciliation so later-enabled modules are ready by first visit.
@MainActor
enum ModuleSetup {
    static func ensureDefaults(
        enabledIDs: Set<ModuleID>,
        settings: AppSettingsRecord?,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        in context: ModelContext,
        registry: ModuleRegistry = .standard
    ) throws {
        let moduleContext = ModuleContext.make(
            in: context,
            settings: settings,
            now: now,
            calendar: calendar
        )
        for module in registry.enabledModules(enabledIDs) {
            if let provider = module as? any LazyDefaultProviding {
                try provider.createDefaultsIfNeeded(in: moduleContext)
            }
        }
    }
}
