import Foundation
import XCTest
@testable import MomentumCore

final class CareScheduleEngineTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func test_dailyAndWeekdayRulesUseTheSuppliedCalendar() {
        let engine = CareScheduleEngine()
        let monday = DomainDay(year: 2026, month: 8, day: 3)
        let tuesday = DomainDay(year: 2026, month: 8, day: 4)

        XCTAssertEqual(
            engine.evaluate(.init(rule: .daily), on: monday, calendar: calendar),
            .due
        )
        XCTAssertEqual(
            engine.evaluate(.init(rule: .weekdays([2, 5])), on: monday, calendar: calendar),
            .due
        )
        XCTAssertEqual(
            engine.evaluate(.init(rule: .weekdays([2, 5])), on: tuesday, calendar: calendar),
            .notDue
        )
    }

    func test_alternatingThreeFourDayCadenceProducesWednesdaySaturdayPattern() {
        let payload = CareRecurrencePayload(rule: .alternating(
            anchorDueDay: DomainDay(year: 2026, month: 8, day: 5),
            intervals: [3, 4],
            intervalAfterAnchorIndex: 0
        ))
        let engine = CareScheduleEngine()
        let expectedDueDays: Set<DomainDay> = [
            DomainDay(year: 2026, month: 8, day: 5),
            DomainDay(year: 2026, month: 8, day: 8),
            DomainDay(year: 2026, month: 8, day: 12),
            DomainDay(year: 2026, month: 8, day: 15),
            DomainDay(year: 2026, month: 8, day: 19)
        ]

        for offset in 0..<15 {
            let candidate = DomainDay(year: 2026, month: 8, day: 5)
                .adding(days: offset, calendar: calendar)
            XCTAssertEqual(
                engine.evaluate(payload, on: candidate, calendar: calendar),
                expectedDueDays.contains(candidate) ? .due : .notDue,
                "Unexpected cadence state for \(candidate)"
            )
        }
    }

    func test_actualCompletionDayBecomesBasisForNextAlternatingInterval() {
        let payload = CareRecurrencePayload(rule: .alternating(
            anchorDueDay: DomainDay(year: 2026, month: 8, day: 5),
            intervals: [3, 4],
            intervalAfterAnchorIndex: 0
        ))

        let advanced = CareScheduleEngine().advancedAlternatingPayload(
            afterCompletionOn: DomainDay(year: 2026, month: 8, day: 6),
            payload: payload,
            calendar: calendar
        )

        XCTAssertEqual(advanced, CareRecurrencePayload(rule: .alternating(
            anchorDueDay: DomainDay(year: 2026, month: 8, day: 9),
            intervals: [3, 4],
            intervalAfterAnchorIndex: 1
        )))
    }

    func test_missedRollingCareRollsToNextDomainDayExactlyOnce() {
        let dueDay = DomainDay(year: 2026, month: 8, day: 5)
        let engine = CareScheduleEngine()

        XCTAssertEqual(
            engine.rollForwardDay(
                for: dueDay,
                asOf: DomainDay(year: 2026, month: 8, day: 6),
                alreadyRolledForward: false,
                calendar: calendar
            ),
            DomainDay(year: 2026, month: 8, day: 6)
        )
        XCTAssertNil(engine.rollForwardDay(
            for: dueDay,
            asOf: DomainDay(year: 2026, month: 8, day: 7),
            alreadyRolledForward: true,
            calendar: calendar
        ))
    }

    func test_invalidRecurrenceRepairsOnlyThatSchedule() {
        XCTAssertEqual(
            CareScheduleEngine().evaluate(
                .init(rule: .alternating(
                    anchorDueDay: DomainDay(year: 2026, month: 8, day: 5),
                    intervals: [3, 0],
                    intervalAfterAnchorIndex: 0
                )),
                on: DomainDay(year: 2026, month: 8, day: 5),
                calendar: calendar
            ),
            .needsRepair(reason: .invalidAlternatingIntervals)
        )
        XCTAssertEqual(
            CareScheduleEngine().evaluate(
                .init(rule: .weekdays([0, 8])),
                on: DomainDay(year: 2026, month: 8, day: 5),
                calendar: calendar
            ),
            .needsRepair(reason: .invalidWeekdays)
        )
    }

    func test_unknownPayloadVersionDecodesAsUnsupportedInsteadOfThrowing() throws {
        let data = Data(#"{"version":99,"kind":"future"}"#.utf8)
        let decoded = try JSONDecoder().decode(CareRecurrencePayload.self, from: data)

        XCTAssertEqual(decoded.rule, .unsupported(version: 99))
        XCTAssertEqual(
            CareScheduleEngine().evaluate(
                decoded,
                on: DomainDay(year: 2026, month: 8, day: 5),
                calendar: calendar
            ),
            .needsRepair(reason: .unsupportedVersion(99))
        )
    }

    func test_currentPayloadRoundTripsThroughCodable() throws {
        let original = CareRecurrencePayload(rule: .alternating(
            anchorDueDay: DomainDay(year: 2026, month: 8, day: 5),
            intervals: [3, 4],
            intervalAfterAnchorIndex: 0
        ))

        let decoded = try JSONDecoder().decode(
            CareRecurrencePayload.self,
            from: JSONEncoder().encode(original)
        )

        XCTAssertEqual(decoded, original)
    }
}
