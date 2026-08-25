import MomentumCore
import SwiftData
import XCTest
@testable import Momentum

@MainActor
final class EveningMergeFallbackTests: XCTestCase {
    private func components(_ day: DomainDay, hour: Int, minute: Int = 0) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = PersistedDomainDay.date(for: day, calendar: calendar, hour: hour, minute: minute)!
        return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    func testAnchorlessCandidatesMergeIntoSyntheticEveningCheckIn() throws {
        let day = DomainDay(year: 2026, month: 8, day: 25)
        let careOne = ScheduledReminder(
            identifier: "care.due.one",
            title: "Night care",
            body: "Complete Night care.",
            categoryIdentifier: MomentumNotificationCategory.careDue,
            dateComponents: components(day, hour: 22, minute: 10),
            userInfo: ["kind": "careDue"]
        )
        let careTwo = ScheduledReminder(
            identifier: "care.due.two",
            title: "Hair care",
            body: "Complete Hair care.",
            categoryIdentifier: MomentumNotificationCategory.careDue,
            dateComponents: components(day, hour: 21, minute: 45),
            userInfo: ["kind": "careDue"]
        )

        let merged = ReminderBundler.bundle(
            [careOne, careTwo],
            anchorCategory: MomentumNotificationCategory.eveningCheckIn,
            fallbackAnchorDateComponents: components(day, hour: 22)
        )

        XCTAssertEqual(merged.count, 1)
        let evening = try XCTUnwrap(merged.first)
        XCTAssertEqual(evening.categoryIdentifier, MomentumNotificationCategory.eveningCheckIn)
        XCTAssertEqual(evening.title, "Evening check-in")
        // Fires no later than any folded candidate's own reminder.
        XCTAssertEqual(evening.dateComponents.hour, 21)
        XCTAssertEqual(evening.dateComponents.minute, 45)
        XCTAssertEqual(evening.body, "Complete Night care. Complete Hair care.")
    }

    func testCandidatesOutsideFallbackWindowStayUnmerged() {
        let day = DomainDay(year: 2026, month: 8, day: 25)
        let morning = ScheduledReminder(
            identifier: "care.due.morning",
            title: "Morning care",
            body: "Complete Morning care.",
            categoryIdentifier: MomentumNotificationCategory.careDue,
            dateComponents: components(day, hour: 9),
            userInfo: [:]
        )

        let result = ReminderBundler.bundle(
            [morning],
            anchorCategory: MomentumNotificationCategory.eveningCheckIn,
            fallbackAnchorDateComponents: components(day, hour: 22)
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.identifier, "care.due.morning")
    }

    func testModuleSetupLazilyCreatesDefaultsForLaterEnabledModules() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        context.insert(AppSettingsRecord())
        try context.save()

        try ModuleSetup.ensureDefaults(
            for: [BuiltInModuleID.hydration, BuiltInModuleID.nutrition],
            unitSystemRaw: "imperial",
            in: context
        )

        let plan = try XCTUnwrap(HydrationPlanService.plan(in: context))
        XCTAssertEqual(HydrationEngine.fluidOunces(fromML: plan.targetML), 85)

        let targets = try context.fetch(FetchDescriptor<NutritionTargetRecord>())
        XCTAssertEqual(targets.count, 1)
        XCTAssertNil(targets.first?.effectiveTo)

        // Idempotent on repeated enablement.
        try ModuleSetup.ensureDefaults(
            for: [BuiltInModuleID.hydration, BuiltInModuleID.nutrition],
            unitSystemRaw: "imperial",
            in: context
        )
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<HydrationPlanRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<NutritionTargetRecord>()), 1)
    }
}
