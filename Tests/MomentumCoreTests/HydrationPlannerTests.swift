import XCTest
@testable import MomentumCore

final class HydrationPlannerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: hour, minute: minute))!
    }

    // MARK: - Pace gate

    func testCheckpointFiresOnlyWhenBehindLinearPace() {
        // Target 2400 ml over 24 h → 100 ml/h. At 12:00 expected 1200 ml.
        let behind = HydrationEngine.isBehindPace(
            targetML: 2400,
            consumedML: 500,
            checkpointMinuteOfDay: 12 * 60
        )
        let ahead = HydrationEngine.isBehindPace(
            targetML: 2400,
            consumedML: 1500,
            checkpointMinuteOfDay: 12 * 60
        )

        XCTAssertTrue(behind)
        XCTAssertFalse(ahead)
    }

    func testExactlyOnPaceIsNotBehind() {
        XCTAssertFalse(HydrationEngine.isBehindPace(
            targetML: 2400,
            consumedML: 1200,
            checkpointMinuteOfDay: 12 * 60
        ))
    }

    // MARK: - Checkpoint planning

    private func plan(
        now: Date,
        intake: Int,
        enabled: Bool = true,
        reached: Bool = false,
        fired: Set<Int> = []
    ) -> [Int] {
        HydrationEngine.dueCheckpoints(
            now: now,
            calendar: calendar,
            checkpointsEnabled: enabled,
            checkpointMinutes: [11 * 60, 15 * 60, 19 * 60],
            targetML: 2400,
            consumedML: intake,
            targetReached: reached,
            alreadyFiredSlots: fired
        )
    }

    func testDueCheckpointEmitsSingleSlotWhenBehindPace() {
        XCTAssertEqual(plan(now: date(15), intake: 200), [15 * 60])
    }

    func testCheckpointSuppressedWhenAheadOfPace() {
        XCTAssertTrue(plan(now: date(15), intake: 2000).isEmpty)
    }

    func testAllCheckpointsSuppressedOnceTargetReached() {
        XCTAssertTrue(plan(now: date(15), intake: 0, reached: true).isEmpty)
    }

    func testDisabledMasterToggleEmitsNothing() {
        XCTAssertTrue(plan(now: date(15), intake: 0, enabled: false).isEmpty)
    }

    func testQuietHoursClampToNineToTwentyOne() {
        XCTAssertTrue(plan(now: date(7), intake: 0).isEmpty, "Before 09:00 nothing fires")
        XCTAssertTrue(plan(now: date(22), intake: 0).isEmpty, "After 21:00 nothing fires")
    }

    func testPastCheckpointsDoNotRetrofire() {
        // At 16:00 both 11:00 and 15:00 are past; only slots not yet fired and
        // still valid may fire. Retro-firing stale checkpoints is wrong.
        XCTAssertEqual(
            plan(now: date(16), intake: 0, fired: []),
            [],
            "Stale checkpoints must not retro-fire"
        )
    }

    func testAlreadyFiredSlotIsNotReemitted() {
        XCTAssertEqual(
            plan(now: date(15, 10), intake: 200, fired: [11 * 60]),
            [15 * 60]
        )
        XCTAssertEqual(
            plan(now: date(15, 10), intake: 200, fired: [11 * 60, 15 * 60]),
            []
        )
    }

    func testHardCapOfThreePerDayHoldsEvenWithExtraConfiguredSlots() {
        let due = HydrationEngine.dueCheckpoints(
            now: date(20),
            calendar: calendar,
            checkpointsEnabled: true,
            checkpointMinutes: [9 * 60 + 30, 11 * 60, 13 * 60, 15 * 60, 17 * 60],
            targetML: 9600,
            consumedML: 0,
            targetReached: false,
            alreadyFiredSlots: [9 * 60 + 30, 11 * 60, 13 * 60]
        )
        XCTAssertTrue(due.isEmpty, "Cap of 3 fired slots per day reached")
    }

    // MARK: - Rendering helpers

    func testMillilitreConversionToWholeFluidOunces() {
        XCTAssertEqual(HydrationEngine.fluidOunces(fromML: 250), 8)
        XCTAssertEqual(HydrationEngine.fluidOunces(fromML: 500), 17)
        XCTAssertEqual(HydrationEngine.fluidOunces(fromML: 0), 0)
    }
}
