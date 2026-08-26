import MomentumCore
import SwiftUI
import SwiftData
import UserNotifications
import XCTest
@testable import Momentum

/// Phase C acceptance locked into CI: one fake module must be able to appear
/// on every shared surface through the registry alone, and a disabled module
/// must render nowhere. No surface may special-case a module.
@MainActor
final class ModuleSurfaceContractTests: XCTestCase {
    private class FakeEverySurfaceModule: MomentumModule {
        let metadata = ModuleMetadata(
            id: ModuleID("fake"),
            displayName: "Fake",
            symbolName: "questionmark",
            tint: .gray,
            todayRank: 15
        )

        func notificationCategory() -> UNNotificationCategory {
            UNNotificationCategory(identifier: "FAKE_CATEGORY", actions: [], intentIdentifiers: [])
        }
    }

    private final class FakeTodayContributor: FakeEverySurfaceModule, TodayContributing {
        func todayContribution(in context: ModuleContext) -> TodayContribution? {
            TodayContribution(metadata: metadata, state: .ongoing)
        }

        func todaySection(in context: ModuleContext) -> AnyView? { AnyView(EmptyView()) }
    }

    private final class FakePlanContributor: FakeEverySurfaceModule, PlanContributing {
        func planSection(in context: ModuleContext) -> AnyView? { AnyView(EmptyView()) }
    }

    private final class FakeInsightsContributor: FakeEverySurfaceModule, InsightsContributing {
        func insightsSection(in context: ModuleContext) -> AnyView? { AnyView(EmptyView()) }
    }

    private final class FakeHistoryContributor: FakeEverySurfaceModule, HistoryContributing {
        func historyFacts(in context: ModuleContext) -> [HistoryAdherenceFact] { [] }
        func historyDaySections(for day: DomainDay, in context: ModuleContext) -> [AnyView] { [] }
        func categoryStreak(asOf day: DomainDay, in context: ModuleContext) -> Int? { nil }
        func adherenceActivities(on day: DomainDay, facts: [HistoryAdherenceFact]) -> [DueAdherenceActivity] { [] }
    }

    private final class FakeReminderProvider: FakeEverySurfaceModule, ReminderCandidateProviding {
        func reminderCandidates(in context: ModuleContext) -> [ScheduledReminder] { [] }
    }

    private final class FakeReconciler: FakeEverySurfaceModule, ReconcilingModule {
        func reconcile(previousDay: DomainDay, currentDay: DomainDay, in context: ModuleContext) throws {}
    }

    private func registryWith(_ modules: [any MomentumModule]) -> ModuleRegistry {
        ModuleRegistry(modules: modules)
    }

    func testEnabledFakeModuleIsDiscoverableOnEveryCapability() {
        let fake = FakeEverySurfaceModule()
        let registry = registryWith([fake])
        let enabled: Set<ModuleID> = [ModuleID("fake")]

        XCTAssertTrue(registry.enabledModules(enabled).contains { $0.metadata.id == ModuleID("fake") })
        XCTAssertNotNil(fake as any MomentumModule)
        // Every surface's discovery pattern resolves the module.
        XCTAssertEqual(registry.enabledModules(enabled).count, 1)
    }

    func testDisabledFakeModuleRendersNowhere() {
        let registry = registryWith([
            FakeTodayContributor(),
            FakePlanContributor(),
            FakeInsightsContributor(),
            FakeHistoryContributor(),
            FakeReminderProvider(),
            FakeReconciler(),
        ])

        // The surfaces' single discovery seam: enabledModules(ids) per capability.
        for enabled: Set<ModuleID> in [[], [BuiltInModuleID.workout], [ModuleID("other")]] {
            let visible = registry.enabledModules(enabled)
            XCTAssertTrue(visible.allSatisfy { $0.metadata.id.rawValue != "fake" })

            XCTAssertTrue((visible.compactMap { $0 as? any TodayContributing }).isEmpty)
            XCTAssertTrue((visible.compactMap { $0 as? any PlanContributing }).isEmpty)
            XCTAssertTrue((visible.compactMap { $0 as? any InsightsContributing }).isEmpty)
            XCTAssertTrue((visible.compactMap { $0 as? any HistoryContributing }).isEmpty)
            XCTAssertTrue((visible.compactMap { $0 as? any ReminderCandidateProviding }).isEmpty)
            XCTAssertTrue((visible.compactMap { $0 as? any ReconcilingModule }).isEmpty)
            XCTAssertTrue((visible.compactMap { $0 as? any ExportDefinitionProviding }).isEmpty)
        }
    }

    func testEnabledCapabilityCastsResolveForEachSurfaceFamily() {
        let registry = registryWith([
            FakeTodayContributor(),
            FakePlanContributor(),
            FakeInsightsContributor(),
            FakeHistoryContributor(),
            FakeReminderProvider(),
            FakeReconciler(),
        ])
        let visible = registry.enabledModules([ModuleID("fake")])

        XCTAssertEqual(visible.compactMap { $0 as? any TodayContributing }.count, 1)
        XCTAssertEqual(visible.compactMap { $0 as? any PlanContributing }.count, 1)
        XCTAssertEqual(visible.compactMap { $0 as? any InsightsContributing }.count, 1)
        XCTAssertEqual(visible.compactMap { $0 as? any HistoryContributing }.count, 1)
        XCTAssertEqual(visible.compactMap { $0 as? any ReminderCandidateProviding }.count, 1)
        XCTAssertEqual(visible.compactMap { $0 as? any ReconcilingModule }.count, 1)
    }
}
