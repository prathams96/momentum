import Charts
import MomentumCore
import SwiftData
import SwiftUI

struct ProgressTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var measurements: [BodyMeasurementRecord]
    @Query private var sessions: [WorkoutSessionRecord]
    @Query private var exerciseLogs: [ExerciseLogRecord]
    @Query private var setLogs: [SetLogRecord]
    @Query private var prescriptions: [ExercisePrescriptionRecord]
    @Query private var suggestions: [LoadSuggestionRecord]
    @Query private var foodEntries: [FoodEntryRecord]
    @Query private var nutritionDays: [NutritionDayRecord]
    @Query private var nutritionTargets: [NutritionTargetRecord]
    @Query private var workoutEvents: [WorkoutDayEventRecord]
    @Query private var careOccurrences: [CareOccurrenceRecord]
    @Query private var settingsRecords: [AppSettingsRecord]
    @Query private var milestones: [MilestoneRecord]

    @State private var presentedSheet: ProgressSheet?
    @State private var selectedPrescriptionID: UUID?
    @State private var actionError: String?

    private var settings: AppSettingsRecord? { AppSettingsRecord.canonical(in: settingsRecords) }
    private var unitSystem: UnitSystemOption {
        UnitSystemOption(rawValue: settings?.unitSystemRaw ?? "metric") ?? .metric
    }
    private var projection: ProgressProjection {
        ProgressProjection.make(
            measurements: measurements,
            sessions: sessions,
            exerciseLogs: exerciseLogs,
            setLogs: setLogs,
            prescriptions: prescriptions,
            foodEntries: foodEntries,
            nutritionDays: nutritionDays,
            nutritionTargets: nutritionTargets,
            workoutEvents: workoutEvents,
            careOccurrences: careOccurrences,
            calendar: .autoupdatingCurrent
        )
    }
    private var selectedExercise: ExerciseProgressSummary? {
        let id = selectedPrescriptionID ?? projection.exerciseSummaries.first?.prescriptionID
        return projection.exerciseSummaries.first { $0.prescriptionID == id }
    }
    private var pendingMilestone: MilestoneRecord? {
        MilestoneService.nextUnacknowledged(in: milestones)
    }
    private var milestoneSourceVersion: String {
        [
            "sessions:\(sessions.count):\(sessions.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0)",
            "logs:\(exerciseLogs.count):\(exerciseLogs.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0)",
            "sets:\(setLogs.count):\(setLogs.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0)",
            "events:\(workoutEvents.count):\(workoutEvents.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0)",
            "nutrition:\(nutritionDays.count):\(nutritionDays.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0)",
            "food:\(foodEntries.count):\(foodEntries.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0)",
            "care:\(careOccurrences.count):\(careOccurrences.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0)"
        ].joined(separator: "|")
    }

    var body: some View {
        List {
            milestoneSection
            measurementSection
            nutritionSection
            exerciseSection
            adherenceSection
            suggestionSection
        }
        .navigationTitle("Progress")
        .task(id: milestoneSourceVersion) {
            do { try MilestoneService.reconcile(in: modelContext) }
            catch { actionError = "Milestones could not be refreshed. Your activity is still safe." }
        }
        .onAppear {
            if selectedPrescriptionID == nil {
                selectedPrescriptionID = projection.exerciseSummaries.first?.prescriptionID
            }
        }
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .newMeasurement(let kind): MeasurementEditor(destination: .new(kind))
            case .editMeasurement(let id): MeasurementEditor(destination: .edit(id))
            case .suggestion(let id): LoadSuggestionEditor(suggestionID: id)
            }
        }
        .alert("Couldn’t update progress", isPresented: Binding(
            get: { actionError != nil }, set: { if !$0 { actionError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(actionError ?? "Try again.") }
    }

    @ViewBuilder
    private var milestoneSection: some View {
        if let pendingMilestone {
            let presentation = MilestoneService.presentation(
                for: pendingMilestone,
                prescriptions: prescriptions
            )
            Section("Milestone") {
                VStack(alignment: .leading, spacing: MomentumSpacing.sm) {
                    Label(presentation.title, systemImage: presentation.symbol)
                        .font(.headline)
                        .foregroundStyle(MomentumTheme.pulseDeep)
                    Text(presentation.message)
                        .foregroundStyle(.secondary)
                    Button("Noted") { acknowledge(pendingMilestone) }
                        .buttonStyle(.bordered)
                }
                .accessibilityElement(children: .contain)
            }
        }
    }

    private var measurementSection: some View {
        Section {
            HStack {
                ProgressMetric(
                    title: "Latest weight",
                    value: projection.latestWeight.map { MeasurementKind.weight.formatted(metricValue: $0.value, unitSystem: unitSystem) } ?? "—"
                )
                Spacer()
                ProgressMetric(
                    title: "7-day average",
                    value: projection.latestWeightAverage.map { MeasurementKind.weight.formatted(metricValue: $0, unitSystem: unitSystem) } ?? "—"
                )
            }

            if projection.weightPoints.isEmpty {
                Text("Log weight observations to see the seven-day trend.").foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(projection.weightPoints) { point in
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Weight", MeasurementKind.weight.displayValue(metricValue: point.value, unitSystem: unitSystem))
                        )
                        .foregroundStyle(.secondary)
                    }
                    ForEach(projection.weightAveragePoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("7-day average", MeasurementKind.weight.displayValue(metricValue: point.value, unitSystem: unitSystem))
                        )
                        .foregroundStyle(MomentumTheme.pulse)
                        .interpolationMethod(.catmullRom)
                    }
                }
                .frame(height: 190)
                .accessibilityLabel("Weight observations and seven-day average")
                .accessibilityValue(projection.weightSummary(unitSystem: unitSystem))
            }

            HStack {
                ProgressMetric(
                    title: "Latest waist",
                    value: projection.latestWaist.map { MeasurementKind.waist.formatted(metricValue: $0.value, unitSystem: unitSystem) } ?? "—"
                )
                Spacer()
                Button("Log weight") { presentedSheet = .newMeasurement(.weight) }
                Button("Log waist") { presentedSheet = .newMeasurement(.waist) }
            }

            if projection.waistIsDue {
                Label("Waist measurement is due", systemImage: "calendar.badge.exclamationmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MomentumTheme.warning)
                    .accessibilityHint("Waist measurements are optional and do not create notifications")
            }

            if !projection.waistPoints.isEmpty {
                Chart(projection.waistPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Waist", MeasurementKind.waist.displayValue(metricValue: point.value, unitSystem: unitSystem))
                    )
                    .foregroundStyle(MomentumTheme.pulseDeep)
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Waist", MeasurementKind.waist.displayValue(metricValue: point.value, unitSystem: unitSystem))
                    )
                    .foregroundStyle(MomentumTheme.pulseDeep)
                }
                .frame(height: 150)
                .accessibilityLabel("Waist measurements")
                .accessibilityValue(projection.waistSummary(unitSystem: unitSystem))
            }

            ForEach(projection.recentMeasurements.prefix(8)) { item in
                Button { presentedSheet = .editMeasurement(item.id) } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.kind.title).foregroundStyle(.primary)
                            Text(item.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.kind.formatted(metricValue: item.value, unitSystem: unitSystem))
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
            }
        } header: {
            Text("Measurements")
        } footer: {
            Text("Observations stay visible as entered; the weight line averages the preceding seven calendar days.")
        }
    }

    private var nutritionSection: some View {
        Section {
            if projection.nutritionPoints.isEmpty {
                Text("Log food to see calorie and protein trends.").foregroundStyle(.secondary)
            } else {
                Chart(projection.nutritionPoints) { point in
                    BarMark(x: .value("Date", point.date), y: .value("Calories", point.calories))
                        .foregroundStyle(MomentumTheme.pulse.opacity(0.55))
                    LineMark(x: .value("Date", point.date), y: .value("Minimum", point.calorieMinimum))
                        .foregroundStyle(.secondary)
                    LineMark(x: .value("Date", point.date), y: .value("Maximum", point.calorieMaximum))
                        .foregroundStyle(.secondary)
                }
                .frame(height: 190)
                .accessibilityLabel("Daily calories and target range")
                .accessibilityValue(projection.nutritionSummary)

                Chart(projection.nutritionPoints) { point in
                    BarMark(x: .value("Date", point.date), y: .value("Protein", point.protein))
                        .foregroundStyle(MomentumTheme.pulseDeep.opacity(0.7))
                    LineMark(x: .value("Date", point.date), y: .value("Minimum", point.proteinMinimum))
                        .foregroundStyle(.secondary)
                }
                .frame(height: 150)
                .accessibilityLabel("Daily protein and minimum target")
                .accessibilityValue(projection.proteinSummary)
            }
        } header: {
            Text("Nutrition")
        } footer: {
            Text("Bars are daily totals. Lines show the effective target for each Domain Day.")
        }
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
                        ProgressMetric(
                            title: "Highest weight",
                            value: MeasurementKind.weight.formatted(
                                metricValue: selectedExercise.highestWeight,
                                unitSystem: unitSystem
                            )
                        )
                        Spacer()
                        ProgressMetric(title: "Best reps there", value: "\(selectedExercise.bestRepsAtHighestWeight)")
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

    private var adherenceSection: some View {
        Section {
            HStack {
                ProgressMetric(title: "Workout streak", value: "\(projection.workoutStreak)")
                Spacer()
                ProgressMetric(title: "Nutrition streak", value: "\(projection.nutritionStreak)")
                Spacer()
                ProgressMetric(title: "Care streak", value: "\(projection.careStreak)")
            }
            if projection.adherencePoints.isEmpty {
                Text("Complete due activities to build adherence history.").foregroundStyle(.secondary)
            } else {
                Chart(projection.adherencePoints) { point in
                    BarMark(x: .value("Date", point.date), y: .value("Adherence", point.percentage))
                        .foregroundStyle(point.percentage >= 100 ? MomentumTheme.success : MomentumTheme.pulse.opacity(0.65))
                }
                .chartYScale(domain: 0...100)
                .frame(height: 180)
                .accessibilityLabel("Daily adherence percentage")
                .accessibilityValue(projection.adherenceSummary)
            }
        } header: {
            Text("Adherence")
        } footer: {
            Text("Recovery days are neutral. Streaks reset only when a due category is incomplete.")
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

    private func acknowledge(_ milestone: MilestoneRecord) {
        do { try MilestoneService.acknowledge(milestone, in: modelContext) }
        catch { actionError = "The milestone acknowledgement was not saved." }
    }

    private func displayedVolume(_ metricVolume: Double) -> Double {
        MeasurementKind.weight.displayValue(metricValue: metricVolume, unitSystem: unitSystem)
    }
}

private struct ProgressMetric: View {
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

private enum ProgressSheet: Identifiable {
    case newMeasurement(MeasurementKind)
    case editMeasurement(UUID)
    case suggestion(UUID)
    var id: String {
        switch self {
        case let .newMeasurement(kind): "new-\(kind.rawValue)"
        case let .editMeasurement(id): "measurement-\(id)"
        case let .suggestion(id): "suggestion-\(id)"
        }
    }
}

enum MeasurementKind: String, CaseIterable, Identifiable {
    case weight = "weightKg"
    case waist = "waistCm"
    var id: String { rawValue }
    var title: String { self == .weight ? "Weight" : "Waist" }

    func displayValue(metricValue: Double, unitSystem: UnitSystemOption) -> Double {
        guard unitSystem == .imperial else { return metricValue }
        return self == .weight ? metricValue * 2.204_622_621_8 : metricValue * 0.393_700_787_4
    }

    func metricValue(displayValue: Double, unitSystem: UnitSystemOption) -> Double {
        guard unitSystem == .imperial else { return displayValue }
        return self == .weight ? displayValue / 2.204_622_621_8 : displayValue / 0.393_700_787_4
    }

    func unit(unitSystem: UnitSystemOption) -> String {
        if unitSystem == .metric { return self == .weight ? "kg" : "cm" }
        return self == .weight ? "lb" : "in"
    }

    func formatted(metricValue: Double, unitSystem: UnitSystemOption) -> String {
        "\(DecimalFormatter.onePlace(displayValue(metricValue: metricValue, unitSystem: unitSystem))) \(unit(unitSystem: unitSystem))"
    }
}

private enum MeasurementEditorDestination {
    case new(MeasurementKind)
    case edit(UUID)
}

private struct MeasurementEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var measurements: [BodyMeasurementRecord]
    @Query private var settingsRecords: [AppSettingsRecord]
    @State private var kind = MeasurementKind.weight
    @State private var value = ""
    @State private var measuredAt = Date.now
    @State private var didLoad = false
    @State private var showDelete = false
    @State private var errorMessage: String?

    let destination: MeasurementEditorDestination
    private var measurementID: UUID? { if case let .edit(id) = destination { id } else { nil } }
    private var measurement: BodyMeasurementRecord? { measurementID.flatMap { id in measurements.first { $0.id == id } } }
    private var settings: AppSettingsRecord? { AppSettingsRecord.canonical(in: settingsRecords) }
    private var units: UnitSystemOption { UnitSystemOption(rawValue: settings?.unitSystemRaw ?? "metric") ?? .metric }
    private var parsedValue: Double? { Double(value.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Measurement", selection: $kind) {
                    ForEach(MeasurementKind.allCases) { item in Text(item.title).tag(item) }
                }
                TextField("Value (\(kind.unit(unitSystem: units)))", text: $value)
                    .keyboardType(.decimalPad)
                DatePicker("Measured", selection: $measuredAt, in: ...Date.now)
                if measurement != nil {
                    Button("Delete measurement", role: .destructive) { showDelete = true }
                }
            }
            .navigationTitle(measurement == nil ? "Log measurement" : "Edit measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(parsedValue.map { $0 <= 0 } ?? true)
                }
            }
            .onAppear(perform: load)
            .confirmationDialog("Delete this measurement?", isPresented: $showDelete, titleVisibility: .visible) {
                Button("Delete measurement", role: .destructive) { delete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It will be removed from Progress and CSV export without changing other history.")
            }
            .alert("Couldn’t save measurement", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "Try again.") }
        }
    }

    private func load() {
        guard !didLoad else { return }
        switch destination {
        case let .new(initialKind): kind = initialKind
        case .edit:
            if let measurement {
                kind = MeasurementKind(rawValue: measurement.kindRaw) ?? .weight
                value = DecimalFormatter.onePlace(kind.displayValue(metricValue: measurement.value, unitSystem: units))
                measuredAt = measurement.measuredAt
            }
        }
        didLoad = true
    }

    private func save() {
        guard let parsedValue, parsedValue > 0 else { return }
        do {
            try MeasurementService.save(
                existing: measurement,
                kind: kind,
                metricValue: kind.metricValue(displayValue: parsedValue, unitSystem: units),
                measuredAt: measuredAt,
                cutoffMinutes: settings?.domainDayCutoffMinutes ?? 180,
                in: modelContext
            )
            dismiss()
        } catch { errorMessage = "The measurement was not saved. Your entry is still here." }
    }

    private func delete() {
        guard let measurement else { return }
        do { try MeasurementService.delete(measurement, in: modelContext); dismiss() }
        catch { errorMessage = "The measurement was not deleted." }
    }
}

