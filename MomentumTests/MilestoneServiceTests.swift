import MomentumCore
import SwiftData
import XCTest
@testable import Momentum

@MainActor
final class MilestoneServiceTests: XCTestCase {
    func testWorkoutThresholdsAreIdempotentAndCorrectionRemovesUnearnedThreshold() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var sessions = [WorkoutSessionRecord]()
        for index in 0..<10 {
            let session = completedSession(index: index, base: base)
            sessions.append(session)
            context.insert(session)
        }
        try context.save()

        try MilestoneService.reconcile(in: context, now: base.addingTimeInterval(1_000))
        let first = try context.fetch(FetchDescriptor<MilestoneRecord>())
            .filter { $0.kindRaw == MilestoneService.workoutCountKind }
        XCTAssertEqual(first.map(\.threshold), [10])
        let milestoneID = try XCTUnwrap(first.first?.id)

        try MilestoneService.reconcile(in: context, now: base.addingTimeInterval(2_000))
        let second = try context.fetch(FetchDescriptor<MilestoneRecord>())
            .filter { $0.kindRaw == MilestoneService.workoutCountKind }
        XCTAssertEqual(second.map(\.id), [milestoneID])

        sessions.last?.deletedAt = base.addingTimeInterval(3_000)
        sessions.last?.updatedAt = base.addingTimeInterval(3_000)
        try context.save()
        try MilestoneService.reconcile(in: context, now: base.addingTimeInterval(4_000))
        XCTAssertTrue(try context.fetch(FetchDescriptor<MilestoneRecord>())
            .filter { $0.kindRaw == MilestoneService.workoutCountKind }.isEmpty)
    }

    func testWorkoutCountGeneratesAllCrossedThresholds() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<50 { context.insert(completedSession(index: index, base: base)) }
        try context.save()

        try MilestoneService.reconcile(in: context, now: base.addingTimeInterval(10_000))

        let thresholds = try context.fetch(FetchDescriptor<MilestoneRecord>())
            .filter { $0.kindRaw == MilestoneService.workoutCountKind }
            .compactMap(\.threshold)
            .sorted()
        XCTAssertEqual(thresholds, [10, 25, 50])
    }

    func testCategoryStreakUsesTheAllTimeRecordAndReconcilesCorrection() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var sessions = [WorkoutSessionRecord]()
        for index in 0..<3 {
            let session = completedSession(index: index, base: base)
            sessions.append(session)
            context.insert(session)
        }
        context.insert(WorkoutDayEventRecord(
            domainDay: "2026-08-04",
            dueWorkoutTemplateID: UUID(),
            kindRaw: "missed",
            createdAt: base.addingTimeInterval(4_000)
        ))
        try context.save()

        try MilestoneService.reconcile(in: context, now: base.addingTimeInterval(5_000))
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<MilestoneRecord>())
                .first { $0.kindRaw == MilestoneService.workoutStreakKind }?.threshold,
            3
        )

        sessions[1].finishedAt = nil
        sessions[1].updatedAt = base.addingTimeInterval(6_000)
        context.insert(WorkoutDayEventRecord(
            domainDay: "2026-08-02",
            dueWorkoutTemplateID: UUID(),
            kindRaw: "missed",
            createdAt: base.addingTimeInterval(1_500)
        ))
        try context.save()
        try MilestoneService.reconcile(in: context, now: base.addingTimeInterval(7_000))
        XCTAssertTrue(try context.fetch(FetchDescriptor<MilestoneRecord>())
            .filter { $0.kindRaw == MilestoneService.workoutStreakKind }.isEmpty)
    }

    func testExerciseBestReplacesCorrectedBestWithoutDuplicates() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let prescriptionID = UUID()
        let session = completedSession(index: 0, base: base)
        let log = ExerciseLogRecord(
            workoutSessionID: session.id,
            prescriptionID: prescriptionID,
            exerciseNameSnapshot: "Squat",
            orderIndex: 0,
            setCountSnapshot: 1,
            repMinimumSnapshot: 5,
            repMaximumSnapshot: 8,
            statusRaw: "completed"
        )
        let set = SetLogRecord(
            exerciseLogID: log.id,
            setNumber: 1,
            weightKg: 50,
            repetitions: 8,
            statusRaw: "completed"
        )
        context.insert(session)
        context.insert(log)
        context.insert(set)
        try context.save()

        try MilestoneService.reconcile(in: context, now: base.addingTimeInterval(2_000))
        XCTAssertEqual(exerciseWeightMilestones(context).map(\.threshold), [50])

        set.weightKg = 45
        set.updatedAt = base.addingTimeInterval(3_000)
        try context.save()
        try MilestoneService.reconcile(in: context, now: base.addingTimeInterval(4_000))
        XCTAssertEqual(exerciseWeightMilestones(context).map(\.threshold), [45])
    }

    func testNutritionRangeRecordRequiresFinalizedConsecutiveDaysAndActiveEntries() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var entries = [FoodEntryRecord]()
        for index in 0..<2 {
            let day = "2026-08-0\(index + 1)"
            context.insert(NutritionDayRecord(
                domainDay: day,
                finalizedAt: base.addingTimeInterval(Double(index + 1) * 1_000),
                calorieMinimumSnapshot: 2_300,
                calorieMaximumSnapshot: 2_500,
                proteinMinimumSnapshot: 150
            ))
            let entry = FoodEntryRecord(
                domainDay: day,
                nameSnapshot: "Food",
                caloriesPerBaseServing: 2_400,
                proteinPerBaseServing: 160
            )
            entries.append(entry)
            context.insert(entry)
        }
        try context.save()

        try MilestoneService.reconcile(in: context, now: base.addingTimeInterval(3_000))
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<MilestoneRecord>())
                .first { $0.kindRaw == MilestoneService.nutritionRangeStreakKind }?.threshold,
            2
        )

        entries[0].deletedAt = base.addingTimeInterval(4_000)
        entries[0].updatedAt = base.addingTimeInterval(4_000)
        try context.save()
        try MilestoneService.reconcile(in: context, now: base.addingTimeInterval(5_000))
        XCTAssertTrue(try context.fetch(FetchDescriptor<MilestoneRecord>())
            .filter { $0.kindRaw == MilestoneService.nutritionRangeStreakKind }.isEmpty)
    }

    func testAcknowledgementPersistsAndNextReturnsOnlyUnacknowledged() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        let first = MilestoneRecord(kindRaw: MilestoneService.workoutCountKind, threshold: 10)
        let second = MilestoneRecord(
            kindRaw: MilestoneService.workoutCountKind,
            threshold: 25,
            earnedAt: first.earnedAt.addingTimeInterval(1)
        )
        context.insert(first)
        context.insert(second)
        try context.save()

        XCTAssertEqual(MilestoneService.nextUnacknowledged(in: [second, first])?.id, first.id)
        let acknowledgedAt = Date(timeIntervalSince1970: 1_800_000_000)
        try MilestoneService.acknowledge(first, now: acknowledgedAt, in: context)

        XCTAssertEqual(first.acknowledgedAt, acknowledgedAt)
        XCTAssertEqual(MilestoneService.nextUnacknowledged(in: [first, second])?.id, second.id)
    }

    private func completedSession(index: Int, base: Date) -> WorkoutSessionRecord {
        let date = base.addingTimeInterval(Double(index + 1) * 1_000)
        return WorkoutSessionRecord(
            workoutTemplateID: UUID(),
            workoutNameSnapshot: "Workout",
            scheduledDomainDay: String(format: "2026-08-%02d", index + 1),
            startedAt: date.addingTimeInterval(-600),
            finishedAt: date,
            completionDomainDay: String(format: "2026-08-%02d", index + 1),
            createdAt: date,
            updatedAt: date
        )
    }

    private func exerciseWeightMilestones(_ context: ModelContext) -> [MilestoneRecord] {
        ((try? context.fetch(FetchDescriptor<MilestoneRecord>())) ?? [])
            .filter { $0.kindRaw == MilestoneService.exerciseWeightBestKind }
    }
}
