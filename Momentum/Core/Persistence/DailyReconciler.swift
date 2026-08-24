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

        let reconcilers = registry
            .enabledModules(ModuleEnablementStore.enabledIDs(from: settings))
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
        let occurrences = try context.fetch(FetchDescriptor<CareOccurrenceRecord>())
        let nutritionDays = try context.fetch(FetchDescriptor<NutritionDayRecord>())
        let workouts = try context.fetch(FetchDescriptor<WorkoutTemplateRecord>())
        let anchors = try context.fetch(FetchDescriptor<CycleAnchorRecord>())
        let sessions = try context.fetch(FetchDescriptor<WorkoutSessionRecord>())
        let state = ScheduleProjection.evaluate(
            workouts: workouts,
            anchors: anchors,
            sessions: sessions,
            settings: settings.map { [$0] } ?? [],
            now: now,
            calendar: calendar
        )
        let currentDay = DomainDay.containing(
            now,
            calendar: calendar,
            cutoffMinutes: settings?.domainDayCutoffMinutes ?? 180
        )
        let reminders = ReminderDeriver.reminders(
            scheduleState: state,
            settings: settings,
            occurrences: occurrences,
            nutritionDay: nutritionDays.first { $0.domainDay == PersistedDomainDay.encode(currentDay) },
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