@MainActor
enum MeasurementService {
    static func save(
        existing: BodyMeasurementRecord?,
        kind: MeasurementKind,
        metricValue: Double,
        measuredAt: Date,
        cutoffMinutes: Int,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        in context: ModelContext
    ) throws {
        let day = DomainDay.containing(measuredAt, calendar: calendar, cutoffMinutes: cutoffMinutes)
        let record = existing ?? BodyMeasurementRecord(
            kindRaw: kind.rawValue,
            value: metricValue,
            measuredAt: measuredAt,
            domainDay: PersistedDomainDay.encode(day)
        )
        if existing == nil { context.insert(record) }
        record.kindRaw = kind.rawValue
        record.value = metricValue
        record.measuredAt = measuredAt
        record.domainDay = PersistedDomainDay.encode(day)
        record.updatedAt = now
        record.deletedAt = nil
        try PlanEditingService.save(context)
    }

    static func delete(_ record: BodyMeasurementRecord, now: Date = .now, in context: ModelContext) throws {
        record.deletedAt = now
        record.updatedAt = now
        try PlanEditingService.save(context)
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

struct MeasurementPoint: Identifiable {
    let id: UUID
    let date: Date
    let value: Double
}

enum WeightTrendProjection {
    static func sevenDayAverages(
        observations: [MeasurementPoint],
        calendar: Calendar,
        minimumDistinctDays: Int = 2
    ) -> [MeasurementPoint] {
        let dailyPoints = Dictionary(grouping: observations) {
            calendar.startOfDay(for: $0.date)
        }.map { date, values in
            let value = values.map(\.value).reduce(0, +) / Double(values.count)
            let id = values.map(\.id).min { $0.uuidString < $1.uuidString } ?? UUID()
            return MeasurementPoint(id: id, date: date, value: value)
        }.sorted { $0.date < $1.date }

        return dailyPoints.compactMap { point in
            let start = calendar.date(byAdding: .day, value: -6, to: point.date) ?? point.date
            let window = dailyPoints.filter { $0.date >= start && $0.date <= point.date }
            guard window.count >= minimumDistinctDays else { return nil }
            let average = window.map(\.value).reduce(0, +) / Double(window.count)
            return MeasurementPoint(id: point.id, date: point.date, value: average)
        }
    }
}

private struct RecentMeasurement: Identifiable {
    let id: UUID
    let kind: MeasurementKind
    let date: Date
    let value: Double
}

private struct NutritionProgressPoint: Identifiable {
    var id: String { domainDay }
    let domainDay: String
    let date: Date
    let calories: Double
    let protein: Double
    let calorieMinimum: Double
    let calorieMaximum: Double
    let proteinMinimum: Double
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

private struct AdherencePoint: Identifiable {
    var id: String { domainDay }
    let domainDay: String
    let date: Date
    let percentage: Double
}

@MainActor
private struct ProgressProjection {
    let weightPoints: [MeasurementPoint]
    let weightAveragePoints: [MeasurementPoint]
    let waistPoints: [MeasurementPoint]
    let recentMeasurements: [RecentMeasurement]
    let nutritionPoints: [NutritionProgressPoint]
    let exerciseSummaries: [ExerciseProgressSummary]
    let adherencePoints: [AdherencePoint]
    let workoutStreak: Int
    let nutritionStreak: Int
    let careStreak: Int
    let waistIsDue: Bool

    var latestWeight: MeasurementPoint? { weightPoints.last }
    var latestWeightAverage: Double? { weightAveragePoints.last?.value }
    var latestWaist: MeasurementPoint? { waistPoints.last }
    var nutritionSummary: String {
        guard let point = nutritionPoints.last else { return "No nutrition data." }
        return "Latest day: \(DecimalFormatter.whole(point.calories)) calories; target range \(DecimalFormatter.whole(point.calorieMinimum)) to \(DecimalFormatter.whole(point.calorieMaximum))."
    }
    var proteinSummary: String {
        guard let point = nutritionPoints.last else { return "No protein data." }
        return "Latest day: \(DecimalFormatter.onePlace(point.protein)) grams; minimum \(DecimalFormatter.onePlace(point.proteinMinimum)) grams."
    }
    var adherenceSummary: String {
        guard let point = adherencePoints.last else { return "No adherence data." }
        return "Latest scored day: \(DecimalFormatter.whole(point.percentage)) percent."
    }

    func weightSummary(unitSystem: UnitSystemOption) -> String {
        guard let latestWeight else { return "No weight observations." }
        let average = latestWeightAverage.map { MeasurementKind.weight.formatted(metricValue: $0, unitSystem: unitSystem) } ?? "unavailable"
        return "Latest \(MeasurementKind.weight.formatted(metricValue: latestWeight.value, unitSystem: unitSystem)); seven-day average \(average)."
    }

    func waistSummary(unitSystem: UnitSystemOption) -> String {
        guard let latestWaist else { return "No waist measurements." }
        return "Latest \(MeasurementKind.waist.formatted(metricValue: latestWaist.value, unitSystem: unitSystem))."
    }

    static func make(
        measurements: [BodyMeasurementRecord],
        sessions: [WorkoutSessionRecord],
        exerciseLogs: [ExerciseLogRecord],
        setLogs: [SetLogRecord],
        prescriptions: [ExercisePrescriptionRecord],
        foodEntries: [FoodEntryRecord],
        nutritionDays: [NutritionDayRecord],
        nutritionTargets: [NutritionTargetRecord],
        workoutEvents: [WorkoutDayEventRecord],
        careOccurrences: [CareOccurrenceRecord],
        calendar: Calendar
    ) -> ProgressProjection {
        let activeMeasurements = measurements.filter { $0.deletedAt == nil }
        let weight = points(kind: .weight, measurements: activeMeasurements)
        let waist = points(kind: .waist, measurements: activeMeasurements)
        let waistIsDue = waist.last.map {
            calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: $0.date),
                to: calendar.startOfDay(for: .now)
            ).day.map { $0 >= 7 } ?? false
        } ?? true
        let averages = WeightTrendProjection.sevenDayAverages(
            observations: weight,
            calendar: calendar
        )
        let recent = activeMeasurements.compactMap { record -> RecentMeasurement? in
            guard let kind = MeasurementKind(rawValue: record.kindRaw) else { return nil }
            return RecentMeasurement(id: record.id, kind: kind, date: record.measuredAt, value: record.value)
        }.sorted { ($0.date, $0.id.uuidString) > ($1.date, $1.id.uuidString) }

        let nutrition = nutritionProjection(entries: foodEntries, days: nutritionDays, targets: nutritionTargets, calendar: calendar)
        let exercises = exerciseProjection(
            sessions: sessions,
            logs: exerciseLogs,
            sets: setLogs,
            prescriptions: prescriptions
        )
        let adherence = adherenceProjection(
            sessions: sessions,
            events: workoutEvents,
            nutritionDays: nutritionDays,
            care: careOccurrences,
            calendar: calendar
        )
        return ProgressProjection(
            weightPoints: weight,
            weightAveragePoints: averages,
            waistPoints: waist,
            recentMeasurements: recent,
            nutritionPoints: nutrition,
            exerciseSummaries: exercises,
            adherencePoints: adherence.points,
            workoutStreak: adherence.workoutStreak,
            nutritionStreak: adherence.nutritionStreak,
            careStreak: adherence.careStreak,
            waistIsDue: waistIsDue
        )
    }

    private static func points(kind: MeasurementKind, measurements: [BodyMeasurementRecord]) -> [MeasurementPoint] {
        measurements.filter { $0.kindRaw == kind.rawValue }
            .map { MeasurementPoint(id: $0.id, date: $0.measuredAt, value: $0.value) }
            .sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }
    }

