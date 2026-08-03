import Foundation
import XCTest
@testable import MomentumCore

final class NutritionCalculatorTests: XCTestCase {
    func test_servingMultiplierScalesCaloriesAndProtein() throws {
        let totals = try NutritionCalculator().entryTotals(
            caloriesPerBaseServing: 320,
            proteinGramsPerBaseServing: 18.5,
            servingMultiplier: 1.5
        )

        XCTAssertEqual(totals.calories, 480)
        XCTAssertEqual(totals.proteinGrams, 27.75)
    }

    func test_fractionalServingMultiplierIsNotRounded() throws {
        let totals = try NutritionCalculator().entryTotals(
            caloriesPerBaseServing: 125,
            proteinGramsPerBaseServing: 7.25,
            servingMultiplier: 0.25
        )

        XCTAssertEqual(totals.calories, 31.25)
        XCTAssertEqual(totals.proteinGrams, 1.8125)
    }

    func test_zeroBaseValuesAreValid() throws {
        XCTAssertEqual(
            try NutritionCalculator().entryTotals(
                caloriesPerBaseServing: 0,
                proteinGramsPerBaseServing: 0,
                servingMultiplier: 1
            ),
            NutritionTotals(calories: 0, proteinGrams: 0)
        )
    }

    func test_negativeBaseValuesAndNonPositiveMultiplierAreRejected() {
        XCTAssertThrowsError(try NutritionCalculator().entryTotals(
            caloriesPerBaseServing: -1,
            proteinGramsPerBaseServing: 10,
            servingMultiplier: 1
        )) { XCTAssertEqual($0 as? NutritionCalculationError, .negativeCalories) }

        XCTAssertThrowsError(try NutritionCalculator().entryTotals(
            caloriesPerBaseServing: 10,
            proteinGramsPerBaseServing: -1,
            servingMultiplier: 1
        )) { XCTAssertEqual($0 as? NutritionCalculationError, .negativeProtein) }

        XCTAssertThrowsError(try NutritionCalculator().entryTotals(
            caloriesPerBaseServing: 10,
            proteinGramsPerBaseServing: 1,
            servingMultiplier: 0
        )) { XCTAssertEqual($0 as? NutritionCalculationError, .nonPositiveServingMultiplier) }
    }

    func test_targetRangeBoundariesAreInclusive() throws {
        let target = NutritionTargetRange(
            calorieMinimum: 2_300,
            calorieMaximum: 2_500,
            proteinMinimum: 150
        )
        let calculator = NutritionCalculator()

        XCTAssertEqual(
            try calculator.evaluate(
                totals: NutritionTotals(calories: 2_300, proteinGrams: 150),
                against: target
            ),
            NutritionTargetEvaluation(caloriesWithinRange: true, proteinMinimumMet: true)
        )
        XCTAssertEqual(
            try calculator.evaluate(
                totals: NutritionTotals(calories: 2_500, proteinGrams: 150),
                against: target
            ).meetsTarget,
            true
        )
    }

    func test_dayTotalsSumPersistedEntryTotals() {
        XCTAssertEqual(
            NutritionCalculator().dayTotals(entries: [
                NutritionTotals(calories: 400, proteinGrams: 20),
                NutritionTotals(calories: Decimal(string: "125.5")!, proteinGrams: 7.25)
            ]),
            NutritionTotals(calories: Decimal(string: "525.5")!, proteinGrams: 27.25)
        )
    }

    func test_targetRangeRejectsValuesJustOutsideEitherBoundary() throws {
        let target = NutritionTargetRange(
            calorieMinimum: 2_300,
            calorieMaximum: 2_500,
            proteinMinimum: 150
        )
        let calculator = NutritionCalculator()

        XCTAssertFalse(try calculator.evaluate(
            totals: NutritionTotals(calories: Decimal(string: "2299.999")!, proteinGrams: 150),
            against: target
        ).caloriesWithinRange)
        XCTAssertFalse(try calculator.evaluate(
            totals: NutritionTotals(calories: Decimal(string: "2500.001")!, proteinGrams: 150),
            against: target
        ).caloriesWithinRange)
        XCTAssertFalse(try calculator.evaluate(
            totals: NutritionTotals(calories: 2_400, proteinGrams: Decimal(string: "149.999")!),
            against: target
        ).proteinMinimumMet)
    }

    func test_invalidTargetRangeIsRejected() {
        XCTAssertThrowsError(try NutritionCalculator().evaluate(
            totals: NutritionTotals(calories: 2_400, proteinGrams: 150),
            against: NutritionTargetRange(
                calorieMinimum: 2_500,
                calorieMaximum: 2_300,
                proteinMinimum: 150
            )
        )) { XCTAssertEqual($0 as? NutritionCalculationError, .invalidTargetRange) }
    }
}
