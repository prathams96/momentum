import Foundation
import MomentumCore
import OSLog
import SwiftData

@MainActor
enum DailyReconciler {
    private static let logger = Logger(
        subsystem: "com.pratham.momentum",
        category: "Reconciliation"
    )

    /// Orchestrates day-rollover reconciliation across enabled modules in
    /// registry rank order, then saves once. Each module's failure is scoped:
    /// a failing module is logged and skipped without blocking the others.
    static func reconcile(
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        registry: ModuleRegistry = .standard
    ) throws {
        let interval = MomentumDiagnostics.signposter.beginInterval("DailyReconciliation")
        defer {
            MomentumDiagnostics.signposter.endInterval("DailyReconciliation", interval)
        }

        let settings = AppSettingsRecord.canonical(
            in: try context.fetch(FetchDescriptor<AppSettingsRecord>())
        )
        let moduleContext = ModuleContext.make(
            in: context,
            settings: settings,
            now: now,
            calendar: calendar
        )

        // Keep the enablement ledger in step before modules run so streak
        // pause windows are recorded for the days they cover.
        let enabledIDs = ModuleEnablementStore.enabledIDs(from: settings)
        do {
            try ModuleEnablementLedger.reconcile(
                enabledIDs: enabledIDs,
                currentDay: moduleContext.currentDomainDay,
                in: context,
                registry: registry
            )
        } catch {
            logger.error(
                "Enablement ledger reconcile failed: \(String(describing: error), privacy: .public)"
            )
        }

        let reconcilers = registry
            .enabledModules(enabledIDs)
            .compactMap { $0 as? any ReconcilingModule }
        for reconciler in reconcilers {
            do {
                try reconciler.reconcile(
                    previousDay: moduleContext.previousDomainDay,
                    currentDay: moduleContext.currentDomainDay,
                    in: moduleContext
                )
            } catch {
                logger.error(
                    "Reconciliation failed for module \(reconciler.metadata.id.rawValue, privacy: .public): \(String(describing: error), privacy: .public)"
                )
            }
        }

        try context.save()
    }

    static func reconcileAndNotify(
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) async throws {
        try reconcile(in: context, now: now, calendar: calendar)

        // Milestones are a Core-level projection of the reconciled data; keep
        // their errors non-fatal so notification health never gates them.
        do {
            try MilestoneService.reconcile(in: context, now: now, calendar: calendar)
        } catch {
            logger.error(
                "Milestone reconciliation failed: \(String(describing: error), privacy: .public)"
            )
        }

        let settings = AppSettingsRecord.canonical(
            in: try context.fetch(FetchDescriptor<AppSettingsRecord>())
        )
        let reminders = deriveReminders(
            settings: settings,
            in: context,
            now: now,
            calendar: calendar
        )
        do {
            try await NotificationScheduler().reconcile(reminders)
            settings?.notificationSchedulingStatusRaw = "healthy"
            try context.save()
        } catch {
            settings?.notificationSchedulingStatusRaw = "failed"
            try? context.save()
            throw error
        }
    }

    /// Collects reminder candidates from enabled modules' ReminderCandidateProviding
    /// in registry rank order, then runs them through the generic Core bundler.
    /// Internal so tests can exercise the full pipeline synchronously.
    static func deriveReminders(
        settings: AppSettingsRecord?,
        in context: ModelContext,
        now: Date,
        calendar: Calendar,
        registry: ModuleRegistry = .standard
    ) -> [ScheduledReminder] {
        let moduleContext = ModuleContext.make(
            in: context,
            settings: settings,
            now: now,
            calendar: calendar
        )
        let enabled = ModuleEnablementStore.enabledIDs(from: settings)
        let providers = registry
            .enabledModules(enabled)
            .compactMap { $0 as? any ReminderCandidateProviding }
        let candidates = providers.flatMap { $0.reminderCandidates(in: moduleContext) }
        return ReminderBundler.bundle(
            candidates,
            anchorCategory: MomentumNotificationCategory.eveningCheckIn
        )
    }

    /// Completes a Care Routine through the same mutation boundary used by notification actions.
    /// Returns `false` when the action was already applied or the occurrence no longer exists.
    @discardableResult
    static func completeCareOccurrence(
        occurrenceID: UUID,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> Bool {
        try CareReconciliationEngine.completeOccurrence(
            occurrenceID: occurrenceID,
            in: context,
            now: now,
            calendar: calendar
        )
    }
}