    private static func nutritionProjection(
        entries: [FoodEntryRecord],
        days: [NutritionDayRecord],
        targets: [NutritionTargetRecord],
        calendar: Calendar
    ) -> [NutritionProgressPoint] {
        let grouped = Dictionary(grouping: entries.filter { $0.deletedAt == nil }, by: \.domainDay)
        return grouped.compactMap { dayValue, values in
            guard let day = PersistedDomainDay.decode(dayValue),
                  let date = PersistedDomainDay.date(for: day, calendar: calendar) else { return nil }
            let calories = values.reduce(0) { $0 + $1.totalCalories }
            let protein = values.reduce(0) { $0 + $1.totalProteinGrams }
            let finalized = days.filter { $0.domainDay == dayValue }.max {
                ($0.updatedAt, $0.id.uuidString) < ($1.updatedAt, $1.id.uuidString)
            }
            let target = NutritionPlanService.target(for: day, in: targets)
            return NutritionProgressPoint(
                domainDay: dayValue,
                date: date,
                calories: calories,
                protein: protein,
                calorieMinimum: Double(finalized?.calorieMinimumSnapshot ?? target?.calorieMinimum ?? 0),
                calorieMaximum: Double(finalized?.calorieMaximumSnapshot ?? target?.calorieMaximum ?? 0),
                proteinMinimum: Double(finalized?.proteinMinimumSnapshot ?? target?.proteinMinimumGrams ?? 0)
            )
        }.sorted { $0.domainDay < $1.domainDay }
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

    private static func adherenceProjection(
        sessions: [WorkoutSessionRecord],
        events: [WorkoutDayEventRecord],
        nutritionDays: [NutritionDayRecord],
        care: [CareOccurrenceRecord],
        calendar: Calendar
    ) -> (points: [AdherencePoint], workoutStreak: Int, nutritionStreak: Int, careStreak: Int) {
        var counts: [String: (completed: Int, due: Int)] = [:]
        for session in sessions where session.finishedAt != nil && session.deletedAt == nil {
            let day = session.completionDomainDay ?? session.scheduledDomainDay
            counts[day, default: (0, 0)].completed += 1
            counts[day, default: (0, 0)].due += 1
        }
        for event in events where event.deletedAt == nil { counts[event.domainDay, default: (0, 0)].due += 1 }
        for day in nutritionDays {
            counts[day.domainDay, default: (0, 0)].due += 1
            if day.finalizedAt != nil { counts[day.domainDay, default: (0, 0)].completed += 1 }
        }
        for occurrence in care where occurrence.statusRaw != "repairedDuplicate" {
            counts[occurrence.dueDomainDay, default: (0, 0)].due += 1
            if occurrence.statusRaw == "completed" { counts[occurrence.dueDomainDay, default: (0, 0)].completed += 1 }
        }
        let points = counts.compactMap { dayValue, value -> AdherencePoint? in
            guard value.due > 0, let day = PersistedDomainDay.decode(dayValue),
                  let date = PersistedDomainDay.date(for: day, calendar: calendar) else { return nil }
            return AdherencePoint(domainDay: dayValue, date: date, percentage: Double(value.completed) / Double(value.due) * 100)
        }.sorted { $0.domainDay < $1.domainDay }

        let workoutOutcomes: [(String, WorkoutAdherenceOutcome)] =
            sessions.filter { $0.finishedAt != nil && $0.deletedAt == nil }.map {
                ($0.completionDomainDay ?? $0.scheduledDomainDay, .finished)
            } + events.filter { $0.deletedAt == nil }.map {
                ($0.domainDay, $0.kindRaw == "skipped" ? .skipped : .missed)
            }
        let workoutStreak = AdherenceEngine().workoutStreak(
            opportunities: workoutOutcomes.sorted { $0.0 < $1.0 }.map(\.1)
        )
        let nutritionStreak = AdherenceEngine().nutritionStreak(
            days: nutritionDays.compactMap { record in
                PersistedDomainDay.decode(record.domainDay).map { day in
                    NutritionAdherenceDay(day: day, isFinalized: record.finalizedAt != nil)
                }
            },
            calendar: calendar
        )
        let careDays = Dictionary(grouping: care.filter { $0.statusRaw != "repairedDuplicate" }, by: \.dueDomainDay)
            .compactMap { dayValue, occurrences -> CareAdherenceDay? in
                guard let day = PersistedDomainDay.decode(dayValue) else { return nil }
                return CareAdherenceDay(
                    day: day,
                    dueCount: occurrences.count,
                    completedCount: occurrences.filter { $0.statusRaw == "completed" }.count
                )
            }
        let careStreak = AdherenceEngine().careStreak(days: careDays, calendar: calendar)
        return (points, workoutStreak, nutritionStreak, careStreak)
    }
}
