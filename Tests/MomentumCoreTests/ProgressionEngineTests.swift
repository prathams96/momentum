import Foundation
import XCTest
@testable import MomentumCore

final class ProgressionEngineTests: XCTestCase {
    private let prescriptionID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!

    func test_allPrescribedSetsAtTopOfRangeSuggestsIncrementAboveMaximumLoad() {
        let result = ProgressionEngine().suggestion(for: input(sets: [
            .init(weightKilograms: 50, repetitions: 10, status: .completed),
            .init(weightKilograms: 52.5, repetitions: 11, status: .completed),
            .init(weightKilograms: 50, repetitions: 10, status: .completed)
        ]))

        XCTAssertEqual(result, LoadSuggestion(
            prescriptionID: prescriptionID,
            suggestedWeightKilograms: 55
        ))
    }

    func test_oneSetBelowSnapshottedMaximumProducesNoSuggestion() {
        XCTAssertNil(ProgressionEngine().suggestion(for: input(sets: [
            .init(weightKilograms: 50, repetitions: 10, status: .completed),
            .init(weightKilograms: 50, repetitions: 9, status: .completed),
            .init(weightKilograms: 50, repetitions: 10, status: .completed)
        ])))
    }

    func test_skippedSetOrExerciseProducesNoSuggestion() {
        XCTAssertNil(ProgressionEngine().suggestion(for: input(sets: [
            .init(weightKilograms: 50, repetitions: 10, status: .completed),
            .init(weightKilograms: 50, repetitions: 10, status: .skipped),
            .init(weightKilograms: 50, repetitions: 10, status: .completed)
        ])))
        XCTAssertNil(ProgressionEngine().suggestion(for: input(
            exerciseStatus: .skipped,
            sets: [
                .init(weightKilograms: 50, repetitions: 10, status: .completed),
                .init(weightKilograms: 50, repetitions: 10, status: .completed),
                .init(weightKilograms: 50, repetitions: 10, status: .completed)
            ]
        )))
    }

    func test_missingOrExtraWorkingSetsProduceNoSuggestion() {
        let validSet = WorkingSetPerformance(
            weightKilograms: 50,
            repetitions: 10,
            status: .completed
        )
        XCTAssertNil(ProgressionEngine().suggestion(for: input(sets: [validSet, validSet])))
        XCTAssertNil(ProgressionEngine().suggestion(for: input(
            sets: [validSet, validSet, validSet, validSet]
        )))
    }

    func test_optionalExerciseAndNonPositiveIncrementProduceNoSuggestion() {
        let validSets = (0..<3).map { _ in
            WorkingSetPerformance(weightKilograms: 50, repetitions: 10, status: .completed)
        }
        XCTAssertNil(ProgressionEngine().suggestion(for: input(
            isOptional: true,
            sets: validSets
        )))
        XCTAssertNil(ProgressionEngine().suggestion(for: input(
            loadIncrementKilograms: 0,
            sets: validSets
        )))
    }

    private func input(
        isOptional: Bool = false,
        exerciseStatus: ExercisePerformanceStatus = .completed,
        loadIncrementKilograms: Decimal = 2.5,
        sets: [WorkingSetPerformance]
    ) -> ProgressionExerciseInput {
        ProgressionExerciseInput(
            prescriptionID: prescriptionID,
            isOptional: isOptional,
            exerciseStatus: exerciseStatus,
            prescribedWorkingSetCount: 3,
            repMaximumSnapshot: 10,
            loadIncrementKilograms: loadIncrementKilograms,
            workingSets: sets
        )
    }
}
