import XCTest
import SwiftData
import MomentumCore
@testable import Momentum

@MainActor
private final class FakeTestModule: MomentumModule {
    let metadata = ModuleMetadata(
        id: ModuleID("fake"),
        displayName: "Fake",
        symbolName: "questionmark",
        tint: .gray,
        todayRank: 15
    )

    init() {}
}

@MainActor
final class ModuleRegistryTests: XCTestCase {
    func testStandardRegistryResolvesBuiltInModulesInRankOrder() {
        let registry = ModuleRegistry.standard

        XCTAssertEqual(
            registry.modules.map { $0.metadata.id.rawValue },
            ["workout", "nutrition", "care"]
        )
        XCTAssertNotNil(registry.module(with: BuiltInModuleID.workout))
        XCTAssertNil(registry.module(with: ModuleID("missing")))
    }

    func testDefaultEnablementContainsEveryBuiltInModule() {
        for module in ModuleRegistry.standard.modules {
            XCTAssertTrue(
                ModuleRegistry.defaultEnabledIDs.contains(module.metadata.id),
                "New built-in \(module.metadata.id) must ship enabled."
            )
        }
    }

    func testEnablementRoundTripsThroughSettingsRecord() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        let settings = AppSettingsRecord()
        context.insert(settings)
        try context.save()

        XCTAssertEqual(ModuleEnablementStore.enabledIDs(from: settings), ModuleRegistry.defaultEnabledIDs)

        var enabled = ModuleRegistry.defaultEnabledIDs
        enabled.insert(ModuleID("hydration"))
        ModuleEnablementStore.apply(enabled, to: settings)
        try context.save()

        XCTAssertEqual(ModuleEnablementStore.enabledIDs(from: settings), enabled)

        settings.enabledModulesRaw = ""
        XCTAssertEqual(ModuleEnablementStore.enabledIDs(from: settings), ModuleRegistry.defaultEnabledIDs)

        XCTAssertEqual(ModuleEnablementStore.enabledIDs(from: nil), ModuleRegistry.defaultEnabledIDs)
    }

    func testDisabledModulesAreFilteredWhilePreservingRegistryOrder() {
        let fake = FakeTestModule()
        let registry = ModuleRegistry(modules: [
            WorkoutModuleAdapter(),
            fake,
            NutritionModuleAdapter(),
            CareModuleAdapter(),
        ])

        let enabled = registry.enabledModules([
            BuiltInModuleID.workout,
            BuiltInModuleID.care,
            ModuleID("fake"),
        ])

        // Rank order wins regardless of construction order: workout(10),
        // fake(15), care(30); nutrition(20) is disabled.
        XCTAssertEqual(enabled.map { $0.metadata.id.rawValue }, ["workout", "fake", "care"])
    }

    func testCapabilityDiscoveryOnlySeesImplementingModules() {
        let registry = ModuleRegistry.standard
        let builtInIDs: Set<ModuleID> = [
            BuiltInModuleID.workout,
            BuiltInModuleID.nutrition,
            BuiltInModuleID.care,
        ]

        // Today, plan, insights, and history-aggregation capabilities ship
        // with the built-in adapters; Phase D moved reconciliation behind
        // the workout and care module boundaries.
        XCTAssertEqual(Set(registry.todayContributors.map { $0.metadata.id }), builtInIDs)
        XCTAssertEqual(Set(registry.planContributors.map { $0.metadata.id }), builtInIDs)
        XCTAssertEqual(
            Set(registry.insightsContributors.map { $0.metadata.id }),
            [BuiltInModuleID.workout, BuiltInModuleID.nutrition]
        )
        XCTAssertEqual(
            Set(registry.reconcilers.map { $0.metadata.id }),
            [BuiltInModuleID.workout, BuiltInModuleID.care]
        )
        XCTAssertTrue(registry.reminderProviders.isEmpty)
        XCTAssertTrue(registry.exportProviders.isEmpty)
    }
}
