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
        proximityMinutes: Int = 30,
        fallbackAnchorDateComponents: DateComponents? = nil
    ) -> [ScheduledReminder] {
        var anchors = candidates.filter { $0.categoryIdentifier == anchorCategory }

        // One-notification-max guarantee (spec §6): when no module supplied
        // an anchor (e.g. nutrition disabled or already finalized), Core's
        // fallback time seeds a synthetic Evening check-in so nearby
        // candidates still merge instead of firing individually.
        if anchors.isEmpty, let fallback = fallbackAnchorDateComponents {
            let seeded = candidates.filter {
                firesWithin($0.dateComponents, of: fallback, minutes: proximityMinutes)
            }
            guard !seeded.isEmpty else { return candidates }
            let earliest = seeded.map(\.dateComponents).reduce(fallback) {
                minuteOfDay($0) <= minuteOfDay($1) ? $0 : $1
            }
            anchors = [ScheduledReminder(
                identifier: "evening.checkin.merged",
                title: "Evening check-in",
                body: "",
                categoryIdentifier: anchorCategory,
                dateComponents: earliest,
                userInfo: [:]
            )]
        }

        guard let primary = anchors.first else { return candidates }

        // Transitive clustering: absorb any candidate within the proximity
        // window of an already-clustered candidate, so chained reminders
        // collapse into the single Evening check-in instead of firing
        // separately. Candidates far outside every cluster (e.g. a daytime
        // workout reminder) keep their own actionable notification.
        var clustered = Set([primary.identifier])
        var clusterTimes = [primary.dateComponents]
        var changed = true
        while changed {
            changed = false
            for candidate in candidates where !clustered.contains(candidate.identifier) {
                if clusterTimes.contains(where: {
                    firesWithin(candidate.dateComponents, of: $0, minutes: proximityMinutes)
                }) {
                    clustered.insert(candidate.identifier)
                    clusterTimes.append(candidate.dateComponents)
                    changed = true
                }
            }
        }

        let folded = candidates.filter {
            clustered.contains($0.identifier) && $0.identifier != primary.identifier
        }
        guard !folded.isEmpty else {
            // Nothing folded (a synthesized anchor always folds its seeds, so
            // this can only happen for a real anchor with no neighbours).
            return candidates
        }

        var result = candidates.filter { !clustered.contains($0.identifier) }
        result.append(merge(folded, into: primary))
        return result
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
            .filter { !$0.isEmpty }
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
