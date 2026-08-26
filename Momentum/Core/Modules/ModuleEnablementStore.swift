import Foundation

/// Persists module activation on the settings record as a comma-separated
/// list of ModuleID raw values. Disable ≠ delete: modules keep their data.
@MainActor
enum ModuleEnablementStore {
    static let defaultRawValue = "workout,nutrition,care,hydration"

    static var defaultEnabledIDs: Set<ModuleID> {
        ModuleRegistry.defaultEnabledIDs
    }

    static func enabledIDs(from settings: AppSettingsRecord?) -> Set<ModuleID> {
        guard let settings else { return ModuleRegistry.defaultEnabledIDs }
        // An explicit empty list means every module is off; only a missing
        // settings record falls back to ship-default enablement.
        let ids = settings.enabledModulesRaw
            .split(separator: ",")
            .map { ModuleID($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.rawValue.isEmpty }
        return Set(ids)
    }

    static func apply(_ ids: Set<ModuleID>, to settings: AppSettingsRecord) {
        settings.enabledModulesRaw = ids
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
        settings.updatedAt = .now
    }
}
