import XCTest
import MomentumCore
import SwiftData
@testable import Momentum

@MainActor
final class HydrationModuleTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    // MARK: - Helpers

    /// Runs `body` with a preview-store context whose settings record exists.
    /// The container is kept alive for the whole body — dropping it while the
    /// context survives traps on the next fetch.
    private func withStore<T>(_ body: (ModelContext) throws -> T) rethrows -> T {
        let container = try! ModelContainerFactory.makePreview()
        let context = container.mainContext
        context.insert(AppSettingsRecord(domainDayCutoffMinutes: 180))
        try? context.save()
        return try withExtendedLifetime(container) {
            try body(context)
        }
    }

    private func date(_ day: DomainDay, hour: Int, minute: Int = 0) -> Date {
        PersistedDomainDay.date(for: day, calendar: calendar, hour: hour, minute: minute)!
    }

    private func reconcile(_ context: ModelContext, now: Date) throws {
        try DailyReconciler.reconcile(in: context, now: now, calendar: calendar, registry: .standard)
    }

    private func dayRecords(in context: ModelContext) throws -> [HydrationDayRecord] {
        try context.fetch(FetchDescriptor<HydrationDayRecord>())
    }

    private func facts(kind targetKind: String? = nil, in context: ModelContext) throws -> [ModuleFactRecord] {
        try context.fetch(FetchDescriptor<ModuleFactRecord>()).filter {
            $0.moduleIDRaw == HydrationFactKind.moduleIDRaw && (targetKind == nil || $0.kindRaw == targetKind)
        }
    }

    // MARK: - Domain-day attribution across the cutoff

    func testEntryLoggingAttributesAcrossTheCutoffToTheEarlierDomainDay() throws {
        try withStore { context in
            let day = DomainDay(year: 2026, month: 8, day: 2)

            // 01:00 on Aug 3 is before the 03:00 cutoff → still Domain Day Aug 2.
            let lateNight = date(day.adding(days: 1, calendar: calendar), hour: 1)
            try HydrationEntryService.log(amountML: 250, now: lateNight, calendar: calendar, cutoffMinutes: 180, in: context)

            let entries = try context.fetch(FetchDescriptor<HydrationEntryRecord>())
            XCTAssertEqual(entries.map(\.domainDay), ["2026-08-02"])

            // Midday logging attributes to the same calendar day.
            let midday = date(day, hour: 12)
            try HydrationEntryService.log(amountML: 500, now: midday, calendar: calendar, cutoffMinutes: 180, in: context)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<HydrationEntryRecord>()), 2)
            XCTAssertTrue(
                try context.fetch(FetchDescriptor<HydrationEntryRecord>()).allSatisfy { $0.domainDay == "2026-08-02" }
            )
        }
    }

    // MARK: - Snapshot semantics

    func testSnapshotTracksPlanEditsUntilFirstEntryThenFreezesPerDay() throws {
        try withStore { context in
            let day = DomainDay(year: 2026, month: 8, day: 2)
            let now = date(day, hour: 12)

            let plan = HydrationPlanService.fetchOrCreate(in: context)
            plan.targetML = 2500

            try reconcile(context, now: now)
            XCTAssertEqual(try dayRecords(in: context).first { $0.domainDay == "2026-08-02" }?.targetMLSnapshot, 2500)

            // Edit before the first entry: the snapshot follows the plan.
            plan.targetML = 3000
            plan.updatedAt = now
            try reconcile(context, now: now.addingTimeInterval(60))
            XCTAssertEqual(try dayRecords(in: context).first { $0.domainDay == "2026-08-02" }?.targetMLSnapshot, 3000)

            // First entry freezes the snapshot.
            try HydrationEntryService.log(amountML: 250, now: now.addingTimeInterval(120), calendar: calendar, cutoffMinutes: 180, in: context)
            let frozen = try XCTUnwrap(dayRecords(in: context).first { $0.domainDay == "2026-08-02" })
            XCTAssertNotNil(frozen.firstEntryAt)
            XCTAssertEqual(frozen.targetMLSnapshot, 3000)

            // Plan edits after freezing no longer move the snapshot.
            plan.targetML = 3500
            plan.updatedAt = now.addingTimeInterval(180)
            try reconcile(context, now: now.addingTimeInterval(240))
            XCTAssertEqual(frozen.targetMLSnapshot, 3000)

            // A past day keeps its own snapshot.
            let yesterday = HydrationDayRecord(domainDay: "2026-08-01", targetMLSnapshot: 2000)
            context.insert(yesterday)
            try context.save()
            try reconcile(context, now: now.addingTimeInterval(300))
            XCTAssertEqual(yesterday.targetMLSnapshot, 2000)
        }
    }

    // MARK: - Undo and exactly-once targetReached fact

    func testUndoSoftDeletesLatestAndTargetReachedFactIsEmittedExactlyOnce() throws {
        try withStore { context in
            let day = DomainDay(year: 2026, month: 8, day: 2)
            let now = date(day, hour: 12)
            let plan = HydrationPlanService.fetchOrCreate(in: context)
            plan.targetML = 300

            try reconcile(context, now: now)

            try HydrationEntryService.log(amountML: 200, now: now, calendar: calendar, cutoffMinutes: 180, in: context)
            XCTAssertNil(try facts(kind: HydrationFactKind.targetReached, in: context).first)

            // Crossing the frozen target emits the fact exactly once.
            let secondTime = now.addingTimeInterval(60)
            try HydrationEntryService.log(amountML: 250, now: secondTime, calendar: calendar, cutoffMinutes: 180, in: context)
            XCTAssertEqual(try facts(kind: HydrationFactKind.targetReached, in: context).count, 1)
            XCTAssertEqual(try facts(kind: HydrationFactKind.entryLogged, in: context).count, 2)

            // Undo removes the latest entry only (soft delete).
            try HydrationEntryService.undoLatest(now: secondTime.addingTimeInterval(30), calendar: calendar, cutoffMinutes: 180, in: context)
            let entries = try context.fetch(FetchDescriptor<HydrationEntryRecord>())
                .sorted { ($0.consumedAt, $0.id.uuidString) < ($1.consumedAt, $1.id.uuidString) }
            XCTAssertEqual(entries.count, 2)
            XCTAssertNil(entries[0].deletedAt)
            XCTAssertNotNil(entries[1].deletedAt)

            // Re-crossing after delete/re-log does not duplicate the fact.
            try HydrationEntryService.log(amountML: 400, now: secondTime.addingTimeInterval(60), calendar: calendar, cutoffMinutes: 180, in: context)
            XCTAssertEqual(try facts(kind: HydrationFactKind.targetReached, in: context).count, 1)

            // Plan saves emit their own fact.
            try HydrationPlanService.savePlan(domainDay: day, now: .now, in: context) { saved in
                saved.targetML = 320
            }
            XCTAssertEqual(try facts(kind: HydrationFactKind.planEdited, in: context).count, 1)
        }
    }

    // MARK: - Reminder candidates

    private func reminderSetup(
        targetML: Int,
        remindersEnabled: Bool,
        _ body: (ModelContext, DomainDay) throws -> Void
    ) rethrows {
        try withStore { context in
            let day = DomainDay(year: 2026, month: 8, day: 2)
            let plan = HydrationPlanService.fetchOrCreate(in: context)
            plan.targetML = targetML
            plan.remindersEnabled = remindersEnabled
            try reconcile(context, now: date(day, hour: 12))
            try body(context, day)
        }
    }

    private func derive(_ context: ModelContext, at now: Date) -> [ScheduledReminder] {
        DailyReconciler.deriveReminders(
            settings: AppSettingsRecord.canonical(in: (try? context.fetch(FetchDescriptor<AppSettingsRecord>())) ?? []),
            in: context,
            now: now,
            calendar: calendar
        )
    }

    /// The pipeline also carries other modules' candidates; scope to hydration.
    private func hydration(_ reminders: [ScheduledReminder]) -> [ScheduledReminder] {
        reminders.filter { $0.categoryIdentifier == MomentumNotificationCategory.hydrationCheckIn }
    }

    func testBehindPaceAtCheckpointEmitsNamespacedSlotReminder() throws {
        try reminderSetup(targetML: 2500, remindersEnabled: true) { context, day in
            // At 15:00 with nothing logged: slot 900 is due; 11:00 is beyond
            // the retro-emission grace and 19:00 is beyond the lookahead.
            let reminders = hydration(derive(context, at: date(day, hour: 15)))
            XCTAssertEqual(reminders.count, 1)
            let reminder = try XCTUnwrap(reminders.first)
            XCTAssertEqual(reminder.identifier, "hydration.reminder.2026-08-02.900")
            XCTAssertEqual(reminder.title, "Hydration check-in")
            XCTAssertEqual(reminder.body, "You are behind your water pace for today.")
            XCTAssertEqual(reminder.categoryIdentifier, MomentumNotificationCategory.hydrationCheckIn)
            XCTAssertEqual(reminder.userInfo["kind"], "hydrationReminder")
            XCTAssertEqual(reminder.userInfo["domainDay"], "2026-08-02")
            XCTAssertEqual(reminder.userInfo["slot"], "900")
        }
    }

    func testAheadOfPaceAndReachedTargetEmitNoReminders() throws {
        try reminderSetup(targetML: 2500, remindersEnabled: true) { context, day in
            // Ahead of linear pace for 15:00 (expected ≈1563 ml).
            try HydrationEntryService.log(amountML: 1600, now: date(day, hour: 14), calendar: calendar, cutoffMinutes: 180, in: context)
            XCTAssertEqual(hydration(derive(context, at: date(day, hour: 15))), [])

            // At target and beyond: reached → nothing fires even at checkpoints.
            try HydrationEntryService.log(amountML: 1000, now: date(day, hour: 16), calendar: calendar, cutoffMinutes: 180, in: context)
            XCTAssertEqual(hydration(derive(context, at: date(day, hour: 19))), [])
        }
    }

    func testMasterToggleOffEmitsNoReminders() throws {
        try reminderSetup(targetML: 2500, remindersEnabled: false) { context, day in
            XCTAssertEqual(hydration(derive(context, at: date(day, hour: 15))), [])
        }
    }

    func testQuietHoursSuppressReminders() throws {
        try reminderSetup(targetML: 2500, remindersEnabled: true) { context, day in
            XCTAssertEqual(hydration(derive(context, at: date(day, hour: 7))), [])
            XCTAssertEqual(hydration(derive(context, at: date(day, hour: 22))), [])
        }
    }

    func testRepeatedDerivationDoesNotDuplicateFiredSlots() throws {
        try reminderSetup(targetML: 2500, remindersEnabled: true) { context, day in
            let at15 = date(day, hour: 15)

            let first = hydration(derive(context, at: at15))
            XCTAssertEqual(first.count, 1)

            let record = try XCTUnwrap(dayRecords(in: context).first { $0.domainDay == "2026-08-02" })
            XCTAssertEqual(record.firedCheckpointSlotsRaw, "900")

            // Second derivation: slot already fired, nothing re-emitted.
            XCTAssertEqual(hydration(derive(context, at: at15.addingTimeInterval(60))), [])
            XCTAssertEqual(record.firedCheckpointSlotsRaw, "900")

            // The next checkpoint still fires later and appends without dupes.
            let evening = hydration(derive(context, at: date(day, hour: 19, minute: 5)))
            XCTAssertEqual(evening.map(\.identifier), ["hydration.reminder.2026-08-02.1140"])
            XCTAssertEqual(record.firedCheckpointSlotsRaw, "900,1140")
        }
    }

    func testDisablingHydrationYieldsZeroHydrationCandidatesFromPipeline() throws {
        try reminderSetup(targetML: 2500, remindersEnabled: true) { context, day in
            let settings = try XCTUnwrap(AppSettingsRecord.canonical(
                in: context.fetch(FetchDescriptor<AppSettingsRecord>())
            ))
            ModuleEnablementStore.apply([
                BuiltInModuleID.workout, BuiltInModuleID.nutrition, BuiltInModuleID.care,
            ], to: settings)
            try context.save()

            let reminders = derive(context, at: date(day, hour: 15))
            XCTAssertFalse(reminders.contains { $0.categoryIdentifier == MomentumNotificationCategory.hydrationCheckIn })
        }
    }

    // MARK: - Export definition

    func testExportDefinitionProducesExpectedHeaderAndRows() throws {
        try withStore { context in
            let adapter = HydrationModuleAdapter()

            let definitions = adapter.exportDefinitions()
            XCTAssertEqual(definitions.count, 1)
            let definition = try XCTUnwrap(definitions.first)
            XCTAssertEqual(definition.fileName, "hydration.csv")
            XCTAssertEqual(definition.header, [
                "id", "amount_ml", "consumed_at", "domain_day", "deleted_at", "created_at", "updated_at",
            ])

            let entry = HydrationEntryRecord(
                amountML: 500,
                consumedAt: date(DomainDay(year: 2026, month: 8, day: 2), hour: 10),
                domainDay: "2026-08-02"
            )
            context.insert(entry)
            try context.save()

            let rows = try definition.rowsProvider(context)
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows[0][1], "500")
            XCTAssertEqual(rows[0][3], "2026-08-02")
            XCTAssertEqual(rows[0][4], "")
        }
    }

    // MARK: - Registry contract + history

    func testRegistryContributionsExistWhenEnabled() throws {
        try withStore { context in
            let day = DomainDay(year: 2026, month: 8, day: 2)
            try reconcile(context, now: date(day, hour: 12))

            let settings = AppSettingsRecord.canonical(in: try context.fetch(FetchDescriptor<AppSettingsRecord>()))
            let moduleContext = ModuleContext.make(in: context, settings: settings, now: date(day, hour: 13), calendar: calendar)
            let module = try XCTUnwrap(ModuleRegistry.standard.module(with: BuiltInModuleID.hydration))

            let contributor = try XCTUnwrap(module as? TodayContributing)
            let contribution = try XCTUnwrap(contributor.todayContribution(in: moduleContext))
            XCTAssertEqual(contribution.state, .optional)

            XCTAssertNotNil((module as? PlanContributing)?.planSection(in: moduleContext))
            XCTAssertNotNil((module as? InsightsContributing)?.insightsSection(in: moduleContext))
            XCTAssertEqual((module as? ExportDefinitionProviding)?.exportDefinitions().count, 1)
            XCTAssertEqual((module as? ReminderCandidateProviding)?.reminderCandidates(in: moduleContext), [])
        }
    }

    func testHistoryFactsDaySectionsAndStreakReflectSnapshots() throws {
        try withStore { context in
            let day = DomainDay(year: 2026, month: 8, day: 2)
            let plan = HydrationPlanService.fetchOrCreate(in: context)
            plan.targetML = 1000

            let previous = day.adding(days: -1, calendar: calendar)
            context.insert(HydrationDayRecord(
                domainDay: PersistedDomainDay.encode(previous),
                targetMLSnapshot: 1500,
                firstEntryAt: date(previous, hour: 9)
            ))
            context.insert(HydrationEntryRecord(
                amountML: 1500,
                consumedAt: date(previous, hour: 9),
                domainDay: PersistedDomainDay.encode(previous)
            ))
            try context.save()
            try reconcile(context, now: date(day, hour: 9))
            try HydrationEntryService.log(amountML: 400, now: date(day, hour: 9), calendar: calendar, cutoffMinutes: 180, in: context)

            let settings = AppSettingsRecord.canonical(in: try context.fetch(FetchDescriptor<AppSettingsRecord>()))
            let moduleContext = ModuleContext.make(in: context, settings: settings, now: date(day, hour: 10), calendar: calendar)
            let module = try XCTUnwrap(
                ModuleRegistry.standard.module(with: BuiltInModuleID.hydration) as? HistoryContributing
            )

            let facts = module.historyFacts(in: moduleContext)
            XCTAssertEqual(facts.count, 2)
            XCTAssertTrue(facts.contains {
                $0.day == previous && $0.category == .hydration && $0.isCompleted
            })
            XCTAssertTrue(facts.contains {
                $0.day == day && $0.category == .hydration && !$0.isCompleted
            })

            XCTAssertEqual(module.historyDaySections(for: day, in: moduleContext).count, 1)

            // Yesterday completed, today incomplete: the streak ending today
            // is 0; ending yesterday it is 1.
            XCTAssertEqual(module.categoryStreak(asOf: day, in: moduleContext), 0)
            XCTAssertEqual(module.categoryStreak(asOf: previous, in: moduleContext), 1)

            // The hydration module folds its day into one scored activity.
            let activities = (module as? any HistoryContributing)?
                .adherenceActivities(on: previous, facts: module.historyFacts(in: moduleContext)) ?? []
            let score = AdherenceEngine().dailyScore(activities: activities)
            XCTAssertEqual(score, .score(completedCount: 1, dueCount: 1, percentage: 100))
        }
    }
}
