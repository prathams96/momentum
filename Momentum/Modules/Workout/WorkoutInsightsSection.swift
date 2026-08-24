import Charts
import MomentumCore
import SwiftData
import SwiftUI

/// The workout module's contribution to the Progress surface: exercise
/// performance over finished sessions plus next-load suggestions.
struct WorkoutInsightsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [WorkoutSessionRecord]
    @Query private var exerciseLogs: [ExerciseLogRecord]
    @Query private var setLogs: [SetLogRecord]
    @Query private var prescriptions: [ExercisePrescriptionRecord]
    @Query private var suggestions: [LoadSuggestionRecord]
    @Query private var settingsRecords: [AppSettingsRecord]

    @State private var presentedSheet: SuggestionSheet?
    @State private var selectedPrescriptionID: UUID?
    @State private var actionError: String?

    private var settings: AppSettingsRecord? { AppSettingsRecord.canonical(in: settingsRecords) }
    private var unitSystem: UnitSystemOption {
        UnitSystemOption(rawValue: settings?.unitSystemRaw ?? "metric") ?? .metric
    }
    private var projection: WorkoutInsightsProjection {
        WorkoutInsightsProjection.make(
            sessions: sessions,
            exerciseLogs: exerciseLogs,
            setLogs: setLogs,
            prescriptions: prescriptions
        )
    }
    private var selectedExercise: ExerciseProgressSummary? {
        let id = selectedPrescriptionID ?? projection.exerciseSummaries.first?.prescriptionID
        return projection.exerciseSummaries.first { $0.prescriptionID == id }
    }

    var body: some View {
        Group {
            exerciseSection
            suggestionSection
        }
        .onAppear {
            if selectedPrescriptionID == nil {
                selectedPrescriptionID = projection.exerciseSummaries.first?.prescriptionID
            }
        }
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .suggestion(let id): LoadSuggestionEditor(suggestionID: id)
            }
        }
        .alert("Couldn’t update progress", isPresented: Binding(
            get: { actionError != nil }, set: { if !$0 { actionError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(actionError ?? "Try again.") }
    }

    private var exerciseSection: some View {
        Section {
            if projection.exerciseSummaries.isEmpty {
                Text("Complete working sets to see exercise performance.").foregroundStyle(.secondary)
            } else {
                Picker("Exercise", selection: Binding(
                    get: { selectedPrescriptionID ?? projection.exerciseSummaries[0].prescriptionID },
                    set: { selectedPrescriptionID = $0 }
                )) {
                    ForEach(projection.exerciseSummaries) { summary in
                        Text(summary.name).tag(summary.prescriptionID)
                    }
                }

                if let selectedExercise {
                    HStack {
                        InsightMetric(
                            title: "Highest weight",
                            value: MeasurementKind.weight.formatted(
                                metricValue: selectedExercise.highestWeight,
                                unitSystem: unitSystem
                            )
                        )
                        Spacer()
                        InsightMetric(title: "Best reps there", value: "\(selectedExercise.bestRepsAtHighestWeight)")
                    }
                    Chart(selectedExercise.volumePoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Volume", displayedVolume(point.volume))
                        )
                            .foregroundStyle(MomentumTheme.pulse)
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Volume", displayedVolume(point.volume))
                        )
                            .foregroundStyle(MomentumTheme.pulse)
                    }
                    .frame(height: 180)
                    .accessibilityLabel("\(selectedExercise.name) total volume over time")
                    .accessibilityValue(selectedExercise.summary(unitSystem: unitSystem))

                    if !selectedExercise.bestRepsByWeight.isEmpty {
                        DisclosureGroup("Best repetitions at each weight") {
                            ForEach(selectedExercise.bestRepsByWeight) { best in
                                LabeledContent(
                                    MeasurementKind.weight.formatted(
                                        metricValue: best.weight,
                                        unitSystem: unitSystem
                                    ),
                                    value: "\(best.repetitions) reps"
                                )
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Exercise performance")
        } footer: {
            Text("Volume is completed working-set \(unitSystem == .metric ? "kilograms" : "pounds") × repetitions. Estimated one-repetition maximums are not calculated.")
        }
    }

    private var suggestionSection: some View {
        Section("Next load suggestions") {
            let pending = suggestions.filter { $0.statusRaw == "pending" }.sorted {
                ($0.createdAt, $0.id.uuidString) > ($1.createdAt, $1.id.uuidString)
            }
            if pending.isEmpty {
                Text("Complete all prescribed sets at the top of the rep range to generate a suggestion.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(pending) { suggestion in
                    let prescription = prescriptions.first { $0.id == suggestion.prescriptionID }
                    VStack(alignment: .leading, spacing: MomentumSpacing.sm) {
                        Text(prescription?.displayName ?? "Exercise").font(.headline)
                        Text("Suggested working weight: \(MeasurementKind.weight.formatted(metricValue: suggestion.suggestedWeightKg, unitSystem: unitSystem))")
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Use") { accept(suggestion) }.buttonStyle(.borderedProminent)
                            Button("Edit") { presentedSheet = .suggestion(suggestion.id) }.buttonStyle(.bordered)
                            Button("Dismiss", role: .destructive) { dismissSuggestion(suggestion) }
                        }
                    }
                }
            }
        }
    }

    private func accept(_ suggestion: LoadSuggestionRecord) {
        do {
            try LoadSuggestionService.accept(
                suggestion,
                weightKg: suggestion.suggestedWeightKg,
                prescriptions: prescriptions,
                in: modelContext
            )
        } catch { actionError = "The suggested load was not applied." }
    }

    private func dismissSuggestion(_ suggestion: LoadSuggestionRecord) {
        do { try LoadSuggestionService.dismiss(suggestion, in: modelContext) }
        catch { actionError = "The suggestion was not dismissed." }
    }

    private func displayedVolume(_ metricVolume: Double) -> Double {
        MeasurementKind.weight.displayValue(metricValue: metricVolume, unitSystem: unitSystem)
    }
}

private enum SuggestionSheet: Identifiable {
    case suggestion(UUID)
    var id: String {
        switch self {
        case .suggestion(let id): "suggestion-\(id)"
        }
    }
}

private struct InsightMetric: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LoadSuggestionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var suggestions: [LoadSuggestionRecord]
    @Query private var prescriptions: [ExercisePrescriptionRecord]
    @Query private var settingsRecords: [AppSettingsRecord]
    @State private var weight = ""
    @State private var didLoad = false
    @State private var errorMessage: String?
    let suggestionID: UUID
    private var suggestion: LoadSuggestionRecord? { suggestions.first { $0.id == suggestionID } }
    private var units: UnitSystemOption {
        UnitSystemOption(rawValue: AppSettingsRecord.canonical(in: settingsRecords)?.unitSystemRaw ?? "metric") ?? .metric
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Working weight (\(MeasurementKind.weight.unit(unitSystem: units)))", text: $weight)
                    .keyboardType(.decimalPad)
                Button("Dismiss suggestion", role: .destructive) { dismissSuggestion() }
            }
            .navigationTitle("Edit suggestion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") { accept() }.disabled(Double(weight).map { $0 <= 0 } ?? true)
                }
            }
            .onAppear {
                guard !didLoad, let suggestion else { return }
                weight = DecimalFormatter.onePlace(
                    MeasurementKind.weight.displayValue(
                        metricValue: suggestion.suggestedWeightKg,
                        unitSystem: units
                    )
                )
                didLoad = true
            }
            .alert("Couldn’t update suggestion", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "Try again.") }
        }
    }

    private func accept() {
        guard let suggestion, let value = Double(weight), value > 0 else { return }
        let metricValue = MeasurementKind.weight.metricValue(displayValue: value, unitSystem: units)
        do { try LoadSuggestionService.accept(suggestion, weightKg: metricValue, prescriptions: prescriptions, in: modelContext); dismiss() }
        catch { errorMessage = "The working weight was not applied." }
    }

    private func dismissSuggestion() {
        guard let suggestion else { return }
        do { try LoadSuggestionService.dismiss(suggestion, in: modelContext); dismiss() }
        catch { errorMessage = "The suggestion was not dismissed." }
    }
}

