import MomentumCore
import SwiftData
import SwiftUI

struct HistoryDayDetail: View {
    @Query private var settingsRecords: [AppSettingsRecord]
    let day: DomainDay
    let category: HistoryCategory
    let sessions: [WorkoutSessionRecord]
    let workoutEvents: [WorkoutDayEventRecord]
    let nutritionDays: [NutritionDayRecord]
    let foodEntries: [FoodEntryRecord]
    let careOccurrences: [CareOccurrenceRecord]
    let measurements: [BodyMeasurementRecord]
    let editFood: (FoodEntryRecord) -> Void
    let backdateFood: (FoodEntryRecord) -> Void
    let backdateMeasurement: (BodyMeasurementRecord) -> Void
    let requestFoodDeletion: (FoodEntryRecord) -> Void
    let requestMeasurementDeletion: (BodyMeasurementRecord) -> Void
    let requestWorkoutDeletion: (WorkoutSessionRecord) -> Void
    let editWorkoutCompletion: (WorkoutSessionRecord) -> Void
    let toggleNutritionFinalization: (DomainDay) -> Void
    let requestCareCompletionUndo: (CareOccurrenceRecord) -> Void

    private var dayKey: String { PersistedDomainDay.encode(day) }
    private var unitSystem: UnitSystemOption {
        UnitSystemOption(rawValue: AppSettingsRecord.canonical(in: settingsRecords)?.unitSystemRaw ?? "metric") ?? .metric
    }

    private var daySessions: [WorkoutSessionRecord] {
        sessions
            .filter {
                $0.deletedAt == nil
                    && ($0.completionDomainDay ?? $0.scheduledDomainDay) == dayKey
            }
            .sorted { ($0.finishedAt ?? $0.startedAt) < ($1.finishedAt ?? $1.startedAt) }
    }

    private var dayEvents: [WorkoutDayEventRecord] {
        workoutEvents.filter { $0.deletedAt == nil && $0.domainDay == dayKey }
    }

    private var dayFoods: [FoodEntryRecord] {
        foodEntries
            .filter { $0.deletedAt == nil && $0.domainDay == dayKey }
            .sorted { $0.consumedAt < $1.consumedAt }
    }

    private var dayCare: [CareOccurrenceRecord] {
        careOccurrences
            .filter { $0.dueDomainDay == dayKey && $0.statusRaw != "repairedDuplicate" }
            .sorted { $0.dueAt < $1.dueAt }
    }

    private var dayMeasurements: [BodyMeasurementRecord] {
        measurements
            .filter { $0.deletedAt == nil && $0.domainDay == dayKey }
            .sorted { $0.measuredAt < $1.measuredAt }
    }

