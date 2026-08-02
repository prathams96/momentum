import Foundation

public enum CareRecurrenceRule: Equatable, Sendable {
    case daily
    /// Calendar weekday values use Foundation's 1 (Sunday) through 7 (Saturday).
    case weekdays(Set<Int>)
    case alternating(
        anchorDueDay: DomainDay,
        intervals: [Int],
        intervalAfterAnchorIndex: Int
    )
    case unsupported(version: Int)
}

public struct CareRecurrencePayload: Equatable, Codable, Sendable {
    public static let currentVersion = 1

    public let rule: CareRecurrenceRule

    public init(rule: CareRecurrenceRule) {
        self.rule = rule
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case kind
        case weekdays
        case anchorDueDay
        case intervals
        case intervalAfterAnchorIndex
    }

    private enum Kind: String, Codable {
        case daily
        case weekdays
        case alternating
        case unsupported
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else {
            rule = .unsupported(version: version)
            return
        }

        guard let kind = try? container.decode(Kind.self, forKey: .kind) else {
            rule = .unsupported(version: version)
            return
        }
        switch kind {
        case .daily:
            rule = .daily
        case .weekdays:
            rule = .weekdays(Set(try container.decode([Int].self, forKey: .weekdays)))
        case .alternating:
            rule = .alternating(
                anchorDueDay: try container.decode(DomainDay.self, forKey: .anchorDueDay),
                intervals: try container.decode([Int].self, forKey: .intervals),
                intervalAfterAnchorIndex: try container.decode(
                    Int.self,
                    forKey: .intervalAfterAnchorIndex
                )
            )
        case .unsupported:
            rule = .unsupported(version: version)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch rule {
        case .daily:
            try container.encode(Self.currentVersion, forKey: .version)
            try container.encode(Kind.daily, forKey: .kind)
        case let .weekdays(weekdays):
            try container.encode(Self.currentVersion, forKey: .version)
            try container.encode(Kind.weekdays, forKey: .kind)
            try container.encode(weekdays.sorted(), forKey: .weekdays)
        case let .alternating(anchorDueDay, intervals, intervalAfterAnchorIndex):
            try container.encode(Self.currentVersion, forKey: .version)
            try container.encode(Kind.alternating, forKey: .kind)
            try container.encode(anchorDueDay, forKey: .anchorDueDay)
            try container.encode(intervals, forKey: .intervals)
            try container.encode(intervalAfterAnchorIndex, forKey: .intervalAfterAnchorIndex)
        case let .unsupported(version):
            try container.encode(version, forKey: .version)
            try container.encode(Kind.unsupported, forKey: .kind)
        }
    }
}

public enum CareScheduleRepairReason: Equatable, Sendable {
    case invalidWeekdays
    case invalidAlternatingIntervals
    case invalidAlternatingIndex
    case unsupportedVersion(Int)
}

public enum CareScheduleEvaluation: Equatable, Sendable {
    case due
    case notDue
    case needsRepair(reason: CareScheduleRepairReason)
}

public struct CareScheduleEngine: Sendable {
    public init() {}

    public func evaluate(
        _ payload: CareRecurrencePayload,
        on day: DomainDay,
        calendar: Calendar
    ) -> CareScheduleEvaluation {
        switch payload.rule {
        case .daily:
            return .due
        case let .weekdays(weekdays):
            guard !weekdays.isEmpty, weekdays.allSatisfy((1...7).contains) else {
                return .needsRepair(reason: .invalidWeekdays)
            }
            let weekday = calendar.component(.weekday, from: day.careFoundationDate(calendar: calendar))
            return weekdays.contains(weekday) ? .due : .notDue
        case let .alternating(anchorDueDay, intervals, intervalAfterAnchorIndex):
            guard !intervals.isEmpty, intervals.allSatisfy({ $0 > 0 }) else {
                return .needsRepair(reason: .invalidAlternatingIntervals)
            }
            guard intervals.indices.contains(intervalAfterAnchorIndex) else {
                return .needsRepair(reason: .invalidAlternatingIndex)
            }
            guard day >= anchorDueDay else {
                return .notDue
            }

            var dueDay = anchorDueDay
            var intervalIndex = intervalAfterAnchorIndex
            while dueDay < day {
                dueDay = dueDay.adding(days: intervals[intervalIndex], calendar: calendar)
                intervalIndex = (intervalIndex + 1) % intervals.count
            }
            return dueDay == day ? .due : .notDue
        case let .unsupported(version):
            return .needsRepair(reason: .unsupportedVersion(version))
        }
    }

    public func advancedAlternatingPayload(
        afterCompletionOn completionDay: DomainDay,
        payload: CareRecurrencePayload,
        calendar: Calendar
    ) -> CareRecurrencePayload? {
        guard case let .alternating(_, intervals, intervalIndex) = payload.rule,
              !intervals.isEmpty,
              intervals.allSatisfy({ $0 > 0 }),
              intervals.indices.contains(intervalIndex) else {
            return nil
        }

        let nextDueDay = completionDay.adding(days: intervals[intervalIndex], calendar: calendar)
        return CareRecurrencePayload(rule: .alternating(
            anchorDueDay: nextDueDay,
            intervals: intervals,
            intervalAfterAnchorIndex: (intervalIndex + 1) % intervals.count
        ))
    }

    public func rollForwardDay(
        for dueDay: DomainDay,
        asOf currentDay: DomainDay,
        alreadyRolledForward: Bool,
        calendar: Calendar
    ) -> DomainDay? {
        guard !alreadyRolledForward else {
            return nil
        }
        let nextDay = dueDay.adding(days: 1, calendar: calendar)
        return currentDay >= nextDay ? nextDay : nil
    }
}

private extension DomainDay {
    func careFoundationDate(calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: 12
        ))!
    }
}
