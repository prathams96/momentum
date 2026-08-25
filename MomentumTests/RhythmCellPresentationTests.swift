import MomentumCore
import XCTest
@testable import Momentum

final class RhythmCellPresentationTests: XCTestCase {
    private func scored(_ percentage: Double) -> RhythmCellPresentation {
        .init(score: .score(completedCount: 1, dueCount: 1, percentage: percentage), isPaused: false)
    }

    func testFiveStepTonalRampFromMissedToComplete() {
        XCTAssertEqual(scored(0).tonalStep, 0)
        XCTAssertEqual(scored(25).tonalStep, 1)
        XCTAssertEqual(scored(50).tonalStep, 2)
        XCTAssertEqual(scored(75).tonalStep, 3)
        XCTAssertEqual(scored(100).tonalStep, 4)
        XCTAssertNil(RhythmCellPresentation(score: .noObligation, isPaused: false).tonalStep)
        XCTAssertNil(RhythmCellPresentation.paused.tonalStep)
    }

    func testNoObligationIsOutlinedNeverConfusedWithMissed() {
        let presentation = RhythmCellPresentation(score: .noObligation, isPaused: false)

        XCTAssertNotEqual(presentation.fill, scored(0).fill)
        XCTAssertNotEqual(presentation.stroke, .clear)
    }

    func testPausedBeatsScoreAndIsVisuallyDistinct() {
        let paused = RhythmCellPresentation(
            score: .score(completedCount: 1, dueCount: 1, percentage: 100),
            isPaused: true
        )

        XCTAssertEqual(paused, .paused)
        XCTAssertNotEqual(paused.fill, scored(100).fill)
        XCTAssertNotEqual(paused.stroke, .clear)
        XCTAssertNotEqual(paused.fill, RhythmCellPresentation(score: .noObligation, isPaused: false).fill)
    }

    func testVoiceOverSaysPausedNotBroken() {
        let day = DomainDay(year: 2026, month: 8, day: 2)

        XCTAssertTrue(
            RhythmCellPresentation(score: .noObligation, isPaused: true)
                .accessibilityLabel(for: day)
                .contains("paused, not broken")
        )
    }

    func testVoiceOverDistinguishesObligationStates() {
        let day = DomainDay(year: 2026, month: 8, day: 2)

        XCTAssertTrue(
            RhythmCellPresentation(score: .noObligation, isPaused: false)
                .accessibilityLabel(for: day)
                .contains("no obligation")
        )
        XCTAssertTrue(
            scored(100).accessibilityLabel(for: day).contains("complete")
        )
        XCTAssertTrue(
            scored(0).accessibilityLabel(for: day).contains("percent")
        )
    }
}