    var body: some View {
        List {
            if category == .all || category == .workouts {
                workoutSection
            }
            if category == .all || category == .nutrition {
                nutritionSection
            }
            if category == .all || category == .care {
                careSection
            }
            if category == .all || category == .measurements {
                measurementSection
            }
        }
        .navigationTitle(day.historyDate?.formatted(date: .abbreviated, time: .omitted) ?? dayKey)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var workoutSection: some View {
        Section("Workout") {
            if daySessions.isEmpty && dayEvents.isEmpty {
                Text("No workout fact")
                    .foregroundStyle(.secondary)
            }
            ForEach(daySessions) { session in
                VStack(alignment: .leading, spacing: MomentumSpacing.xxs) {
                    Text(session.workoutNameSnapshot)
                        .font(.headline)
                    if let finishedAt = session.finishedAt {
                        Text("Finished \(finishedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("In progress")
                            .font(.caption)
                            .foregroundStyle(MomentumTheme.warning)
                    }
                    if !session.note.isEmpty {
                        Text(session.note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .swipeActions(edge: .leading) {
                    if session.finishedAt != nil {
                        Button("Edit time") {
                            editWorkoutCompletion(session)
                        }
                        .tint(MomentumTheme.pulse)
                    }
                }
                .swipeActions {
                    if session.finishedAt != nil {
                        Button("Delete", role: .destructive) {
                            requestWorkoutDeletion(session)
                        }
                    }
                }
                .contextMenu {
                    if session.finishedAt != nil {
                        Button("Edit completion time") {
                            editWorkoutCompletion(session)
                        }
                        Button("Delete workout", role: .destructive) {
                            requestWorkoutDeletion(session)
                        }
                    }
                }
            }
            ForEach(dayEvents) { event in
                Label(
                    "Workout \(event.kindRaw)",
                    systemImage: event.kindRaw == "missed" ? "xmark.circle" : "forward.circle"
                )
                .foregroundStyle(.secondary)
            }
        }
    }

    private var nutritionSection: some View {
        Section("Nutrition") {
            if let record = nutritionDays.first(where: { $0.domainDay == dayKey }) {
                Label(
                    record.finalizedAt == nil ? "Logging not finalized" : "Logging finalized",
                    systemImage: record.finalizedAt == nil ? "circle" : "checkmark.circle.fill"
                )
                .foregroundStyle(record.finalizedAt == nil ? .secondary : MomentumTheme.success)

                let calorieTotal = dayFoods.reduce(0) { $0 + $1.totalCalories }
                let proteinTotal = dayFoods.reduce(0) { $0 + $1.totalProteinGrams }
                LabeledContent(
                    "Day total",
                    value: "\(calorieTotal.formatted(.number.precision(.fractionLength(0)))) kcal · \(proteinTotal.formatted(.number.precision(.fractionLength(0...1)))) g"
                )
                LabeledContent(
                    "Target",
                    value: "\(record.calorieMinimumSnapshot)–\(record.calorieMaximumSnapshot) kcal · \(record.proteinMinimumSnapshot) g protein"
                )

                Button(record.finalizedAt == nil ? "Finalize logging" : "Reopen logging") {
                    toggleNutritionFinalization(day)
                }
            } else if dayFoods.isEmpty {
                Text("No nutrition facts")
                    .foregroundStyle(.secondary)
            } else {
                Button("Finalize logging") {
                    toggleNutritionFinalization(day)
                }
            }

            ForEach(dayFoods) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.nameSnapshot)
                        Text(entry.consumedAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(entry.totalCalories.formatted(.number.precision(.fractionLength(0)))) kcal")
                        Text("\(entry.totalProteinGrams.formatted(.number.precision(.fractionLength(0...1)))) g protein")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .swipeActions(edge: .leading) {
                    Button("Edit") { editFood(entry) }
                        .tint(MomentumTheme.pulse)
                    Button("Move") { backdateFood(entry) }
                        .tint(MomentumTheme.dataCyan)
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", role: .destructive) {
                        requestFoodDeletion(entry)
                    }
                }
                .contextMenu {
                    Button("Edit food") { editFood(entry) }
                    Button("Move to another day") { backdateFood(entry) }
                    Button("Delete food", role: .destructive) {
                        requestFoodDeletion(entry)
                    }
                }
            }
        }
    }

    private var careSection: some View {
        Section("Care") {
            if dayCare.isEmpty {
                Text("No care routines due")
                    .foregroundStyle(.secondary)
            }
            ForEach(dayCare) { occurrence in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(occurrence.routineNameSnapshot)
                        if occurrence.routineRoleRaw == "postWorkout" {
                            Text("Post-workout care")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(occurrence.statusRaw.capitalized)
                        .font(.subheadline)
                        .foregroundStyle(
                            occurrence.statusRaw == "completed" ? MomentumTheme.success : .secondary
                        )
                    if occurrence.statusRaw == "completed" {
                        Button("Undo") {
                            requestCareCompletionUndo(occurrence)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Undo \(occurrence.routineNameSnapshot) completion")
                    }
                }
                .contextMenu {
                    if occurrence.statusRaw == "completed" {
                        Button("Undo completion") {
                            requestCareCompletionUndo(occurrence)
                        }
                    }
                }
            }
        }
    }

    private var measurementSection: some View {
        Section("Measurements") {
            if dayMeasurements.isEmpty {
                Text("No measurements")
                    .foregroundStyle(.secondary)
            }
            ForEach(dayMeasurements) { measurement in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(measurement.kindRaw == "waistCm" ? "Waist" : "Weight")
                        Text(measurement.sourceRaw == "postWorkout" ? "Post-workout" : "Manual")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(measurementValue(measurement))
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .swipeActions(edge: .leading) {
                    Button("Move") { backdateMeasurement(measurement) }
                        .tint(MomentumTheme.dataCyan)
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", role: .destructive) {
                        requestMeasurementDeletion(measurement)
                    }
                }
                .contextMenu {
                    Button("Move to another day") { backdateMeasurement(measurement) }
                    Button("Delete measurement", role: .destructive) {
                        requestMeasurementDeletion(measurement)
                    }
                }
            }
        }
    }

    private func measurementValue(_ measurement: BodyMeasurementRecord) -> String {
        let kind = MeasurementKind(rawValue: measurement.kindRaw) ?? .weight
        return kind.formatted(metricValue: measurement.value, unitSystem: unitSystem)
    }
}
