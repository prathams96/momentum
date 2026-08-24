import Foundation

/// Compile-time registry of all modules. Shared surfaces iterate this list —
/// adding or removing a module never edits surface logic.
@MainActor
struct ModuleRegistry {
    let modules: [any MomentumModule]

    init(modules: [any MomentumModule]) {
        self.modules = modules.sorted { $0.metadata.todayRank < $1.metadata.todayRank }
    }

    /// The shipping roster. Order is deterministic and defines reconciliation
    /// ordering, Today ranking ties, and export file order.
    static let standard = ModuleRegistry(modules: [
        WorkoutModuleAdapter(),
        NutritionModuleAdapter(),
        CareModuleAdapter(),
        HydrationModuleAdapter(),
    ])

    /// Enablement applied before any enablement preference exists on disk.
    static let defaultEnabledIDs: Set<ModuleID> = [
        BuiltInModuleID.workout,
        BuiltInModuleID.nutrition,
        BuiltInModuleID.care,
        BuiltInModuleID.hydration,
    ]

    func module(with id: ModuleID) -> (any MomentumModule)? {
        modules.first { $0.metadata.id == id }
    }

    /// Enabled modules in registry (rank) order.
    func enabledModules(_ enabled: Set<ModuleID>) -> [any MomentumModule] {
        modules.filter { enabled.contains($0.metadata.id) }
    }

    var todayContributors: [any TodayContributing] {
        modules.compactMap { $0 as? any TodayContributing }
    }

    var planContributors: [any PlanContributing] {
        modules.compactMap { $0 as? any PlanContributing }
    }

    var insightsContributors: [any InsightsContributing] {
        modules.compactMap { $0 as? any InsightsContributing }
    }

    var historyContributors: [any HistoryContributing] {
        modules.compactMap { $0 as? any HistoryContributing }
    }

    var reconcilers: [any ReconcilingModule] {
        modules.compactMap { $0 as? any ReconcilingModule }
    }

    var reminderProviders: [any ReminderCandidateProviding] {
        modules.compactMap { $0 as? any ReminderCandidateProviding }
    }

    var exportProviders: [any ExportDefinitionProviding] {
        modules.compactMap { $0 as? any ExportDefinitionProviding }
    }
}
