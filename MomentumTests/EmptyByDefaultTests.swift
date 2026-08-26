import MomentumCore
import SwiftData
import XCTest
@testable import Momentum

@MainActor
final class EmptyByDefaultTests: XCTestCase {
    func testEnsureSettingsRecordCreatesOnlySettingsNeverSeedContent() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext

        try SeedData.ensureSettingsRecord(in: context)
        try SeedData.ensureSettingsRecord(in: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AppSettingsRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutTemplateRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareRoutineTemplateRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<NutritionTargetRecord>()), 0)

        let settings = try XCTUnwrap(
            AppSettingsRecord.canonical(in: try context.fetch(FetchDescriptor<AppSettingsRecord>()))
        )
        XCTAssertFalse(settings.onboardingCompleted)
    }

    func testExamplePlanInstallsOnlyBehindExplicitPath() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext

        try SeedData.ensureSettingsRecord(in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutTemplateRecord>()), 0)

        // The explicit opt-in path installs the example content.
        try SeedData.install(in: context, currentDomainDay: DomainDay(year: 2026, month: 8, day: 2))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutTemplateRecord>()), 4)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareRoutineTemplateRecord>()), 5)
    }

    func testUninstallExamplePlanRestoresEmptyByDefault() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        try SeedData.install(in: context, currentDomainDay: DomainDay(year: 2026, month: 8, day: 2))

        try SeedData.uninstallExamplePlan(in: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutTemplateRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExercisePrescriptionRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseAlternativeRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareRoutineTemplateRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareTaskTemplateRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CycleAnchorRecord>()), 0)
    }

    func testUninstallExamplePlanRefusesWhenHistoryExists() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        try SeedData.install(in: context, currentDomainDay: DomainDay(year: 2026, month: 8, day: 2))
        context.insert(WorkoutSessionRecord(
            workoutNameSnapshot: "Upper A",
            scheduledDomainDay: "2026-08-02",
            finishedAt: Date(timeIntervalSince1970: 100),
            completionDomainDay: "2026-08-02"
        ))
        try context.save()

        try SeedData.uninstallExamplePlan(in: context)

        // Recorded history pins the seed content in place.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutTemplateRecord>()), 4)
    }

    func testImperialLocaleDefaultsRenderAsWholeFluidOunces() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext

        let imperialPlan = HydrationPlanService.fetchOrCreate(
            in: context,
            now: .now,
            unitSystemRaw: "imperial"
        )

        // Storage stays ml-canonical but renders as whole fl oz:
        // ≈85 fl oz target, 8/16/24 fl oz presets.
        XCTAssertEqual(HydrationEngine.fluidOuncesDisplay(fromML: imperialPlan.targetML), "85")
        XCTAssertEqual(HydrationEngine.fluidOuncesDisplay(fromML: imperialPlan.firstPresetML), "8")
        XCTAssertEqual(HydrationEngine.fluidOuncesDisplay(fromML: imperialPlan.secondPresetML), "16")
        XCTAssertEqual(HydrationEngine.fluidOuncesDisplay(fromML: imperialPlan.thirdPresetML), "24")

        // Metric-era values keep honest fractional rendering: 500 ml is
        // 16.9 fl oz, never a rounded-up false 17.
        XCTAssertEqual(HydrationEngine.fluidOuncesDisplay(fromML: 500), "16.9")
        XCTAssertEqual(HydrationEngine.exactFluidOunces(fromML: 500), 500.0 / 29.573_529_562_5, accuracy: 0.0001)
        XCTAssertEqual(
            HydrationEngine.millilitres(fromExactFluidOunces: HydrationEngine.exactFluidOunces(fromML: 500)),
            500
        )

        // Metric keeps its existing defaults.
        try context.delete(context.fetch(FetchDescriptor<HydrationPlanRecord>()).first!)
        let metricPlan = HydrationPlanService.fetchOrCreate(in: context, now: .now)
        XCTAssertEqual(metricPlan.targetML, 2500)
        XCTAssertEqual(metricPlan.firstPresetML, 250)
        XCTAssertEqual(metricPlan.secondPresetML, 500)
        XCTAssertEqual(metricPlan.thirdPresetML, 750)
    }
}