@MainActor
enum LoadSuggestionService {
    enum ActionError: LocalizedError { case missingPrescription }

    static func accept(
        _ suggestion: LoadSuggestionRecord,
        weightKg: Double,
        prescriptions: [ExercisePrescriptionRecord],
        now: Date = .now,
        in context: ModelContext
    ) throws {
        guard let prescription = prescriptions.first(where: { $0.id == suggestion.prescriptionID }) else {
            throw ActionError.missingPrescription
        }
        suggestion.suggestedWeightKg = weightKg
        suggestion.statusRaw = "accepted"
        suggestion.resolvedAt = now
        suggestion.updatedAt = now
        prescription.workingWeightKg = weightKg
        prescription.updatedAt = now
        try PlanEditingService.save(context)
    }

    static func dismiss(_ suggestion: LoadSuggestionRecord, now: Date = .now, in context: ModelContext) throws {
        suggestion.statusRaw = "dismissed"
        suggestion.resolvedAt = now
        suggestion.updatedAt = now
        try PlanEditingService.save(context)
    }
}

private struct VolumePoint: Identifiable {
    let id: UUID
    let date: Date
    let volume: Double
}

private struct WeightRepetitionBest: Identifiable {
    var id: Double { weight }
    let weight: Double
    let repetitions: Int
}

