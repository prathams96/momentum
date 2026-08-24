import Foundation
import MomentumCore
import SwiftData

/// Singleton access to the hydration plan plus entry-mutation services.
/// All mutations save through the shared plan-editing boundary and emit the
/// module facts defined for hydration v1.
@MainActor
enum HydrationPlanService {
    /// Lazily creates the singleton plan record. Safe to call inside
    /// reconciliation (the orchestrator owns the save).
    static func fetchOrCreate(in context: ModelContext, now: Date = .now) -> HydrationPlanRecord {
        let existing = (try? context.fetch(FetchDescriptor<HydrationPlanRecord>())) ?? []
        if let canonical = existing.min { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) } {
            return canonical
        }
        let plan = HydrationPlanRecord(createdAt: now, updatedAt: now)
        context.insert(plan)
        return plan
    }

    static func plan(in context: ModelContext) -> HydrationPlanRecord? {
        ((try? context.fetch(FetchDescriptor<HydrationPlanRecord>())) ?? [])
            .min { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }

    static func checkpointMinutes(of plan: HydrationPlanRecord) -> [Int] {
        [plan.firstCheckpointMinutes, plan.secondCheckpointMinutes, plan.thirdCheckpointMinutes]
    }

    static func presetAmounts(of plan: HydrationPlanRecord) -> [Int] {
        [plan.firstPresetML, plan.secondPresetML, plan.thirdPresetML]
    }

    static func savePlan(
        domainDay: DomainDay,
        now: Date = .now,
        in context: ModelContext,
        _ apply: (HydrationPlanRecord) -> Void
    ) throws {
        let plan = fetchOrCreate(in: context, now: now)
        apply(plan)
        plan.updatedAt = now
        HydrationRecords.emitFact(
            kind: HydrationFactKind.planEdited,
            domainDay: PersistedDomainDay.encode(domainDay),
            now: now,
            in: context
        )
        try PlanEditingService.save(context)
    }
}

@MainActor
enum HydrationEntryService {
    /// Logs one entry attributed to the current Domain Day. The first entry
    /// of the day freezes the target snapshot; a crossing of the frozen
    /// target emits the once-per-day `targetReached` fact.
    static func log(
        amountML: Int,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        cutoffMinutes: Int,
        in context: ModelContext
    ) throws {
        let plan = HydrationPlanService.fetchOrCreate(in: context, now: now)
        let dayKey = PersistedDomainDay.encode(
            DomainDay.containing(now, calendar: calendar, cutoffMinutes: cutoffMinutes)
        )
        let entry = HydrationEntryRecord(amountML: amountML, consumedAt: now, domainDay: dayKey)
        context.insert(entry)

        let dayRecord = HydrationRecords.ensureDayRecord(for: dayKey, plan: plan, now: now, in: context)
        if dayRecord.firstEntryAt == nil {
            // Freeze: snapshot stops tracking plan edits from here on.
            dayRecord.targetMLSnapshot = plan.targetML
            dayRecord.firstEntryAt = now
            dayRecord.updatedAt = now
        }

        HydrationRecords.emitFact(
            kind: HydrationFactKind.entryLogged,
            domainDay: dayKey,
            subjectID: entry.id,
            now: now,
            in: context
        )
        HydrationRecords.emitTargetReachedOnce(dayKey: dayKey, dayRecord: dayRecord, now: now, in: context)
        try PlanEditingService.save(context)
    }

    /// Soft-deletes the most recent active entry of the current Domain Day.
    @discardableResult
    static func undoLatest(
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        cutoffMinutes: Int,
        in context: ModelContext
    ) throws -> Bool {
        let dayKey = PersistedDomainDay.encode(
            DomainDay.containing(now, calendar: calendar, cutoffMinutes: cutoffMinutes)
        )
        let entries = HydrationRecords.activeEntries(
            for: dayKey,
            in: (try? context.fetch(FetchDescriptor<HydrationEntryRecord>())) ?? []
        )
        guard let latest = entries.last else { return false }

        latest.deletedAt = now
        latest.updatedAt = now
        try PlanEditingService.save(context)
        return true
    }

    /// Per-entry correction from history. Time stays within the entry's own
    /// day; the freeze marker and already-emitted facts are untouched.
    static func edit(
        _ entry: HydrationEntryRecord,
        amountML: Int,
        consumedAt: Date,
        now: Date = .now,
        in context: ModelContext
    ) throws {
        entry.amountML = amountML
        entry.consumedAt = consumedAt
        entry.updatedAt = now

        if let dayRecord = HydrationRecords.dayRecord(
            for: entry.domainDay,
            in: (try? context.fetch(FetchDescriptor<HydrationDayRecord>())) ?? []
        ) {
            HydrationRecords.emitTargetReachedOnce(
                dayKey: entry.domainDay,
                dayRecord: dayRecord,
                now: now,
                in: context
            )
        }
        try PlanEditingService.save(context)
    }

    /// Soft delete from history. The `targetReached` fact is never revoked:
    /// recompute-safe exactly-once semantics.
    static func delete(
        _ entry: HydrationEntryRecord,
        now: Date = .now,
        in context: ModelContext
    ) throws {
        entry.deletedAt = now
        entry.updatedAt = now
        try PlanEditingService.save(context)
    }
}
