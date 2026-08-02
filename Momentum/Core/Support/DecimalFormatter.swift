import Foundation

enum DecimalFormatter {
    static func whole(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).doubleValue.formatted(.number.precision(.fractionLength(0)))
    }

    static func whole(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    static func onePlace(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).doubleValue.formatted(.number.precision(.fractionLength(0...1)))
    }

    static func onePlace(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
