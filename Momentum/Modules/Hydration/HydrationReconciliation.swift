import Foundation
import MomentumCore
import SwiftData

/// Hydration-side day-rollover engine. Ensures the current day's record
/// exists with a plan snapshot; while no entry has been logged the snapshot
/// keeps tracking plan edits. Idempotent; never saves — the orchestrator
/// owns the single save at the end of reconciliation.
@MainActor
enum HydrationReconciliationEngine {
    static func reconcile(
        previousDay: DomainDay,
        currentDay: DomainDay,
        in context: ModuleContext
    ) throws {
        let modelContext = context.modelContext
        let plan = HydrationPlanService.fetchOrCreate(in: modelContext, now: context.now, unitSystemRaw: context.unitSystemRaw)
        let dayKey = PersistedDomainDay.encode(currentDay)
        let dayRecords = (try? modelContext.fetch(FetchDescriptor<HydrationDayRecord>())) ?? []

        if let record = HydrationRecords.dayRecord(for: dayKey, in: dayRecords) {
            guard record.firstEntryAt == nil else { return }
            // Still unfrozen: keep following plan edits.
            if record.targetMLSnapshot != plan.targetML {
                record.targetMLSnapshot = plan.targetML
                record.updatedAt = context.now
            }
        } else {
            let record = HydrationDayRecord(domainDay: dayKey, targetMLSnapshot: plan.targetML)
            modelContext.insert(record)
        }
    }
}

extension HydrationModuleAdapter: ReconcilingModule {
    func reconcile(previousDay: DomainDay, currentDay: DomainDay, in context: ModuleContext) throws {
        try HydrationReconciliationEngine.reconcile(
            previousDay: previousDay,
            currentDay: currentDay,
            in: context
        )
    }
}
