import XCTest
import MomentumCore
import SwiftData
@testable import Momentum

@MainActor
final class MomentumAppTests: XCTestCase {
    func testPreviewContainerUsesTheV1Schema() throws {
        let container = try ModelContainerFactory.makePreview()

        XCTAssertNotNil(container)
    }

    func testLocalDevelopmentContainerPersistsFactsAcrossReload() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MomentumLocal-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let container = try ModelContainerFactory.makeLocalDevelopment(at: url)
            let context = container.mainContext
            try SeedData.install(
                in: context,
                currentDomainDay: DomainDay(year: 2026, month: 8, day: 2)
            )
            context.insert(FoodEntryRecord(
                domainDay: "2026-08-02",
                nameSnapshot: "Reloadable food",
                caloriesPerBaseServing: 100,
                proteinPerBaseServing: 10
            ))
            try context.save()
        }

        let reloaded = try ModelContainerFactory.makeLocalDevelopment(at: url)
        XCTAssertEqual(
            try reloaded.mainContext.fetchCount(FetchDescriptor<FoodEntryRecord>()),
            1
        )
        XCTAssertEqual(
            try reloaded.mainContext.fetch(FetchDescriptor<AppSettingsRecord>()).count,
            1
        )
    }

    func testSeedDataIsIdempotentAndContainsCanonicalRoutines() throws {
        let container = try ModelContainerFactory.makePreview()
        try SeedData.install(
            in: container.mainContext,
            currentDomainDay: DomainDay(year: 2026, month: 8, day: 2)
        )
        try SeedData.install(
            in: container.mainContext,
            currentDomainDay: DomainDay(year: 2026, month: 8, day: 3)
        )

        let workouts = try container.mainContext.fetch(FetchDescriptor<WorkoutTemplateRecord>())
        let routines = try container.mainContext.fetch(FetchDescriptor<CareRoutineTemplateRecord>())
        let settings = try container.mainContext.fetch(FetchDescriptor<AppSettingsRecord>())

        XCTAssertEqual(workouts.count, 4)
        XCTAssertEqual(routines.count, 5)
        XCTAssertEqual(settings.count, 1)
        XCTAssertEqual(settings.first?.seedVersion, SeedData.currentVersion)
        XCTAssertTrue(routines.allSatisfy { routine in
            !routine.name.localizedCaseInsensitiveContains("pilgrim") &&
            !routine.name.localizedCaseInsensitiveContains("conscious chemist")
        })
        XCTAssertTrue(routines.allSatisfy { routine in
            guard let data = routine.recurrencePayload.data(using: .utf8) else { return false }
            return (try? JSONDecoder().decode(CareRecurrencePayload.self, from: data)) != nil
        })

        let lowerB = try XCTUnwrap(workouts.first { $0.name == "Lower B" })
        let sidePlank = try XCTUnwrap(
            try container.mainContext.fetch(FetchDescriptor<ExercisePrescriptionRecord>())
                .first { $0.workoutTemplateID == lowerB.id && $0.displayName == "Side Plank or Pallof Press" }
        )
        XCTAssertEqual(sidePlank.repUnitRaw, "seconds")
    }

    func testHistoryNutritionCareAndMeasurementRecordsRoundTrip() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        let workoutTemplateID = UUID()
        let prescriptionID = UUID()

        let target = NutritionTargetRecord(effectiveFrom: "2026-08-02")
        let session = WorkoutSessionRecord(
            workoutTemplateID: workoutTemplateID,
            workoutNameSnapshot: "Upper A",
            focusSnapshot: "Upper body",
            sequenceIndexSnapshot: 0,
            scheduledDomainDay: "2026-08-02"
        )
        let exercise = ExerciseLogRecord(
            workoutSessionID: session.id,
            prescriptionID: prescriptionID,
            exerciseNameSnapshot: "Bench Press",
            orderIndex: 0,
            setCountSnapshot: 3,
            repMinimumSnapshot: 6,
            repMaximumSnapshot: 8
        )
        let set = SetLogRecord(
            exerciseLogID: exercise.id,
            setNumber: 1,
            weightKg: 60,
            repetitions: 8,
            rir: 2,
            statusRaw: "completed"
        )
        let workoutEvent = WorkoutDayEventRecord(
            domainDay: "2026-08-01",
            dueWorkoutTemplateID: workoutTemplateID,
            kindRaw: "missed"
        )
        let suggestion = LoadSuggestionRecord(
            prescriptionID: prescriptionID,
            sourceSessionID: session.id,
            suggestedWeightKg: 62.5
        )

        let preset = FoodPresetRecord(
            name: "Greek yogurt",
            caloriesPerBaseServing: 120,
            proteinGramsPerBaseServing: 20,
            isFavorite: true
        )
        let foodEntry = FoodEntryRecord(
            domainDay: "2026-08-02",
            presetID: preset.id,
            nameSnapshot: preset.name,
            caloriesPerBaseServing: preset.caloriesPerBaseServing,
            proteinPerBaseServing: preset.proteinGramsPerBaseServing,
            servingMultiplier: 1.5,
            totalCalories: 0,
            totalProteinGrams: 0
        )
        foodEntry.recomputeTotals()
        let nutritionDay = NutritionDayRecord(domainDay: "2026-08-02")

        let routineID = UUID()
        let taskID = UUID()
        let occurrence = CareOccurrenceRecord(
            routineTemplateID: routineID,
            routineNameSnapshot: "Morning care",
            dueDomainDay: "2026-08-02",
            dueAt: .now
        )
        let completion = CareTaskCompletionRecord(
            occurrenceID: occurrence.id,
            taskTemplateID: taskID,
            labelSnapshot: "Cleanse"
        )
        let measurement = BodyMeasurementRecord(
            kindRaw: "weightKg",
            value: 80.5,
            domainDay: "2026-08-02"
        )
        let milestone = MilestoneRecord(
            kindRaw: "workoutCount",
            threshold: 10,
            relatedEntityID: workoutTemplateID
        )

        context.insert(target)
        context.insert(session)
        context.insert(exercise)
        context.insert(set)
        context.insert(workoutEvent)
        context.insert(suggestion)
        context.insert(preset)
        context.insert(foodEntry)
        context.insert(nutritionDay)
        context.insert(occurrence)
        context.insert(completion)
        context.insert(measurement)
        context.insert(milestone)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<NutritionTargetRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSessionRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseLogRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetLogRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutDayEventRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LoadSuggestionRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodPresetRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodEntryRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<NutritionDayRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareOccurrenceRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CareTaskCompletionRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BodyMeasurementRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MilestoneRecord>()), 1)

        let fetchedFood = try XCTUnwrap(context.fetch(FetchDescriptor<FoodEntryRecord>()).first)
        XCTAssertEqual(fetchedFood.totalCalories, 180, accuracy: 0.001)
        XCTAssertEqual(fetchedFood.totalProteinGrams, 30, accuracy: 0.001)
    }

    func testStartingWorkoutCreatesSnapshotLogsAndDraftSets() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        let day = DomainDay(year: 2026, month: 8, day: 2)
        try SeedData.install(in: context, currentDomainDay: day)

        let workouts = try context.fetch(FetchDescriptor<WorkoutTemplateRecord>()).sorted { $0.sequenceIndex < $1.sequenceIndex }
        let workout = try XCTUnwrap(workouts.first)
        let exercises = try context.fetch(FetchDescriptor<ExercisePrescriptionRecord>())
            .filter { $0.workoutTemplateID == workout.id }
        let nextWorkoutID = try XCTUnwrap(workouts.dropFirst().first?.id)

        let sessionID = try WorkoutSessionStarter.start(
            workout: workout,
            exercises: exercises,
            nextWorkoutTemplateID: nextWorkoutID,
            scheduledDomainDay: day,
            currentDomainDay: day,
            now: Date(timeIntervalSince1970: 10),
            in: context
        )

        let session = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutSessionRecord>()).first { $0.id == sessionID })
        XCTAssertEqual(session.workoutNameSnapshot, workout.name)
        XCTAssertEqual(session.nextWorkoutTemplateIDSnapshot, nextWorkoutID)
        XCTAssertEqual(session.scheduledDomainDay, "2026-08-02")
        XCTAssertFalse(session.startedEarly)

        let logs = try context.fetch(FetchDescriptor<ExerciseLogRecord>()).filter { $0.workoutSessionID == sessionID }
        XCTAssertEqual(logs.count, exercises.count)
        let sets = try context.fetch(FetchDescriptor<SetLogRecord>())
        XCTAssertEqual(sets.count, exercises.reduce(0) { $0 + $1.workingSetCount })
        XCTAssertTrue(sets.allSatisfy { $0.statusRaw == "pending" })
    }

    func testStartingSecondWorkoutIsRejectedWhileOneIsOpen() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        let day = DomainDay(year: 2026, month: 8, day: 2)
        try SeedData.install(in: context, currentDomainDay: day)
        let workouts = try context.fetch(FetchDescriptor<WorkoutTemplateRecord>()).sorted { $0.sequenceIndex < $1.sequenceIndex }
        let workout = try XCTUnwrap(workouts.first)
        let exercises = try context.fetch(FetchDescriptor<ExercisePrescriptionRecord>()).filter { $0.workoutTemplateID == workout.id }

        _ = try WorkoutSessionStarter.start(
            workout: workout,
            exercises: exercises,
            nextWorkoutTemplateID: workouts.dropFirst().first?.id,
            scheduledDomainDay: day,
            currentDomainDay: day,
            in: context
        )

        XCTAssertThrowsError(try WorkoutSessionStarter.start(
            workout: workout,
            exercises: exercises,
            nextWorkoutTemplateID: workouts.dropFirst().first?.id,
            scheduledDomainDay: day,
            currentDomainDay: day,
            in: context
        )) { error in
            guard case .openSessionExists = error as? WorkoutSessionStartError else {
                return XCTFail("Expected an open-session error, got \(error)")
            }
        }
    }

    func testDailyReconcilerRecordsOneMissedWorkoutAndIsIdempotent() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        let dueDay = DomainDay(year: 2026, month: 8, day: 2)
        try SeedData.install(in: context, currentDomainDay: dueDay)
        let anchor = try XCTUnwrap(context.fetch(FetchDescriptor<CycleAnchorRecord>()).first)
        anchor.firstDueDomainDay = PersistedDomainDay.encode(dueDay)
        try context.save()

        let now = PersistedDomainDay.date(for: DomainDay(year: 2026, month: 8, day: 3), calendar: .autoupdatingCurrent, hour: 12)!
        try DailyReconciler.reconcile(in: context, now: now)
        try DailyReconciler.reconcile(in: context, now: now)

        let events = try context.fetch(FetchDescriptor<WorkoutDayEventRecord>())
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kindRaw, "missed")
        XCTAssertEqual(events.first?.domainDay, "2026-08-02")
    }

    func testDailyReconcilerRecordsEveryElapsedDueWorkoutOpportunity() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        let dueDay = DomainDay(year: 2026, month: 8, day: 2)
        try SeedData.install(in: context, currentDomainDay: dueDay)
        let anchor = try XCTUnwrap(context.fetch(FetchDescriptor<CycleAnchorRecord>()).first)
        anchor.firstDueDomainDay = PersistedDomainDay.encode(dueDay)
        try context.save()

        let now = PersistedDomainDay.date(
            for: DomainDay(year: 2026, month: 8, day: 5),
            calendar: .autoupdatingCurrent,
            hour: 12
        )!
        try DailyReconciler.reconcile(in: context, now: now)
        try DailyReconciler.reconcile(in: context, now: now)

        let events = try context.fetch(FetchDescriptor<WorkoutDayEventRecord>())
            .filter { $0.kindRaw == "missed" }
            .sorted { $0.domainDay < $1.domainDay }
        XCTAssertEqual(events.map(\.domainDay), ["2026-08-02", "2026-08-03", "2026-08-04"])
    }

    func testDailyReconcilerRecordsMissesWhenOpenSessionCrossesCutoff() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        let dueDay = DomainDay(year: 2026, month: 8, day: 2)
        try SeedData.install(in: context, currentDomainDay: dueDay)
        let anchor = try XCTUnwrap(context.fetch(FetchDescriptor<CycleAnchorRecord>()).first)
        let workout = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkoutTemplateRecord>())
                .first { $0.id == anchor.nextWorkoutTemplateID }
        )
        context.insert(WorkoutSessionRecord(
            workoutTemplateID: workout.id,
            workoutNameSnapshot: workout.name,
            focusSnapshot: workout.focus,
            sequenceIndexSnapshot: workout.sequenceIndex,
            scheduledDomainDay: "2026-08-02",
            startedAt: PersistedDomainDay.date(for: dueDay, calendar: .autoupdatingCurrent, hour: 18)!
        ))
        try context.save()

        let now = PersistedDomainDay.date(
            for: DomainDay(year: 2026, month: 8, day: 4),
            calendar: .autoupdatingCurrent,
            hour: 12
        )!
        try DailyReconciler.reconcile(in: context, now: now)

        let events = try context.fetch(FetchDescriptor<WorkoutDayEventRecord>())
            .filter { $0.kindRaw == "missed" }
            .sorted { $0.domainDay < $1.domainDay }
        XCTAssertEqual(events.map(\.domainDay), ["2026-08-02", "2026-08-03"])
    }

    func testDailyReconcilerKeepsDeterministicCompletedOccurrenceSurvivor() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        let routineID = UUID()
        let day = DomainDay(year: 2026, month: 8, day: 2)
        let dueAt = PersistedDomainDay.date(for: day, calendar: .autoupdatingCurrent, hour: 9)!
        let completedID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let pendingID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        context.insert(CareOccurrenceRecord(
            id: pendingID,
            routineTemplateID: routineID,
            routineNameSnapshot: "Morning care",
            dueDomainDay: "2026-08-02",
            dueAt: dueAt,
            createdAt: Date(timeIntervalSince1970: 1)
        ))
        context.insert(CareOccurrenceRecord(
            id: completedID,
            routineTemplateID: routineID,
            routineNameSnapshot: "Morning care",
            dueDomainDay: "2026-08-02",
            dueAt: dueAt,
            statusRaw: "completed",
            completedAt: dueAt,
            createdAt: Date(timeIntervalSince1970: 2)
        ))
        try context.save()

        let now = PersistedDomainDay.date(for: day, calendar: .autoupdatingCurrent, hour: 12)!
        try DailyReconciler.reconcile(in: context, now: now)

        let occurrences = try context.fetch(FetchDescriptor<CareOccurrenceRecord>())
        XCTAssertEqual(occurrences.first { $0.id == completedID }?.statusRaw, "completed")
        XCTAssertEqual(occurrences.first { $0.id == pendingID }?.statusRaw, "repairedDuplicate")
    }

    func testDailyReconcilerDoesNotMergePostWorkoutCareFromDifferentSessions() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        let day = DomainDay(year: 2026, month: 8, day: 2)
        let dueAt = PersistedDomainDay.date(for: day, calendar: .autoupdatingCurrent, hour: 18)!
        for sourceID in [UUID(), UUID()] {
            context.insert(CareOccurrenceRecord(
                routineNameSnapshot: "Post-workout care",
                routineRoleRaw: "postWorkout",
                sourceWorkoutSessionID: sourceID,
                dueDomainDay: "2026-08-02",
                dueAt: dueAt
            ))
        }
        try context.save()

        let now = PersistedDomainDay.date(for: day, calendar: .autoupdatingCurrent, hour: 20)!
        try DailyReconciler.reconcile(in: context, now: now)

        let occurrences = try context.fetch(FetchDescriptor<CareOccurrenceRecord>())
            .filter { $0.routineRoleRaw == "postWorkout" }
        XCTAssertEqual(occurrences.count, 2)
        XCTAssertTrue(occurrences.allSatisfy { $0.statusRaw == "pending" })
    }

    func testExplicitWorkoutSkipPreventsMissedEvent() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        let dueDay = DomainDay(year: 2026, month: 8, day: 2)
        try SeedData.install(in: context, currentDomainDay: dueDay)
        let anchor = try XCTUnwrap(context.fetch(FetchDescriptor<CycleAnchorRecord>()).first)
        anchor.firstDueDomainDay = PersistedDomainDay.encode(dueDay)
        let workoutID = anchor.nextWorkoutTemplateID
        context.insert(WorkoutDayEventRecord(
            domainDay: PersistedDomainDay.encode(dueDay),
            dueWorkoutTemplateID: workoutID,
            kindRaw: "skipped"
        ))
        try context.save()

        let now = PersistedDomainDay.date(for: DomainDay(year: 2026, month: 8, day: 3), calendar: .autoupdatingCurrent, hour: 12)!
        try DailyReconciler.reconcile(in: context, now: now)

        let events = try context.fetch(FetchDescriptor<WorkoutDayEventRecord>())
        XCTAssertEqual(events.map(\.kindRaw), ["skipped"])
    }

    func testReminderDeriverUsesStableWorkoutAndEveningIdentifiers() throws {
        let settings = AppSettingsRecord(
            domainDayCutoffMinutes: 180,
            workoutNotificationMinutes: 18 * 60,
            nutritionReminderMinutes: 22 * 60
        )
        let now = PersistedDomainDay.date(
            for: DomainDay(year: 2026, month: 8, day: 2),
            calendar: .autoupdatingCurrent,
            hour: 12
        )!
        let workoutID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let reminders = ReminderDeriver.reminders(
            scheduleState: .due(
                workoutID: workoutID,
                dueDay: DomainDay(year: 2026, month: 8, day: 2),
                overdueBy: 0
            ),
            settings: settings,
            occurrences: [],
            nutritionDay: NutritionDayRecord(domainDay: "2026-08-02"),
            now: now,
            calendar: .autoupdatingCurrent
        )

        XCTAssertEqual(
            reminders.map(\.identifier),
            ["workout.\(workoutID.uuidString).2026-08-02", "evening.2026-08-02"]
        )
    }

    func testOverdueWorkoutReminderRepresentsCurrentOpportunity() throws {
        let settings = AppSettingsRecord(
            domainDayCutoffMinutes: 180,
            workoutNotificationMinutes: 18 * 60
        )
        let currentDay = DomainDay(year: 2026, month: 8, day: 4)
        let now = PersistedDomainDay.date(
            for: currentDay,
            calendar: .autoupdatingCurrent,
            hour: 12
        )!
        let workoutID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

        let reminders = ReminderDeriver.reminders(
            scheduleState: .due(
                workoutID: workoutID,
                dueDay: DomainDay(year: 2026, month: 8, day: 2),
                overdueBy: 2
            ),
            settings: settings,
            occurrences: [],
            nutritionDay: NutritionDayRecord(domainDay: "2026-08-04", finalizedAt: now),
            now: now,
            calendar: .autoupdatingCurrent
        )

        let workout = try XCTUnwrap(reminders.first { $0.categoryIdentifier == MomentumNotificationCategory.workoutDue })
        XCTAssertEqual(workout.identifier, "workout.\(workoutID.uuidString).2026-08-04")
        XCTAssertEqual(workout.userInfo["domainDay"], "2026-08-04")
    }

    func testWorkoutNotificationRouteCarriesTargetAndCurrentOpportunityDay() throws {
        let workoutID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let route = try XCTUnwrap(WorkoutNotificationRoute(userInfo: [
            "workoutID": workoutID.uuidString,
            "domainDay": "2026-08-04"
        ]))

        XCTAssertEqual(route.workoutID, workoutID)
        XCTAssertEqual(route.domainDay, DomainDay(year: 2026, month: 8, day: 4))
    }

    func testNightCareAndOpenNutritionAtSameTimeCoalesceIntoOneEveningReminder() throws {
        let settings = AppSettingsRecord(
            domainDayCutoffMinutes: 180,
            nutritionReminderMinutes: 22 * 60
        )
        let day = DomainDay(year: 2026, month: 8, day: 2)
        let now = PersistedDomainDay.date(for: day, calendar: .autoupdatingCurrent, hour: 12)!
        let dueAt = PersistedDomainDay.date(for: day, calendar: .autoupdatingCurrent, hour: 22)!
        let occurrence = CareOccurrenceRecord(
            routineNameSnapshot: "Editable night routine",
            routineRoleRaw: "night",
            dueDomainDay: "2026-08-02",
            dueAt: dueAt
        )

        let reminders = ReminderDeriver.reminders(
            scheduleState: .needsRepair(reason: .missingAnchorWorkout),
            settings: settings,
            occurrences: [occurrence],
            nutritionDay: nil,
            now: now,
            calendar: .autoupdatingCurrent
        )

        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders.first?.categoryIdentifier, MomentumNotificationCategory.eveningCheckIn)
        XCTAssertEqual(reminders.first?.userInfo["occurrenceID"], occurrence.id.uuidString)
    }

    func testCompletingAlternatingCareFromNotificationAdvancesRecurrence() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        let completionDay = DomainDay(year: 2026, month: 8, day: 2)
        let originalPayload = CareRecurrencePayload(rule: .alternating(
            anchorDueDay: completionDay,
            intervals: [3, 4],
            intervalAfterAnchorIndex: 0
        ))
        let originalData = try JSONEncoder().encode(originalPayload)
        let originalValue = try XCTUnwrap(String(data: originalData, encoding: .utf8))
        let routine = CareRoutineTemplateRecord(
            name: "Hair care",
            routineRoleRaw: "hair",
            recurrenceKindRaw: "alternatingInterval",
            recurrencePayload: originalValue,
            notificationMinutes: 8 * 60,
            rollsForwardWhenMissed: true
        )
        let dueAt = PersistedDomainDay.date(for: completionDay, calendar: .autoupdatingCurrent, hour: 8)!
        let occurrence = CareOccurrenceRecord(
            routineTemplateID: routine.id,
            routineNameSnapshot: routine.name,
            routineRoleRaw: routine.routineRoleRaw,
            dueDomainDay: "2026-08-02",
            dueAt: dueAt
        )
        let task = CareTaskCompletionRecord(
            occurrenceID: occurrence.id,
            labelSnapshot: "Wash scalp"
        )
        context.insert(routine)
        context.insert(occurrence)
        context.insert(task)
        try context.save()

        let changed = try DailyReconciler.completeCareOccurrence(
            occurrenceID: occurrence.id,
            in: context,
            now: dueAt,
            calendar: .autoupdatingCurrent
        )
        let repeated = try DailyReconciler.completeCareOccurrence(
            occurrenceID: occurrence.id,
            in: context,
            now: dueAt.addingTimeInterval(60),
            calendar: .autoupdatingCurrent
        )

        XCTAssertTrue(changed)
        XCTAssertFalse(repeated)
        XCTAssertEqual(occurrence.statusRaw, "completed")
        XCTAssertEqual(task.statusRaw, "completed")
        XCTAssertEqual(occurrence.recurrencePayloadBeforeCompletion, originalValue)
        let advancedData = try XCTUnwrap(routine.recurrencePayload.data(using: .utf8))
        let advanced = try JSONDecoder().decode(CareRecurrencePayload.self, from: advancedData)
        XCTAssertEqual(advanced.rule, .alternating(
            anchorDueDay: DomainDay(year: 2026, month: 8, day: 5),
            intervals: [3, 4],
            intervalAfterAnchorIndex: 1
        ))
    }

    func testNutritionDayFinalizationSnapshotsTargetAndCanReopen() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        let day = DomainDay(year: 2026, month: 8, day: 2)
        let target = NutritionTargetRecord(
            effectiveFrom: "2026-08-02",
            calorieDisplayTarget: 2_400,
            calorieMinimum: 2_300,
            calorieMaximum: 2_500,
            proteinMinimumGrams: 150
        )
        context.insert(target)

        try NutritionDayService.finalize(
            domainDay: day,
            target: target,
            existing: nil,
            context: context,
            now: Date(timeIntervalSince1970: 100)
        )

        let finalized = try XCTUnwrap(context.fetch(FetchDescriptor<NutritionDayRecord>()).first)
        XCTAssertEqual(finalized.calorieMinimumSnapshot, 2_300)
        XCTAssertEqual(finalized.proteinMinimumSnapshot, 150)
        XCTAssertNotNil(finalized.finalizedAt)

        try NutritionDayService.reopen(existing: finalized, context: context)
        XCTAssertNil(finalized.finalizedAt)
    }
}
