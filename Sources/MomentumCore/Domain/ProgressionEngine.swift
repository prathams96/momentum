import Foundation

public enum ExercisePerformanceStatus: Equatable, Sendable {
    case completed
    case skipped
}

public enum WorkingSetStatus: Equatable, Sendable {
    case completed
    case skipped
}

public struct WorkingSetPerformance: Equatable, Sendable {
    public let weightKilograms: Decimal
    public let repetitions: Int
    public let status: WorkingSetStatus

    public init(
        weightKilograms: Decimal,
        repetitions: Int,
        status: WorkingSetStatus
    ) {
        self.weightKilograms = weightKilograms
        self.repetitions = repetitions
        self.status = status
    }
}

public struct ProgressionExerciseInput: Equatable, Sendable {
    public let prescriptionID: UUID
    public let isOptional: Bool
    public let exerciseStatus: ExercisePerformanceStatus
    public let prescribedWorkingSetCount: Int
    public let repMaximumSnapshot: Int
    public let loadIncrementKilograms: Decimal
    public let workingSets: [WorkingSetPerformance]

    public init(
        prescriptionID: UUID,
        isOptional: Bool,
        exerciseStatus: ExercisePerformanceStatus,
        prescribedWorkingSetCount: Int,
        repMaximumSnapshot: Int,
        loadIncrementKilograms: Decimal,
        workingSets: [WorkingSetPerformance]
    ) {
        self.prescriptionID = prescriptionID
        self.isOptional = isOptional
        self.exerciseStatus = exerciseStatus
        self.prescribedWorkingSetCount = prescribedWorkingSetCount
        self.repMaximumSnapshot = repMaximumSnapshot
        self.loadIncrementKilograms = loadIncrementKilograms
        self.workingSets = workingSets
    }
}

public struct LoadSuggestion: Equatable, Sendable {
    public let prescriptionID: UUID
    public let suggestedWeightKilograms: Decimal

    public init(prescriptionID: UUID, suggestedWeightKilograms: Decimal) {
        self.prescriptionID = prescriptionID
        self.suggestedWeightKilograms = suggestedWeightKilograms
    }
}

public struct ProgressionEngine: Sendable {
    public init() {}

    public func suggestion(for input: ProgressionExerciseInput) -> LoadSuggestion? {
        guard !input.isOptional,
              input.exerciseStatus == .completed,
              input.prescribedWorkingSetCount > 0,
              input.repMaximumSnapshot > 0,
              input.loadIncrementKilograms > 0,
              input.workingSets.count == input.prescribedWorkingSetCount,
              input.workingSets.allSatisfy({
                  $0.status == .completed
                      && $0.repetitions >= input.repMaximumSnapshot
                      && $0.weightKilograms >= 0
              }),
              let maximumWeight = input.workingSets.map(\.weightKilograms).max()
        else {
            return nil
        }

        return LoadSuggestion(
            prescriptionID: input.prescriptionID,
            suggestedWeightKilograms: maximumWeight + input.loadIncrementKilograms
        )
    }
}
