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

    func testNutritionTargetSaveCreatesFutureOnlyEffectiveRecord() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        context.insert(NutritionTargetRecord(
            effectiveFrom: "2026-07-01",
            calorieDisplayTarget: 2_400,
            calorieMinimum: 2_300,
            calorieMaximum: 2_500,
            proteinMinimumGrams: 150
        ))
        try context.save()

        try NutritionPlanService.saveTarget(
            effectiveFrom: DomainDay(year: 2026, month: 8, day: 2),
            displayTarget: 2_600,
            calorieMinimum: 2_500,
            calorieMaximum: 2_700,
            proteinMinimum: 165,
            now: Date(timeIntervalSince1970: 200),
            in: context
        )

        let targets = try context.fetch(FetchDescriptor<NutritionTargetRecord>())
        XCTAssertEqual(targets.count, 2)
        XCTAssertEqual(targets.first { $0.effectiveFrom == "2026-07-01" }?.effectiveTo, "2026-08-01")
        let current = try XCTUnwrap(targets.first { $0.effectiveFrom == "2026-08-02" })
        XCTAssertEqual(current.calorieDisplayTarget, 2_600)
        XCTAssertEqual(current.proteinMinimumGrams, 165)
    }

    func testMeasurementServiceSupportsEditAndSoftDelete() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        let date = Date(timeIntervalSince1970: 1_775_275_200)

        try MeasurementService.save(
            existing: nil,
            kind: .waist,
            metricValue: 82.5,
            measuredAt: date,
            cutoffMinutes: 180,
            now: date,
            in: context
        )
        let measurement = try XCTUnwrap(context.fetch(FetchDescriptor<BodyMeasurementRecord>()).first)
        XCTAssertEqual(measurement.kindRaw, "waistCm")
        XCTAssertEqual(measurement.value, 82.5)

        try MeasurementService.save(
            existing: measurement,
            kind: .waist,
            metricValue: 81,
            measuredAt: date,
            cutoffMinutes: 180,
            now: date.addingTimeInterval(1),
            in: context
        )
        XCTAssertEqual(measurement.value, 81)

        try MeasurementService.delete(measurement, now: date.addingTimeInterval(2), in: context)
        XCTAssertNotNil(measurement.deletedAt)
    }

    func testAcceptingLoadSuggestionAppliesWorkingWeight() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        let prescription = ExercisePrescriptionRecord(
            workoutTemplateID: UUID(),
            displayName: "Squat",
            orderIndex: 0,
            workingSetCount: 3,
            repMinimum: 6,
            repMaximum: 8
        )
        let suggestion = LoadSuggestionRecord(
            prescriptionID: prescription.id,
            sourceSessionID: UUID(),
            suggestedWeightKg: 82.5
        )
        context.insert(prescription)
        context.insert(suggestion)
        try context.save()

        try LoadSuggestionService.accept(
            suggestion,
            weightKg: 80,
            prescriptions: [prescription],
            now: Date(timeIntervalSince1970: 300),
            in: context
        )

        XCTAssertEqual(prescription.workingWeightKg, 80)
        XCTAssertEqual(suggestion.suggestedWeightKg, 80)
        XCTAssertEqual(suggestion.statusRaw, "accepted")
        XCTAssertNotNil(suggestion.resolvedAt)
    }

    func testAppearanceResolverMapsPersistedValues() {
        XCTAssertNil(AppearanceResolver.colorScheme(for: "system"))
        XCTAssertEqual(AppearanceResolver.colorScheme(for: "light"), .light)
        XCTAssertEqual(AppearanceResolver.colorScheme(for: "dark"), .dark)
        XCTAssertNil(AppearanceResolver.colorScheme(for: "invalid"))
    }

    func testSevenDayWeightAverageAggregatesSameDayReadingsAndNeedsTwoDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dayOneMorning = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 8))!
        let dayOneEvening = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 20))!
        let dayTwo = calendar.date(from: DateComponents(year: 2026, month: 8, day: 2, hour: 8))!
        let points = [
            MeasurementPoint(id: UUID(), date: dayOneMorning, value: 80),
            MeasurementPoint(id: UUID(), date: dayOneEvening, value: 82),
            MeasurementPoint(id: UUID(), date: dayTwo, value: 84)
        ]

        let averages = WeightTrendProjection.sevenDayAverages(
            observations: points,
            calendar: calendar
        )

        XCTAssertEqual(averages.count, 1)
        XCTAssertEqual(averages[0].value, 82.5, accuracy: 0.001)
        XCTAssertEqual(averages[0].date, calendar.startOfDay(for: dayTwo))
    }

    func testCanonicalSettingsUsesIDAsDeterministicTimestampTieBreaker() {
        let timestamp = Date(timeIntervalSince1970: 100)
        let lower = AppSettingsRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            updatedAt: timestamp
        )
        let higher = AppSettingsRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            updatedAt: timestamp
        )

        XCTAssertEqual(AppSettingsRecord.canonical(in: [higher, lower])?.id, higher.id)
        XCTAssertEqual(AppSettingsRecord.canonical(in: [lower, higher])?.id, higher.id)
    }
}
