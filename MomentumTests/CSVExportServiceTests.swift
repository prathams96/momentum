import XCTest
import SwiftData
@testable import Momentum

@MainActor
final class CSVExportServiceTests: XCTestCase {
    func testExportsFiveUTF8RFC4180FilesWithStableFormatting() async throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        let timestamp = Date(timeIntervalSince1970: 0)
        let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let session = WorkoutSessionRecord(
            id: sessionID,
            workoutNameSnapshot: "Bench, \"Press\"\nHeavy",
            scheduledDomainDay: "2026-08-02",
            startedAt: timestamp,
            finishedAt: timestamp,
            completionDomainDay: "2026-08-02",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let exercise = ExerciseLogRecord(
            workoutSessionID: session.id,
            exerciseNameSnapshot: "Bench Press",
            orderIndex: 0,
            setCountSnapshot: 1,
            repMinimumSnapshot: 6,
            repMaximumSnapshot: 8,
            statusRaw: "completed",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let set = SetLogRecord(
            exerciseLogID: exercise.id,
            setNumber: 1,
            weightKg: 62.5,
            repetitions: 8,
            rir: 2,
            statusRaw: "completed",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let food = FoodEntryRecord(
            domainDay: "2026-08-02",
            consumedAt: timestamp,
            nameSnapshot: "Yogurt, plain",
            caloriesPerBaseServing: 120.25,
            proteinPerBaseServing: 20,
            servingMultiplier: 1.5,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let measurement = BodyMeasurementRecord(
            kindRaw: "weightKg",
            value: 80.5,
            measuredAt: timestamp,
            domainDay: "2026-08-02",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let occurrence = CareOccurrenceRecord(
            routineNameSnapshot: "Morning care",
            dueDomainDay: "2026-08-02",
            dueAt: timestamp,
            statusRaw: "completed",
            completedAt: timestamp,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        context.insert(session)
        context.insert(exercise)
        context.insert(set)
        context.insert(food)
        context.insert(measurement)
        context.insert(occurrence)
        try context.save()

        let snapshot = try CSVExportSnapshot(context: context)
        let baseDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MomentumCSVExportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let files = try await Task.detached {
            try CSVExportService(baseDirectory: baseDirectory).export(snapshot)
        }.value

        XCTAssertEqual(Set(files.map(\.name)), Set([
            "workouts.csv", "food.csv", "measurements.csv", "care.csv", "adherence.csv"
        ]))

        let workoutURL = try XCTUnwrap(files.first { $0.name == "workouts.csv" }?.url)
        let workoutData = try Data(contentsOf: workoutURL)
        let workoutCSV = try XCTUnwrap(String(data: workoutData, encoding: .utf8))
        XCTAssertTrue(workoutCSV.contains("\r\n"))
        XCTAssertTrue(workoutCSV.contains("\"Bench, \"\"Press\"\"\nHeavy\""))
        XCTAssertTrue(workoutCSV.contains("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
        XCTAssertTrue(workoutCSV.contains("1970-01-01T00:00:00.000Z"))
        XCTAssertTrue(workoutCSV.contains(",62.5,8,2,"))

        let foodURL = try XCTUnwrap(files.first { $0.name == "food.csv" }?.url)
        let foodCSV = try String(contentsOf: foodURL, encoding: .utf8)
        XCTAssertTrue(foodCSV.contains("\"Yogurt, plain\""))
        XCTAssertTrue(foodCSV.contains("120.25"))
        XCTAssertFalse(foodCSV.contains("120,25"))

        let adherenceURL = try XCTUnwrap(files.first { $0.name == "adherence.csv" }?.url)
        let adherenceCSV = try String(contentsOf: adherenceURL, encoding: .utf8)
        XCTAssertTrue(adherenceCSV.contains("2026-08-02"))
        XCTAssertTrue(adherenceCSV.contains("care;workout"))
    }

    func testCleanupRemovesOnlyStaleExports() throws {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.temporaryDirectory
            .appending(path: "MomentumCSVCleanupTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let stale = baseDirectory.appending(path: "stale", directoryHint: .isDirectory)
        let recent = baseDirectory.appending(path: "recent", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: baseDirectory) }
        try fileManager.createDirectory(at: stale, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: recent, withIntermediateDirectories: true)
        try fileManager.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000)],
            ofItemAtPath: stale.path()
        )

        let now = Date(timeIntervalSince1970: 100_000)
        try CSVExportService(baseDirectory: baseDirectory, now: { now })
            .cleanupStaleExports(olderThan: 24 * 60 * 60)

        XCTAssertFalse(fileManager.fileExists(atPath: stale.path()))
        XCTAssertTrue(fileManager.fileExists(atPath: recent.path()))
    }

    func testEscapingLeavesSimpleValuesAloneAndQuotesSpecialValues() {
        XCTAssertEqual(CSVExportService.escape("simple"), "simple")
        XCTAssertEqual(CSVExportService.escape("a,b"), "\"a,b\"")
        XCTAssertEqual(CSVExportService.escape("a\"b"), "\"a\"\"b\"")
        XCTAssertEqual(CSVExportService.escape("a\nb"), "\"a\nb\"")
        XCTAssertEqual(CSVExportService.escape("a\r\nb"), "\"a\r\nb\"")
    }
}