private struct ExerciseProgressSummary: Identifiable {
    var id: UUID { prescriptionID }
    let prescriptionID: UUID
    let name: String
    let volumePoints: [VolumePoint]
    let highestWeight: Double
    let bestRepsAtHighestWeight: Int
    let bestRepsByWeight: [WeightRepetitionBest]
    func summary(unitSystem: UnitSystemOption) -> String {
        "\(volumePoints.count) completed sessions. Highest weight \(MeasurementKind.weight.formatted(metricValue: highestWeight, unitSystem: unitSystem)) for \(bestRepsAtHighestWeight) repetitions."
    }
}

@MainActor
private struct WorkoutInsightsProjection {
    let exerciseSummaries: [ExerciseProgressSummary]

    static func make(
        sessions: [WorkoutSessionRecord],
        exerciseLogs: [ExerciseLogRecord],
        setLogs: [SetLogRecord],
        prescriptions: [ExercisePrescriptionRecord]
    ) -> WorkoutInsightsProjection {
        WorkoutInsightsProjection(exerciseSummaries: exerciseProjection(
            sessions: sessions,
            logs: exerciseLogs,
            sets: setLogs,
            prescriptions: prescriptions
        ))
    }

    private static func exerciseProjection(
        sessions: [WorkoutSessionRecord],
        logs: [ExerciseLogRecord],
        sets: [SetLogRecord],
        prescriptions: [ExercisePrescriptionRecord]
    ) -> [ExerciseProgressSummary] {
        let sessionsByID = Dictionary(uniqueKeysWithValues: sessions.filter {
            $0.finishedAt != nil && $0.deletedAt == nil
        }.map { ($0.id, $0) })
        let setsByLog = Dictionary(grouping: sets.filter { $0.statusRaw == "completed" }, by: \.exerciseLogID)

        return prescriptions.filter { !$0.isArchived }.compactMap { prescription in
            let matchingLogs = logs.filter { $0.prescriptionID == prescription.id && $0.statusRaw == "completed" }
            var performances: [(WorkoutSessionRecord, [SetLogRecord])] = []
            for log in matchingLogs {
                guard let session = sessionsByID[log.workoutSessionID] else { continue }
                performances.append((session, setsByLog[log.id] ?? []))
            }
            guard !performances.isEmpty else { return nil }
            let volume = performances.map { session, sessionSets in
                VolumePoint(
                    id: session.id,
                    date: session.finishedAt ?? session.startedAt,
                    volume: sessionSets.reduce(0) { $0 + $1.weightKg * Double($1.repetitions) }
                )
            }.sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }
            let allSets = performances.flatMap(\.1)
            let highest = allSets.map(\.weightKg).max() ?? 0
            let byWeight = Dictionary(grouping: allSets, by: \.weightKg).map { weight, values in
                WeightRepetitionBest(weight: weight, repetitions: values.map(\.repetitions).max() ?? 0)
            }.sorted { $0.weight > $1.weight }
            return ExerciseProgressSummary(
                prescriptionID: prescription.id,
                name: prescription.displayName,
                volumePoints: volume,
                highestWeight: highest,
                bestRepsAtHighestWeight: byWeight.first { $0.weight == highest }?.repetitions ?? 0,
                bestRepsByWeight: byWeight
            )
        }.sorted { ($0.name, $0.prescriptionID.uuidString) < ($1.name, $1.prescriptionID.uuidString) }
    }
}

// MARK: - Module conformance

extension WorkoutModuleAdapter: InsightsContributing {
    func insightsSection(in context: ModuleContext) -> AnyView? {
        AnyView(WorkoutInsightsSection())
    }
}
