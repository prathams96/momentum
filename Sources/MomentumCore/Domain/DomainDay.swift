import Foundation

public struct DomainDay: Hashable, Comparable, Codable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func containing(
        _ date: Date,
        calendar: Calendar,
        cutoffMinutes: Int
    ) -> DomainDay {
        let shiftedDate = calendar.date(
            byAdding: .minute,
            value: -cutoffMinutes,
            to: date
        ) ?? date
        let components = calendar.dateComponents([.year, .month, .day], from: shiftedDate)

        return DomainDay(
            year: components.year!,
            month: components.month!,
            day: components.day!
        )
    }

    public func adding(days: Int, calendar: Calendar) -> DomainDay {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12

        let baseDate = calendar.date(from: components)!
        let resultDate = calendar.date(byAdding: .day, value: days, to: baseDate)!
        let resultComponents = calendar.dateComponents([.year, .month, .day], from: resultDate)

        return DomainDay(
            year: resultComponents.year!,
            month: resultComponents.month!,
            day: resultComponents.day!
        )
    }

    public static func < (lhs: DomainDay, rhs: DomainDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
