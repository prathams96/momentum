import XCTest
import MomentumCore
import SwiftData
import SwiftUI
@testable import Momentum

@MainActor
private final class ExplodingReconciliationModule: MomentumModule, ReconcilingModule {
    struct ExplosionError: Error {}

    let metadata = ModuleMetadata(
        id: ModuleID("chaos"),
        displayName: "Chaos",
        symbolName: "exclamationmark.triangle",
        tint: .gray,
        todayRank: 15
    )

    func reconcile(previousDay: DomainDay, currentDay: DomainDay, in context: ModuleContext) throws {
        throw ExplosionError()
    }
}

@MainActor
final class ReconciliationOrchestrationTests: XCTestCase {
    func testDoubleReconcileIsIdempotentAcrossOccurrencesAndEvents() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        let day = DomainDay(year: 2026, month: 8, day: 2)
        try SeedData.install(in: context, currentDomainDay: day)

        let now = PersistedDomainDay.date(
            for: day.adding(days: 1, calendar: .autoupdatingCurrent),
            calendar: .autoupdatingCurrent,
            hour: 12
        )!
        try DailyReconciler.reconcile(in: context, now: now)

        let firstOccurrences = try context.fetchCount(FetchDescriptor<CareOccurrenceRecord>())
        let firstCompletions = try context.fetchCount(FetchDescriptor<CareTaskCompletionRecord>())
        let firstEvents = try context.fetchCount(FetchDescriptor<WorkoutDayEventRecord>())

        XCTAssertGreaterThan(firstOccurrences, 0)
        XCTAssertGreaterThan(firstCompletions, 0)

        try DailyReconciler.reconcile(in: context, now: now)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareOccurrenceRecord>()), firstOccurrences)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareTaskCompletionRecord>()), firstCompletions)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutDayEventRecord>()), firstEvents)
    }

    func testFailingModuleDoesNotBlockOtherModulesOrTheSave() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        let day = DomainDay(year: 2026, month: 8, day: 2)
        try SeedData.install(in: context, currentDomainDay: day)

        // The exploding module sits between the workout and care modules in
        // registry rank order; both real modules must still reconcile and the
        // orchestrator must still save.
        let registry = ModuleRegistry(modules: [
            WorkoutModuleAdapter(),
            ExplodingReconciliationModule(),
            NutritionModuleAdapter(),
            CareModuleAdapter(),
        ])

        let now = PersistedDomainDay.date(
            for: day.adding(days: 1, calendar: .autoupdatingCurrent),
            calendar: .autoupdatingCurrent,
            hour: 12
        )!
        try DailyReconciler.reconcile(in: context, now: now, calendar: .autoupdatingCurrent, registry: registry)

        // Save happened: the records are visible from a fresh context on the
        // same store, which would not be true if inserts were unsaved.
        let verifier = ModelContext(container)
        let persistedOccurrences = try verifier.fetchCount(FetchDescriptor<CareOccurrenceRecord>())
        XCTAssertGreaterThan(persistedOccurrences, 0)

        let nextDayValue = PersistedDomainDay.encode(day.adding(days: 1, calendar: .autoupdatingCurrent))
        let occurrences = try context.fetch(FetchDescriptor<CareOccurrenceRecord>())
            .filter { $0.dueDomainDay == nextDayValue }
        XCTAssertFalse(occurrences.isEmpty)
        XCTAssertTrue(occurrences.allSatisfy { $0.statusRaw == "pending" })
    }

    func testDisabledCareModuleCreatesNoOccurrences() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        let day = DomainDay(year: 2026, month: 8, day: 2)
        try SeedData.install(in: context, currentDomainDay: day)

        let settings = try XCTUnwrap(AppSettingsRecord.canonical(
            in: try context.fetch(FetchDescriptor<AppSettingsRecord>())
        ))
        ModuleEnablementStore.apply([.init(rawValue: "workout"), .init(rawValue: "nutrition")], to: settings)
        try context.save()

        // Morning care is due every weekday-set day; with care disabled no
        // occurrence may be materialized for it.
        let dueDays: [DomainDay] = [day.adding(days: 1, calendar: .autoupdatingCurrent), day.adding(days: 3, calendar: .autoupdatingCurrent)]
        for dueDay in dueDays {
            let now = PersistedDomainDay.date(for: dueDay, calendar: .autoupdatingCurrent, hour: 12)!
            try DailyReconciler.reconcile(in: context, now: now)
        }

        let occurrences = try context.fetch(FetchDescriptor<CareOccurrenceRecord>())
        XCTAssertTrue(occurrences.isEmpty)
    }
}
