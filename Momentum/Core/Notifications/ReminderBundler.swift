import Foundation

/// Generic, domain-agnostic merging of notification candidates (pre-launch
/// spec §6): each enabled module contributes candidates carrying its own
/// sentence fragment plus an optional deep-link payload. A candidate whose
/// fire time is within `proximityMinutes` of an evening anchor on the same day
/// loses its own notification and its fragment merges into one Evening
/// check-in firing at the earliest contributed time. The bundler knows nothing
/// about which module produced a candidate — anchors are recognized purely by
/// their notification category.
enum ReminderBundler {
    static func bundle(
        _ candidates: [ScheduledReminder],
        anchorCategory: String,
        proximityMinutes: Int = 30
    ) -> [ScheduledReminder] {
        let anchors = candidates.filter { $0.categoryIdentifier == anchorCategory }
        guard !anchors.isEmpty else { return candidates }

        var mergedByAnchor: [String: (anchor: ScheduledReminder, merged: [ScheduledReminder])] = [:]
        var mergedIdentifiers = Set<String>()
        for anchor in anchors {
            let nearby = candidates.filter { candidate in
                candidate.identifier != anchor.identifier
                    && candidate.categoryIdentifier != anchorCategory
                    && firesWithin(candidate.dateComponents, of: anchor.dateComponents, minutes: proximityMinutes)
            }
            if !nearby.isEmpty {
                mergedByAnchor[anchor.identifier] = (anchor, nearby)
                mergedIdentifiers.formUnion(nearby.map(\.identifier))
            }
        }

        return candidates.compactMap { candidate in
            if mergedIdentifiers.contains(candidate.identifier) { return nil }
            guard let entry = mergedByAnchor[candidate.identifier] else { return candidate }
            return merge(entry.merged, into: entry.anchor)
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

    /// One notification max per evening: the contributed fragments concatenate
    /// verbatim and the merged reminder fires at the earliest contributed
    /// time — never later than any folded candidate's own reminder.
    private static func merge(
        _ merged: [ScheduledReminder],
        into anchor: ScheduledReminder
    ) -> ScheduledReminder {
        let fragments = ([anchor.body] + merged.map(\.body))
            .map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }
        let earliest = merged
            .map(\.dateComponents)
            .filter { minuteOfDay($0) < minuteOfDay(anchor.dateComponents) }
            .min(by: { minuteOfDay($0) < minuteOfDay($1) }) ?? anchor.dateComponents
        return ScheduledReminder(
            identifier: anchor.identifier,
            title: anchor.title,
            body: fragments.joined(separator: ". ") + ".",
            categoryIdentifier: anchor.categoryIdentifier,
            dateComponents: earliest,
            repeats: anchor.repeats,
            userInfo: anchor.userInfo
        )
    }
}
