import Foundation
import MomentumCore

enum PersistedDomainDay {
    static func encode(_ day: DomainDay) -> String {
        String(format: "%04d-%02d-%02d", day.year, day.month, day.day)
    }

    static func decode(_ value: String) -> DomainDay? {
        let pieces = value.split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3 else { return nil }
        return DomainDay(year: pieces[0], month: pieces[1], day: pieces[2])
    }

    static func date(
        for day: DomainDay,
        calendar: Calendar = .autoupdatingCurrent,
        hour: Int = 12,
        minute: Int = 0
    ) -> Date? {
        calendar.date(from: DateComponents(
            year: day.year,
            month: day.month,
            day: day.day,
            hour: hour,
            minute: minute
        ))
    }
}
