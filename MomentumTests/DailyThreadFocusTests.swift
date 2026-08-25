import SwiftUI
import XCTest

@testable import Momentum

@MainActor
final class DailyThreadFocusTests: XCTestCase {
    private func contribution(
        id: String,
        rank: Int,
        state: ContributionState
    ) -> TodayContribution {
        TodayContribution(
            metadata: ModuleMetadata(
                id: ModuleID(id),
                displayName: id,
                symbolName: "circle",
                tint: .blue,
                todayRank: rank
            ),
            state: state
        )
    }

    func testFocusIsFirstDueIncompleteContribution() {
        let contributions = [
            contribution(id: "Workout", rank: 10, state: .completed),
            contribution(id: "Nutrition", rank: 20, state: .ongoing),
            contribution(id: "Care", rank: 30, state: .ongoing),
        ]

        let stages = DailyThreadFocus.stages(from: contributions)

        XCTAssertEqual(stages.map(\.title), ["Workout", "Nutrition", "Care"])
        XCTAssertTrue(stages[1].isFocused)
        XCTAssertFalse(stages[0].isFocused)
        XCTAssertFalse(stages[2].isFocused)
    }

    func testOptionalContributionsAreNeverFocused() {
        let contributions = [
            contribution(id: "Workout", rank: 10, state: .optional),
            contribution(id: "Nutrition", rank: 20, state: .ongoing),
        ]

        let stages = DailyThreadFocus.stages(from: contributions)

        XCTAssertTrue(stages[1].isFocused)
    }

    func testNoReflectStageIsAppended() {
        let stages = DailyThreadFocus.stages(from: [
            contribution(id: "Hydration", rank: 40, state: .completed)
        ])

        XCTAssertEqual(stages.count, 1)
        XCTAssertNil(stages.first(where: { $0.title == "Reflect" }))
    }

    func testCompleteDayHasNoFocusedStage() {
        let stages = DailyThreadFocus.stages(from: [
            contribution(id: "Workout", rank: 10, state: .completed),
            contribution(id: "Nutrition", rank: 20, state: .completed),
        ])

        XCTAssertTrue(stages.allSatisfy { !$0.isFocused })
    }

    func testAttentionWinsCalloutOverEarlierOngoing() {
        let contributions = [
            contribution(id: "Workout", rank: 10, state: .attention),
            contribution(id: "Nutrition", rank: 20, state: .ongoing),
        ]
        let callout = DailyThreadFocus.callout(
            contributions: contributions,
            stages: DailyThreadFocus.stages(from: contributions)
        )

        XCTAssertEqual(callout, "Workout needs attention")
    }

    func testCalloutNamesNextIncompleteActivity() {
        let contributions = [
            contribution(id: "Workout", rank: 10, state: .completed),
            contribution(id: "Nutrition", rank: 20, state: .ongoing),
        ]
        let callout = DailyThreadFocus.callout(
            contributions: contributions,
            stages: DailyThreadFocus.stages(from: contributions)
        )

        XCTAssertEqual(callout, "Nutrition next")
    }

    func testCalloutPresentsCompleteDayWithoutReflect() {
        let contributions = [
            contribution(id: "Workout", rank: 10, state: .completed),
            contribution(id: "Care", rank: 20, state: .optional),
        ]
        let callout = DailyThreadFocus.callout(
            contributions: contributions,
            stages: DailyThreadFocus.stages(from: contributions)
        )

        XCTAssertEqual(callout, "All done for today")
    }
}
