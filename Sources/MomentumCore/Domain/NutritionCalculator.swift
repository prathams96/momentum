import Foundation

public struct NutritionTotals: Equatable, Sendable {
    public let calories: Decimal
    public let proteinGrams: Decimal

    public init(calories: Decimal, proteinGrams: Decimal) {
        self.calories = calories
        self.proteinGrams = proteinGrams
    }
}

public struct NutritionTargetRange: Equatable, Sendable {
    public let calorieMinimum: Decimal
    public let calorieMaximum: Decimal
    public let proteinMinimum: Decimal

    public init(
        calorieMinimum: Decimal,
        calorieMaximum: Decimal,
        proteinMinimum: Decimal
    ) {
        self.calorieMinimum = calorieMinimum
        self.calorieMaximum = calorieMaximum
        self.proteinMinimum = proteinMinimum
    }
}

public struct NutritionTargetEvaluation: Equatable, Sendable {
    public let caloriesWithinRange: Bool
    public let proteinMinimumMet: Bool

    public var meetsTarget: Bool {
        caloriesWithinRange && proteinMinimumMet
    }

    public init(caloriesWithinRange: Bool, proteinMinimumMet: Bool) {
        self.caloriesWithinRange = caloriesWithinRange
        self.proteinMinimumMet = proteinMinimumMet
    }
}

public enum NutritionCalculationError: Error, Equatable, Sendable {
    case negativeCalories
    case negativeProtein
    case nonPositiveServingMultiplier
    case invalidTargetRange
}

public struct NutritionCalculator: Sendable {
    public init() {}

    public func entryTotals(
        caloriesPerBaseServing: Decimal,
        proteinGramsPerBaseServing: Decimal,
        servingMultiplier: Decimal
    ) throws -> NutritionTotals {
        guard caloriesPerBaseServing >= 0 else {
            throw NutritionCalculationError.negativeCalories
        }
        guard proteinGramsPerBaseServing >= 0 else {
            throw NutritionCalculationError.negativeProtein
        }
        guard servingMultiplier > 0 else {
            throw NutritionCalculationError.nonPositiveServingMultiplier
        }

        return NutritionTotals(
            calories: caloriesPerBaseServing * servingMultiplier,
            proteinGrams: proteinGramsPerBaseServing * servingMultiplier
        )
    }

    public func evaluate(
        totals: NutritionTotals,
        against target: NutritionTargetRange
    ) throws -> NutritionTargetEvaluation {
        guard target.calorieMinimum >= 0,
              target.calorieMaximum >= target.calorieMinimum,
              target.proteinMinimum >= 0 else {
            throw NutritionCalculationError.invalidTargetRange
        }

        return NutritionTargetEvaluation(
            caloriesWithinRange: totals.calories >= target.calorieMinimum
                && totals.calories <= target.calorieMaximum,
            proteinMinimumMet: totals.proteinGrams >= target.proteinMinimum
        )
    }

    public func dayTotals(entries: [NutritionTotals]) -> NutritionTotals {
        entries.reduce(NutritionTotals(calories: 0, proteinGrams: 0)) { result, entry in
            NutritionTotals(
                calories: result.calories + entry.calories,
                proteinGrams: result.proteinGrams + entry.proteinGrams
            )
        }
    }
}
