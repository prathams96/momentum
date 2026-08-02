import Foundation

struct MaterialTimeZoneChange: Equatable, Identifiable {
    let previousIdentifier: String
    let currentIdentifier: String

    var id: String { "\(previousIdentifier)->\(currentIdentifier)" }
}

enum MaterialTimeZoneChangeDecision: Equatable {
    case initialize(identifier: String)
    case unchanged(clearPending: Bool)
    case requiresConfirmation(MaterialTimeZoneChange)

    static func evaluate(
        acceptedIdentifier: String?,
        pendingIdentifier: String?,
        currentIdentifier: String
    ) -> Self {
        guard let acceptedIdentifier, !acceptedIdentifier.isEmpty else {
            return .initialize(identifier: currentIdentifier)
        }
        guard acceptedIdentifier != currentIdentifier else {
            return .unchanged(clearPending: pendingIdentifier != nil)
        }
        return .requiresConfirmation(MaterialTimeZoneChange(
            previousIdentifier: acceptedIdentifier,
            currentIdentifier: currentIdentifier
        ))
    }
}

@MainActor
enum MaterialTimeZoneChangeStore {
    private static let acceptedKey = "momentum.acceptedTimeZoneIdentifier"
    private static let pendingKey = "momentum.pendingTimeZoneIdentifier"

    static func evaluate(
        currentIdentifier: String = TimeZone.autoupdatingCurrent.identifier,
        defaults: UserDefaults = .standard
    ) -> MaterialTimeZoneChange? {
        let decision = MaterialTimeZoneChangeDecision.evaluate(
            acceptedIdentifier: defaults.string(forKey: acceptedKey),
            pendingIdentifier: defaults.string(forKey: pendingKey),
            currentIdentifier: currentIdentifier
        )

        switch decision {
        case .initialize(let identifier):
            defaults.set(identifier, forKey: acceptedKey)
            defaults.removeObject(forKey: pendingKey)
            return nil
        case .unchanged(let clearPending):
            if clearPending { defaults.removeObject(forKey: pendingKey) }
            return nil
        case .requiresConfirmation(let change):
            defaults.set(change.currentIdentifier, forKey: pendingKey)
            return change
        }
    }

    static func accept(
        _ change: MaterialTimeZoneChange,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(change.currentIdentifier, forKey: acceptedKey)
        defaults.removeObject(forKey: pendingKey)
    }
}
