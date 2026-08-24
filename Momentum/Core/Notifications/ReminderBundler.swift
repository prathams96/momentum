import Foundation

/// Generic, domain-agnostic bundling of notification candidates that fire at
/// the same moment (parent-spec decision 4): a candidate whose fire time is
/// within `proximityMinutes` of an anchor candidate on the same day loses its
/// own notification and its identity is folded into the anchor's body. The
/// bundler knows nothing about which module produced a candidate — anchors are
/// recognized purely by their notification category.
enum ReminderBundler {
    static func bundle(
        _ candidates: [ScheduledReminder],
        anchorCategory: String,
        proximityMinutes: Int = 0
    ) -> [ScheduledReminder] {
        let anchors = candidates.filter { $0.categoryIdentifier == anchorCategory }
        guard !anchors.isEmpty else { return candidates }

        var foldedByAnchor: [String: [ScheduledReminder]] = [:]
        var foldedIdentifiers = Set<String>()
        for anchor in anchors {
            let nearby = candidates.filter { candidate in
                candidate.identifier != anchor.identifier
                    && candidate.categoryIdentifier != anchorCategory
                    && firesWithin(candidate.dateComponents, of: anchor.dateComponents, minutes: proximityMinutes)
            }
            if !nearby.isEmpty {
                foldedByAnchor[anchor.identifier] = nearby
                foldedIdentifiers.formUnion(nearby.map(\.identifier))
            }
        }

        return candidates.compactMap { candidate in
            if foldedIdentifiers.contains(candidate.identifier) { return nil }
            guard let folded = foldedByAnchor[candidate.identifier] else { return candidate }
            return fold(folded, into: candidate)
        }
    }

    private static func firesWithin(
        _ lhs: DateComponents,
        of rhs: DateComponents,
        minutes: Int
    ) -> Bool {
        lhs.year == rhs.year
            && lhs.month == rhs.month
            && lhs.day == rhs.day
            && abs(minuteOfDay(lhs) - minuteOfDay(rhs)) <= minutes
    }

    private static func minuteOfDay(_ components: DateComponents) -> Int {
        (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private static func fold(
        _ folded: [ScheduledReminder],
        into anchor: ScheduledReminder
    ) -> ScheduledReminder {
        let baseBody = anchor.body.hasSuffix(".") ? String(anchor.body.dropLast()) : anchor.body
        let phrases = folded.map { "check your \($0.title) routine" }
        var userInfo = anchor.userInfo
        if let carrier = folded.first(where: { $0.userInfo["actionKind"] == "careDue" }),
           let occurrenceID = carrier.userInfo["occurrenceID"] {
            userInfo["occurrenceID"] = occurrenceID
        }
        return ScheduledReminder(
            identifier: anchor.identifier,
            title: anchor.title,
            body: baseBody + " and " + phrases.joined(separator: " and ") + ".",
            categoryIdentifier: anchor.categoryIdentifier,
            dateComponents: anchor.dateComponents,
            repeats: anchor.repeats,
            userInfo: userInfo
        )
    }
}
