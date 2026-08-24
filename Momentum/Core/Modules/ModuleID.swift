import Foundation

/// Stable identity of a behavior module. Persisted in settings and used to
/// namespace notifications, exports, and facts; never rename a raw value.
public struct ModuleID: Hashable, Codable, Sendable, RawRepresentable, Comparable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static func < (lhs: ModuleID, rhs: ModuleID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension ModuleID: CustomStringConvertible {
    public var description: String { rawValue }
}

/// Built-in module identities. Feature modules own their identifiers;
/// these are referenced by enablement defaults and seed logic.
enum BuiltInModuleID {
    static let workout = ModuleID("workout")
    static let nutrition = ModuleID("nutrition")
    static let care = ModuleID("care")
    static let hydration = ModuleID("hydration")
}
