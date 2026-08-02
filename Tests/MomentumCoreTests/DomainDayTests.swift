import Foundation
import XCTest
@testable import MomentumCore

final class DomainDayTests: XCTestCase {
    func test_dateBeforeCutoffBelongsToPreviousDomainDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let date = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 8,
            day: 2,
            hour: 2,
            minute: 59
        ))!

        let result = DomainDay.containing(
            date,
            calendar: calendar,
            cutoffMinutes: 180
        )

        XCTAssertEqual(result, DomainDay(year: 2026, month: 8, day: 1))
    }

    func test_exactlyAtCutoffBelongsToCurrentDomainDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let date = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 8,
            day: 2,
            hour: 3
        ))!

        let result = DomainDay.containing(
            date,
            calendar: calendar,
            cutoffMinutes: 180
        )

        XCTAssertEqual(result, DomainDay(year: 2026, month: 8, day: 2))
    }

    func test_addingDomainDaysUsesCalendarDaysAcrossDST() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let day = DomainDay(year: 2026, month: 3, day: 8)

        let result = day.adding(days: 1, calendar: calendar)

        XCTAssertEqual(result, DomainDay(year: 2026, month: 3, day: 9))
    }

    func test_sameTimestampUsesSuppliedTimeZone() {
        let date = Date(timeIntervalSince1970: 1785637800)
        var indiaCalendar = Calendar(identifier: .gregorian)
        indiaCalendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        var newYorkCalendar = Calendar(identifier: .gregorian)
        newYorkCalendar.timeZone = TimeZone(identifier: "America/New_York")!

        let indiaDay = DomainDay.containing(
            date,
            calendar: indiaCalendar,
            cutoffMinutes: 180
        )
        let newYorkDay = DomainDay.containing(
            date,
            calendar: newYorkCalendar,
            cutoffMinutes: 180
        )

        XCTAssertEqual(indiaDay, DomainDay(year: 2026, month: 8, day: 2))
        XCTAssertEqual(newYorkDay, DomainDay(year: 2026, month: 8, day: 1))
    }
}
