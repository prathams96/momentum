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
    @State private var correctionError: String?

    private let calendar = Calendar.autoupdatingCurrent

    private var today: DomainDay {
        ScheduleProjection.currentDomainDay(
            settings: settings,
            now: .now,
            calendar: calendar
        )
    }

    private var adherenceFacts: [HistoryAdherenceFact] {
        HistoryProjection.facts(
            sessions: sessions,
            workoutEvents: workoutEvents,
            nutritionDays: nutritionDays,
            careOccurrences: careOccurrences
        )
    }

    private var filteredDays: [DomainDay] {
        let sessionDays: [DomainDay] = category.includes(.workouts)
            ? sessions.compactMap { session in
                guard session.deletedAt == nil else { return nil }
                return PersistedDomainDay.decode(
                    session.completionDomainDay ?? session.scheduledDomainDay
                )
            }
            : []
        let eventDays: [DomainDay] = category.includes(.workouts)
            ? workoutEvents.compactMap {
                $0.deletedAt == nil ? PersistedDomainDay.decode($0.domainDay) : nil
            }
            : []
        let nutritionFactDays: [DomainDay] = category.includes(.nutrition)
            ? nutritionDays.compactMap { PersistedDomainDay.decode($0.domainDay) }
                + foodEntries.compactMap {
                    $0.deletedAt == nil ? PersistedDomainDay.decode($0.domainDay) : nil
                }
            : []
        let careDays: [DomainDay] = category.includes(.care)
            ? careOccurrences.compactMap { PersistedDomainDay.decode($0.dueDomainDay) }
            : []
        let measurementDays: [DomainDay] = category.includes(.measurements)
            ? measurements.compactMap {
                $0.deletedAt == nil ? PersistedDomainDay.decode($0.domainDay) : nil
            }
            : []

        var days = Set<DomainDay>()
        days.formUnion(sessionDays)
        days.formUnion(eventDays)
        days.formUnion(nutritionFactDays)
        days.formUnion(careDays)
        days.formUnion(measurementDays)
        return days.sorted(by: >)
    }

    private var streaks: HistoryStreakSummary {
        HistoryProjection.streaks(facts: adherenceFacts, calendar: calendar)
    }

    var body: some View {
        List {
            Section {
                Picker("Category", selection: $category) {
                    ForEach(HistoryCategory.allCases) { option in
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

                HistoryStreakSummaryView(summary: streaks, category: category)
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
                                careOccurrences: careOccurrences,
                                measurements: measurements
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
        .navigationDestination(for: DomainDay.self) { day in
            HistoryDayDetail(
                day: day,
                category: category,
                sessions: sessions,
                workoutEvents: workoutEvents,
                nutritionDays: nutritionDays,
                foodEntries: foodEntries,
                careOccurrences: careOccurrences,
                measurements: measurements,
                editFood: { entry in
                    presentedSheet = .editFood(id: entry.id, domainDay: entry.domainDay)
                },
                backdateFood: { entry in
                    presentedSheet = .backdate(.food(id: entry.id, currentDay: entry.domainDay))
                },
                backdateMeasurement: { measurement in
                    presentedSheet = .backdate(.measurement(
                        id: measurement.id,
                        currentDay: measurement.domainDay
                    ))
                },
                requestFoodDeletion: { pendingDeletion = .food(id: $0.id) },
                requestMeasurementDeletion: { pendingDeletion = .measurement(id: $0.id) },
                requestWorkoutDeletion: requestWorkoutDeletion
            )
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
    func includes(_ category: HistoryCategory) -> Bool {
        self == .all || self == category
    }
}
