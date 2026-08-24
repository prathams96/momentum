import MomentumCore
import SwiftUI

/// Correction-sheet entry points owned by the History surface. Day-detail
/// sections receive these through the environment instead of holding
/// references back into HistoryView.
struct HistoryDayActions {
    let editFood: (FoodEntryRecord) -> Void
    let backdateFood: (FoodEntryRecord) -> Void
    let requestFoodDeletion: (FoodEntryRecord) -> Void
    let requestWorkoutDeletion: (WorkoutSessionRecord) -> Void
    let editWorkoutCompletion: (WorkoutSessionRecord) -> Void
    let toggleNutritionFinalization: (DomainDay) -> Void
    let requestCareCompletionUndo: (CareOccurrenceRecord) -> Void

    /// Fresh no-op value; closures are inert so this stays concurrency-safe.
    static var inactive: HistoryDayActions {
        HistoryDayActions(
            editFood: { _ in },
            backdateFood: { _ in },
            requestFoodDeletion: { _ in },
            requestWorkoutDeletion: { _ in },
            editWorkoutCompletion: { _ in },
            toggleNutritionFinalization: { _ in },
            requestCareCompletionUndo: { _ in }
        )
    }
}

private struct HistoryDayActionsKey: EnvironmentKey {
    static var defaultValue: HistoryDayActions { .inactive }
}

extension EnvironmentValues {
    var historyDayActions: HistoryDayActions {
        get { self[HistoryDayActionsKey.self] }
        set { self[HistoryDayActionsKey.self] = newValue }
    }
}
