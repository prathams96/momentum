import Foundation
import MomentumCore
import SwiftUI
import SwiftData
import UserNotifications

/// Semantic completion state of a module's Today obligation.
enum ContributionState: Sendable, Equatable {
    /// No obligation exists (e.g. nothing logged yet on a fresh day).
    case optional
    /// An obligation exists and is not yet satisfied.
    case ongoing
    /// The day's obligation is satisfied.
    case completed
    /// Something needs repair before the routine can continue.
    case attention
}

/// A module's ranked, stateful claim on the Today surface. Core derives
/// DailyThreadFocus from these contributions — never from domain knowledge.
struct TodayContribution {
    let moduleID: ModuleID
    let title: String
    let symbolName: String
    let tint: Color?
    let state: ContributionState
    let rank: Int
    let accessibilitySummary: String?

    init(
        metadata: ModuleMetadata,
        state: ContributionState,
        accessibilitySummary: String? = nil
    ) {
        self.moduleID = metadata.id
        self.title = metadata.displayName
        self.symbolName = metadata.symbolName
        self.tint = metadata.tint
        self.state = state
        self.rank = metadata.todayRank
        self.accessibilitySummary = accessibilitySummary
    }
}

/// Base protocol every module implements. Capabilities are separate,
/// small protocols below; surfaces feature-detect via `as?`.
@MainActor
protocol MomentumModule: AnyObject {
    var metadata: ModuleMetadata { get }
}

/// Contributes a ranked state plus an interactive section to Today.
@MainActor
protocol TodayContributing: MomentumModule {
    func todayContribution(in context: ModuleContext) -> TodayContribution?
    func todaySection(in context: ModuleContext) -> AnyView?
}

/// Contributes a plan-editing section to the Plans surface.
@MainActor
protocol PlanContributing: MomentumModule {
    func planSection(in context: ModuleContext) -> AnyView?
}

/// Contributes an insight section to the Progress surface.
@MainActor
protocol InsightsContributing: MomentumModule {
    func insightsSection(in context: ModuleContext) -> AnyView?
}

/// Contributes adherence facts, per-day history detail, and its Category Streak.
@MainActor
protocol HistoryContributing: MomentumModule {
    /// Facts across all recorded days, used by heatmap/streak projections.
    func historyFacts(in context: ModuleContext) -> [HistoryAdherenceFact]
    /// Interactive sections describing everything recorded on one day.
    func historyDaySections(for day: DomainDay, in context: ModuleContext) -> [AnyView]
    /// Consecutive eligible days with the category completed, ending at `day`.
    /// Returns nil when the module is disabled or has no streak semantics.
    func categoryStreak(asOf day: DomainDay, in context: ModuleContext) -> Int?
    /// Folds this module's facts for one day into scored activities. Registry-
    /// owned so shared scoring never hard-codes per-category rules.
    func adherenceActivities(on day: DomainDay, facts: [HistoryAdherenceFact]) -> [DueAdherenceActivity]
}

/// Performs idempotent day-rollover reconciliation inside the module boundary.
@MainActor
protocol ReconcilingModule: MomentumModule {
    /// The previous/current day pair is computed once by the orchestrator so
    /// ordering stays deterministic. Must be idempotent; must not save.
    func reconcile(previousDay: DomainDay, currentDay: DomainDay, in context: ModuleContext) throws
}

/// Supplies notification candidates; Core owns scheduling and bundling.
@MainActor
protocol ReminderCandidateProviding: MomentumModule {
    /// Identifier must be namespaced `<module>.<kind>...` and stable per opportunity.
    func reminderCandidates(in context: ModuleContext) -> [ScheduledReminder]
}

/// Declares the UNNotificationCategory its reminders use. Registration is
/// registry-driven: Core never hard-codes a module's category.
@MainActor
protocol NotificationCategoryProviding: MomentumModule {
    func notificationCategory() -> UNNotificationCategory
}

/// Supplies CSV export definitions; filenames of migrated modules are frozen.
struct ModuleExportDefinition {
    let moduleID: ModuleID
    let fileName: String
    let header: [String]
    let rowsProvider: @MainActor (ModelContext) throws -> [[String]]

    init(
        moduleID: ModuleID,
        fileName: String,
        header: [String],
        rowsProvider: @escaping @MainActor (ModelContext) throws -> [[String]]
    ) {
        self.moduleID = moduleID
        self.fileName = fileName
        self.header = header
        self.rowsProvider = rowsProvider
    }
}

@MainActor
protocol ExportDefinitionProviding: MomentumModule {
    func exportDefinitions() -> [ModuleExportDefinition]
}
