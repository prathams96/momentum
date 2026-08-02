import XCTest
import MomentumCore
import SwiftData
@testable import Momentum

@MainActor
final class SettingsPersistenceTests: XCTestCase {
    func testDraftAppliesSettingsAndPerRoutineReminderTimes() {
        let settings = AppSettingsRecord()
        let routine = CareRoutineTemplateRecord(
            name: "Morning care",
            recurrencePayload: "weekdays:0,1,2,3,4,5,6",
            notificationMinutes: 9 * 60
        )
        let archived = CareRoutineTemplateRecord(
            name: "Archived",
            recurrencePayload: "weekdays:0",
            notificationMinutes: 10,
            isArchived: true
        )
        var draft = SettingsDraft(settings: settings, routines: [routine, archived])
        let updatedAt = Date(timeIntervalSince1970: 123)

        draft.domainDayCutoffMinutes = 240
        draft.unitSystemRaw = "imperial"
        draft.selectedAppearanceRaw = "dark"
        draft.workoutNotificationMinutes = 19 * 60
        draft.nutritionReminderMinutes = 21 * 60 + 30
        draft.routineReminders[0].minutes = 8 * 60 + 45
        draft.apply(to: settings, routines: [routine, archived], now: updatedAt)

        XCTAssertEqual(settings.domainDayCutoffMinutes, 240)
        XCTAssertEqual(settings.unitSystemRaw, "imperial")
        XCTAssertEqual(settings.selectedAppearanceRaw, "dark")
        XCTAssertEqual(settings.workoutNotificationMinutes, 19 * 60)
        XCTAssertEqual(settings.nutritionReminderMinutes, 21 * 60 + 30)
        XCTAssertEqual(settings.updatedAt, updatedAt)
        XCTAssertEqual(routine.notificationMinutes, 8 * 60 + 45)
        XCTAssertEqual(routine.updatedAt, updatedAt)
        XCTAssertEqual(archived.notificationMinutes, 10)
    }

    func testResetAllDataDeletesSeedAndHistoryRecords() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        try SeedData.install(
            in: context,
            currentDomainDay: DomainDay(year: 2026, month: 8, day: 2)
        )
        context.insert(WorkoutSessionRecord(
            workoutNameSnapshot: "Upper A",
            scheduledDomainDay: "2026-08-02"
        ))
        context.insert(FoodEntryRecord(
            domainDay: "2026-08-02",
            nameSnapshot: "Yogurt",
            caloriesPerBaseServing: 120,
            proteinPerBaseServing: 20
        ))
        context.insert(BodyMeasurementRecord(
            kindRaw: "weightKg",
            value: 80,
            domainDay: "2026-08-02"
        ))
        try context.save()

        try ResetAllDataService.reset(context: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AppSettingsRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutTemplateRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareRoutineTemplateRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSessionRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodEntryRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BodyMeasurementRecord>()), 0)
    }

    func testResetRequiresExactTypedPhrase() {
        XCTAssertEqual(ResetAllDataService.confirmationPhrase, "RESET ALL DATA")
        XCTAssertNotEqual(ResetAllDataService.confirmationPhrase, "reset all data")
    }
}
