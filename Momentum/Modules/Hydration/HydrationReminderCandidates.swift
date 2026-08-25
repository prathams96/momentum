import Foundation
import MomentumCore
import SwiftData

extension HydrationModuleAdapter: ReminderCandidateProviding {
    /// Checkpoint reminders driven purely by `HydrationEngine.dueCheckpoints`.
    /// Derived slots are appended (deduped) to the day record's fired-slot
    /// list so repeated derivations never re-fire; the orchestrator's save in
    /// `reconcileAndNotify` persists that mutation. Target-reached and master-
    /// toggle suppression emerge naturally: no candidates → the scheduler's
    /// diff cancels pending ones.
    func reminderCandidates(in context: ModuleContext) -> [ScheduledReminder] {
        let modelContext = context.modelContext
        let plan = HydrationPlanService.fetchOrCreate(in: modelContext, now: context.now)
        let dayKey = PersistedDomainDay.encode(context.currentDomainDay)

        let entries = (try? modelContext.fetch(FetchDescriptor<HydrationEntryRecord>())) ?? []
        let consumed = HydrationRecords.total(intake: HydrationRecords.activeEntries(for: dayKey, in: entries))
        let dayRecord = HydrationRecords.dayRecord(
            for: dayKey,
            in: (try? modelContext.fetch(FetchDescriptor<HydrationDayRecord>())) ?? []
        )
        let targetML = dayRecord?.targetMLSnapshot ?? plan.targetML

        var firedSlots = HydrationRecords.firedSlots(from: dayRecord?.firedCheckpointSlotsRaw ?? "")
        let dueSlots = HydrationEngine.dueCheckpoints(
            now: context.now,
            calendar: context.calendar,
            checkpointsEnabled: plan.remindersEnabled,
            checkpointMinutes: HydrationPlanService.checkpointMinutes(of: plan),
            targetML: targetML,
            consumedML: consumed,
            targetReached: consumed >= targetML,
            alreadyFiredSlots: firedSlots
        )
        guard !dueSlots.isEmpty else { return [] }

        // Cap/idempotency ledger lives on the day record; reconcileAndNotify's
        // trailing save persists it without any provider-side write.
        let record = dayRecord ?? HydrationRecords.ensureDayRecord(
            for: dayKey,
            plan: plan,
            now: context.now,
            in: modelContext
        )
        firedSlots.formUnion(dueSlots)
        record.firedCheckpointSlotsRaw = HydrationRecords.encode(firedSlots: firedSlots)
        record.updatedAt = context.now

        return dueSlots.map { slot in
            ScheduledReminder(
                identifier: "hydration.reminder.\(dayKey).\(slot)",
                title: "Hydration check-in",
                body: "You are behind your water pace for today.",
                categoryIdentifier: MomentumNotificationCategory.hydrationCheckIn,
                dateComponents: context.calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: PersistedDomainDay.date(
                        for: context.currentDomainDay,
                        calendar: context.calendar,
                        hour: slot / 60,
                        minute: slot % 60
                    ) ?? context.now
                ),
                userInfo: [
                    "kind": "hydrationReminder",
                    "domainDay": dayKey,
                    "slot": String(slot),
                ]
            )
        }
    }
}
