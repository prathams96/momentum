import XCTest
import MomentumCore
import SwiftData
@testable import Momentum

/// Parent-spec §3.3 / §9.3: disabled-interval days are ineligible for a
/// module's Category Streak — the streak pauses and resumes on re-enable
/// rather than breaking. The enablement ledger records activation intervals;
/// streak math treats uncovered days as neutral.
@MainActor
final class StreakPauseLedgerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func withStore<T>(_ body: (ModelContext) throws -> T) rethrows -> T {
        let container = try! ModelContainerFactory.makePreview()
        let context = container.mainContext
        context.insert(AppSettingsRecord(domainDayCutoffMinutes: 180))
        try? context.save()
        return try withExtendedLifetime(container) {
            try body(context)
        }
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> DomainDay {
        DomainDay(year: year, month: month, day: day)
    }

    private func date(_ day: DomainDay, hour: Int) -> Date {
        PersistedDomainDay.date(for: day, calendar: calendar, hour: hour)!
    }

    // MARK: - Ledger reconcile

    func testReconcileOpensOneIntervalPerEnabledModuleAndIsIdempotent() throws {
        try withStore { context in
            let now = date(day(2026, 8, 10), hour: 12)

            try ModuleEnablementLedger.reconcile(
                enabledIDs: ModuleRegistry.defaultEnabledIDs,
                currentDay: day(2026, 8, 10),
                in: context
            )
            try ModuleEnablementLedger.reconcile(
                enabledIDs: ModuleRegistry.defaultEnabledIDs,
                currentDay: day(2026, 8, 11),
                in: context
            )
            try context.save()

            let intervals = try context.fetch(FetchDescriptor<ModuleActivationIntervalRecord>())
            XCTAssertEqual(intervals.count, ModuleRegistry.standard.modules.count)
            XCTAssertTrue(intervals.allSatisfy { $0.enabledToDomainDay == nil })
            XCTAssertTrue(intervals.allSatisfy { $0.enabledFromDomainDay.isEmpty },
                          "First sighting covers from forever so upgrade streaks survive.")
            _ = now
        }
    }

    func testDisablingClosesTheIntervalAndMarksThoseDaysPaused() throws {
        try withStore { context in
            let enabled = ModuleRegistry.defaultEnabledIDs
            var hydrationOnly = enabled
            hydrationOnly.remove(BuiltInModuleID.hydration)

            try ModuleEnablementLedger.reconcile(enabledIDs: enabled, currentDay: day(2026, 8, 5), in: context)
            try ModuleEnablementLedger.reconcile(enabledIDs: hydrationOnly, currentDay: day(2026, 8, 8), in: context)
            try context.save()

            let paused = ModuleEnablementLedger.pausedDays(
                for: BuiltInModuleID.hydration,
                through: day(2026, 8, 20),
                calendar: calendar,
                in: context
            )
            // Disabled on Aug 8 → Aug 8 onward is ineligible.
            XCTAssertEqual(paused, Set((8...20).map { day(2026, 8, $0) }))

            // A never-disabled module has no paused days.
            let workoutPaused = ModuleEnablementLedger.pausedDays(
                for: BuiltInModuleID.workout,
                through: day(2026, 8, 20),
                calendar: calendar,
                in: context
            )
            XCTAssertTrue(workoutPaused.isEmpty)
        }
    }

    func testReEnablingResumesTheDayAfterTheToggle() throws {
        try withStore { context in
            var withoutCare = ModuleRegistry.defaultEnabledIDs
            withoutCare.remove(BuiltInModuleID.care)

            try ModuleEnablementLedger.reconcile(enabledIDs: ModuleRegistry.defaultEnabledIDs, currentDay: day(2026, 8, 1), in: context)
            try ModuleEnablementLedger.reconcile(enabledIDs: withoutCare, currentDay: day(2026, 8, 4), in: context)
            try ModuleEnablementLedger.reconcile(enabledIDs: ModuleRegistry.defaultEnabledIDs, currentDay: day(2026, 8, 9), in: context)
            try context.save()

            let paused = ModuleEnablementLedger.pausedDays(
                for: BuiltInModuleID.care,
                through: day(2026, 8, 12),
                calendar: calendar,
                in: context
            )
            // Re-enabled Aug 9 → the toggle day itself stays paused; the
            // streak resumes Aug 10 (spec §2: resumes the day after re-enable).
            XCTAssertEqual(paused, Set((4...9).map { day(2026, 8, $0) }))
        }
    }

    func testModulesWithNoLedgerHistoryPauseNothing() throws {
        withStore { context in
            let paused = ModuleEnablementLedger.pausedDays(
                for: BuiltInModuleID.hydration,
                through: day(2026, 8, 20),
                calendar: calendar,
                in: context
            )
            XCTAssertTrue(paused.isEmpty)
        }
    }

    // MARK: - End-to-end pause across a disabled window (hydration)

    func testHydrationStreakPausesAcrossDisabledWindowInsteadOfBreaking() throws {
        try withStore { context in
            // Reached target Aug 1–3; module "disabled" Aug 4–6 (no data);
            // reached again Aug 7. Streak must be 4, not reset to 1.
            for dayIndex in [1, 2, 3, 7] {
                context.insert(HydrationDayRecord(
                    domainDay: PersistedDomainDay.encode(day(2026, 8, dayIndex)),
                    targetMLSnapshot: 1000
                ))
                context.insert(HydrationEntryRecord(
                    amountML: 1000,
                    consumedAt: date(day(2026, 8, dayIndex), hour: 12),
                    domainDay: PersistedDomainDay.encode(day(2026, 8, dayIndex))
                ))
            }
            try ModuleEnablementLedger.reconcile(enabledIDs: ModuleRegistry.defaultEnabledIDs, currentDay: day(2026, 8, 3), in: context)
            var withoutHydration = ModuleRegistry.defaultEnabledIDs
            withoutHydration.remove(BuiltInModuleID.hydration)
            try ModuleEnablementLedger.reconcile(enabledIDs: withoutHydration, currentDay: day(2026, 8, 4), in: context)
            try ModuleEnablementLedger.reconcile(enabledIDs: ModuleRegistry.defaultEnabledIDs, currentDay: day(2026, 8, 7), in: context)
            try context.save()

            let adapter = ModuleRegistry.standard.module(with: BuiltInModuleID.hydration) as? any HistoryContributing
            XCTAssertNotNil(adapter)
            let moduleContext = ModuleContext(
                modelContext: context,
                calendar: calendar,
                now: date(day(2026, 8, 7), hour: 18),
                domainDayCutoffMinutes: 180
            )
            let streak = adapter?.categoryStreak(asOf: day(2026, 8, 7), in: moduleContext)
            XCTAssertEqual(streak, 4)
        }
    }
}
