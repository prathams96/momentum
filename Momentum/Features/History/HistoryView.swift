import MomentumCore
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var settings: [AppSettingsRecord]
    @Query private var workouts: [WorkoutTemplateRecord]
    @Query private var anchors: [CycleAnchorRecord]
    @Query private var sessions: [WorkoutSessionRecord]
    @Query private var workoutEvents: [WorkoutDayEventRecord]
    @Query private var nutritionDays: [NutritionDayRecord]
    @Query private var foodEntries: [FoodEntryRecord]
    @Query private var careOccurrences: [CareOccurrenceRecord]
    @Query private var measurements: [BodyMeasurementRecord]

    @State private var category: HistoryCategory = .all
    @State private var heatmapPage = 0
    @State private var presentedSheet: HistorySheetDestination?
    @State private var pendingDeletion: HistoryDeletionRequest?
    @State private var lastDeletion: HistoryDeletionRequest?
    @State private var pendingCareUndo: HistoryCareUndoRequest?
    @State private var correctionError: String?

    private let calendar = Calendar.autoupdatingCurrent

    private var today: DomainDay {
        ScheduleProjection.currentDomainDay(
            settings: settings,
            now: .now,
            calendar: calendar
        )
    }

    private var canonicalSettings: AppSettingsRecord? {
        AppSettingsRecord.canonical(in: settings)
    }

    private var moduleContextValue: ModuleContext {
        ModuleContext.make(in: modelContext, settings: canonicalSettings, calendar: calendar)
    }

    private var historyContributors: [any HistoryContributing] {
        ModuleRegistry.standard
            .enabledModules(ModuleEnablementStore.enabledIDs(from: canonicalSettings))
            .compactMap { $0 as? any HistoryContributing }
    }

    private var adherenceFacts: [HistoryAdherenceFact] {
        historyContributors.flatMap { $0.historyFacts(in: moduleContextValue) }
    }

    private var filteredDays: [DomainDay] {
        var days = Set<DomainDay>()
        if category.includes(.workouts) {
            days.formUnion(adherenceFacts.filter { $0.category == .workouts }.map(\.day))
        }
        if category.includes(.nutrition) {
            days.formUnion(adherenceFacts.filter { $0.category == .nutrition }.map(\.day))
            // Facts only map finalized-day records; food-entry-only days stay visible.
            days.formUnion(foodEntries.compactMap {
                $0.deletedAt == nil ? PersistedDomainDay.decode($0.domainDay) : nil
            })
        }
        if category.includes(.care) {
            days.formUnion(adherenceFacts.filter { $0.category == .care }.map(\.day))
        }
        return days.sorted(by: >)
    }

    var body: some View {
        let context = moduleContextValue
        List {
            Section {
                Picker("Category", selection: $category) {
                    ForEach(HistoryCategory.allCases.filter(\.isUserSelectable)) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityHint("Filters the heatmap and chronological history")

                HistoryHeatmapView(
                    currentDay: today,
                    page: $heatmapPage,
                    calendar: calendar
                ) { day in
                    HistoryProjection.adherenceScore(
                        on: day,
                        facts: adherenceFacts,
                        category: category
                    )
                }

                HStack(spacing: MomentumSpacing.md) {
                    ForEach(Array(historyContributors.enumerated()), id: \.offset) { _, contributor in
                        streakTile(contributor, context: context)
                    }
                }
            }

            if filteredDays.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No \(category.title.lowercased()) history",
                        systemImage: "calendar",
                        description: Text("Completed activities and logged facts will appear here.")
                    )
                }
            } else {
                ForEach(filteredDays, id: \.self) { day in
                    Section {
                        NavigationLink(value: day) {
                            HistoryDayRow(
                                day: day,
                                category: category,
                                sessions: sessions,
                                workoutEvents: workoutEvents,
                                nutritionDays: nutritionDays,
                                foodEntries: foodEntries,
                                careOccurrences: careOccurrences
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
        .navigationDestination(for: DomainDay.self) { day in
            HistoryDayDetail(day: day)
                .environment(\.historyDayActions, HistoryDayActions(
                    editFood: { entry in
                        presentedSheet = .editFood(id: entry.id, domainDay: entry.domainDay)
                    },
                    backdateFood: { entry in
                        presentedSheet = .backdate(.food(id: entry.id, currentDay: entry.domainDay))
                    },
                    requestFoodDeletion: { pendingDeletion = .food(id: $0.id) },
                    requestWorkoutDeletion: requestWorkoutDeletion,
                    editWorkoutCompletion: { session in
                        guard let finishedAt = session.finishedAt else { return }
                        presentedSheet = .editWorkoutCompletion(
                            id: session.id,
                            currentCompletion: finishedAt
                        )
                    },
                    toggleNutritionFinalization: toggleNutritionFinalization,
                    requestCareCompletionUndo: { occurrence in
                        pendingCareUndo = HistoryCareUndoRequest(
                            occurrenceID: occurrence.id,
                            routineName: occurrence.routineNameSnapshot
                        )
                    }
                ))
        }
        .toolbar {
            if lastDeletion != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Undo", action: undoLastDeletion)
                        .accessibilityHint("Restores the most recently deleted history record")
                }
            }
        }
        .sheet(item: $presentedSheet, onDismiss: reconcileHistory) { destination in
            switch destination {
            case let .editFood(id, domainDay):
                FoodEntrySheet(domainDay: domainDay, existingEntryID: id)
            case let .editWorkoutCompletion(id, currentCompletion):
                HistoryWorkoutCompletionSheet(
                    sessionID: id,
                    currentCompletion: currentCompletion
                )
            case let .backdate(target):
                HistoryBackdateSheet(target: target)
            }
        }
        .confirmationDialog(
            pendingDeletion?.title ?? "Delete history?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { deletion in
            Button("Delete", role: .destructive) {
                performDeletion(deletion)
            }
            Button("Cancel", role: .cancel) {}
        } message: { deletion in
            Text(deletion.message)
        }
        .confirmationDialog(
            "Undo care completion?",
            isPresented: Binding(
                get: { pendingCareUndo != nil },
                set: { if !$0 { pendingCareUndo = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingCareUndo
        ) { request in
            Button("Undo completion") {
                undoCareCompletion(request)
            }
            Button("Cancel", role: .cancel) {}
        } message: { request in
            Text("\(request.routineName), its tasks, recurrence, adherence, streaks, and reminders will be recalculated.")
        }
        .alert("History couldn’t be refreshed", isPresented: Binding(
            get: { correctionError != nil },
            set: { if !$0 { correctionError = nil } }
        )) {
            Button("Retry", action: reconcileHistory)
            Button("OK", role: .cancel) {}
        } message: {
            Text(correctionError ?? "The correction was saved. Try refreshing again.")
        }
    }

    private func streakTile(
        _ contributor: any HistoryContributing,
        context: ModuleContext
    ) -> some View {
        let streak = contributor.categoryStreak(asOf: today, in: context) ?? 0
        return VStack(alignment: .leading, spacing: 2) {
            Label(contributor.metadata.displayName, systemImage: contributor.metadata.symbolName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("\(streak)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(streak == 1 ? "opportunity/day" : "opportunities/days")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func requestWorkoutDeletion(_ session: WorkoutSessionRecord) {
        let preview = HistoryCorrectionProjection.workoutDeletionPreview(
            sessionID: session.id,
            workouts: workouts,
            anchors: anchors,
            sessions: sessions,
            settings: settings,
            now: .now,
            calendar: calendar
        )
        pendingDeletion = .workout(id: session.id, preview: preview)
    }

    private func performDeletion(_ deletion: HistoryDeletionRequest) {
        let changed: Bool
        switch deletion {
        case let .food(id):
            guard let record = foodEntries.first(where: { $0.id == id }) else { return }
            record.deletedAt = .now
            record.updatedAt = .now
            changed = true
        case let .measurement(id):
            guard let record = measurements.first(where: { $0.id == id }) else { return }
            record.deletedAt = .now
            record.updatedAt = .now
            changed = true
        case let .workout(id, _):
            guard let record = sessions.first(where: { $0.id == id }) else { return }
            record.deletedAt = .now
            record.updatedAt = .now
            changed = true
        }

        guard changed else { return }
        do {
            try modelContext.save()
            lastDeletion = deletion
            pendingDeletion = nil
            reconcileHistory()
        } catch {
            correctionError = "The record is still visible because the deletion could not be saved."
        }
    }

    private func toggleNutritionFinalization(_ day: DomainDay) {
        do {
            try HistoryCorrectionService.toggleNutritionFinalization(
                domainDay: day,
                in: modelContext,
                calendar: calendar
            )
            reconcileHistory()
        } catch {
            correctionError = "Nutrition logging could not be changed. No partial correction was kept."
        }
    }

    private func undoCareCompletion(_ request: HistoryCareUndoRequest) {
        do {
            try HistoryCorrectionService.undoCareCompletion(
                occurrenceID: request.occurrenceID,
                in: modelContext,
                calendar: calendar
            )
            pendingCareUndo = nil
            reconcileHistory()
        } catch {
            correctionError = "Care completion could not be undone. No partial correction was kept."
        }
    }

    private func undoLastDeletion() {
        guard let deletion = lastDeletion else { return }
        switch deletion {
        case let .food(id):
            foodEntries.first(where: { $0.id == id })?.deletedAt = nil
        case let .measurement(id):
            measurements.first(where: { $0.id == id })?.deletedAt = nil
        case let .workout(id, _):
            sessions.first(where: { $0.id == id })?.deletedAt = nil
        }

        do {
            try modelContext.save()
            lastDeletion = nil
            reconcileHistory()
        } catch {
            correctionError = "The record could not be restored. Try again."
        }
    }

    private func reconcileHistory() {
        Task { @MainActor in
            do {
                try await DailyReconciler.reconcileAndNotify(
                    in: modelContext,
                    calendar: calendar
                )
            } catch {
                correctionError = "The correction was saved, but schedules and reminders could not be refreshed."
            }
        }
    }
}

private extension HistoryCategory {
    /// Measurements stay in schema and export but are no longer a filterable
    /// history surface.
    var isUserSelectable: Bool {
        self != .measurements
    }

    func includes(_ category: HistoryCategory) -> Bool {
        self == .all || self == category
    }
}
