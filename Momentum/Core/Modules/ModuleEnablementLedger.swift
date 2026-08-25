import Foundation
import MomentumCore
import SwiftData

/// Tracks each module's enabled stretches so Category Streaks can pause —
/// never break — across disabled intervals (parent spec §3.3). Idempotent;
/// the reconciliation orchestrator persists its mutations with the single
/// end-of-run save.
@MainActor
enum ModuleEnablementLedger {
    /// Days up to and including `through` on which the module was disabled.
    /// Modules without any recorded interval history pause nothing
    /// (back-compat for installs upgraded before the ledger existed).
    static func pausedDays(
        for moduleID: ModuleID,
        through day: DomainDay,
        calendar: Calendar,
        in context: ModelContext
    ) -> Set<DomainDay> {
        guard let allRecords = try? context.fetch(FetchDescriptor<ModuleActivationIntervalRecord>()) else {
            return []
        }
        let records = allRecords
            .filter { $0.moduleIDRaw == moduleID.rawValue && !$0.isDeleted }
        guard !records.isEmpty else { return [] }

        guard var cursor = scanStart(records: records, through: day, calendar: calendar) else {
            return []
        }
        var paused: Set<DomainDay> = []
        while cursor <= day {
            if !isCovered(cursor, intervals: records) {
                paused.insert(cursor)
            }
            cursor = cursor.adding(days: 1, calendar: calendar)
        }
        return paused
    }

    /// Opens/closes intervals to match `enabledIDs`. Safe to run repeatedly;
    /// does not save (the orchestrator's single save persists everything).
    static func reconcile(
        enabledIDs: Set<ModuleID>,
        currentDay: DomainDay,
        in context: ModelContext,
        registry: ModuleRegistry = .standard
    ) throws {
        let records = try context.fetch(FetchDescriptor<ModuleActivationIntervalRecord>())
        let now = Date.now

        for module in registry.modules {
            let id = module.metadata.id
            let moduleRecords = records
                .filter { $0.moduleIDRaw == id.rawValue && !$0.isDeleted }
            let openInterval = moduleRecords.first { $0.enabledToDomainDay == nil }
            let isEnabled = enabledIDs.contains(id)

            switch (isEnabled, openInterval) {
            case (true, nil):
                // First sighting ever: cover from forever so upgrade installs
                // keep their existing streaks unbroken. Re-enablements instead
                // anchor to the actual day.
                let fromValue = moduleRecords.isEmpty
                    ? ""
                    : PersistedDomainDay.encode(currentDay)
                context.insert(ModuleActivationIntervalRecord(
                    moduleIDRaw: id.rawValue,
                    enabledFromDomainDay: fromValue
                ))
            case (false, .some(let interval)):
                // The disable takes effect from the previous day boundary:
                // the toggle day itself stays eligible if the module already
                // recorded completion facts on it, and pauses otherwise.
                interval.enabledToDomainDay = PersistedDomainDay.encode(
                    currentDay.adding(days: -1, calendar: .autoupdatingCurrent)
                )
                interval.updatedAt = now
            case (true, _), (false, nil):
                break
            }
        }
    }

    // MARK: - Coverage internals

    private static func isCovered(
        _ day: DomainDay,
        intervals: [ModuleActivationIntervalRecord]
    ) -> Bool {
        intervals.contains { record in
            let startsBeforeOrOn = record.enabledFromDomainDay.isEmpty
                || (PersistedDomainDay.decode(record.enabledFromDomainDay).map { $0 <= day } ?? false)
            let endsAfterOrNever = record.enabledToDomainDay.map { dayValue -> Bool in
                PersistedDomainDay.decode(dayValue).map { $0 >= day } ?? false
            } ?? true
            return startsBeforeOrOn && endsAfterOrNever
        }
    }

    /// Where the day-by-day coverage scan may start: the earliest meaningful
    /// boundary among recorded starts/ends, clamped to a bounded lookback so
    /// scans stay cheap even with forever-sentinels.
    private static func scanStart(
        records: [ModuleActivationIntervalRecord],
        through day: DomainDay,
        calendar: Calendar
    ) -> DomainDay? {
        let lookbackLimit = day.adding(days: -365, calendar: calendar)
        let boundaries = records.flatMap { record -> [DomainDay] in
            var values: [DomainDay] = []
            if !record.enabledFromDomainDay.isEmpty {
                values.append(contentsOf: PersistedDomainDay.decode(record.enabledFromDomainDay).map { [$0] } ?? [])
            }
            if let endValue = record.enabledToDomainDay {
                values.append(contentsOf: PersistedDomainDay.decode(endValue).map { [$0] } ?? [])
            }
            return values
        }
        return boundaries.min().map { max($0, lookbackLimit) } ?? lookbackLimit
    }
}
