import Foundation

public enum CSVEncodingError: Error, Equatable, Sendable {
    case columnCountMismatch(row: Int, expected: Int, actual: Int)
}

public struct RFC4180CSVEncoder: Sendable {
    public init() {}

    public func encode(headers: [String], rows: [[String]]) throws -> Data {
        var lines = [headers.map(escaped).joined(separator: ",")]
        lines.reserveCapacity(rows.count + 1)

        for (index, row) in rows.enumerated() {
            guard row.count == headers.count else {
                throw CSVEncodingError.columnCountMismatch(
                    row: index + 1,
                    expected: headers.count,
                    actual: row.count
                )
            }
            lines.append(row.map(escaped).joined(separator: ","))
        }

        return Data((lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    public func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).description(withLocale: Locale(identifier: "en_US_POSIX"))
    }

    public func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private func escaped(_ field: String) -> String {
        let scalars = field.unicodeScalars
        guard scalars.contains(",")
                || scalars.contains("\"")
                || scalars.contains("\r")
                || scalars.contains("\n") else {
            return field
        }

        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
