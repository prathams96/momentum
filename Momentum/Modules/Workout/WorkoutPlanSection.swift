import MomentumCore
import SwiftData
import SwiftUI

/// The workout module's contribution to the Plans surface: the cycle order,
/// recovery requirements, and per-workout exercise editing.
struct WorkoutPlanSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var workouts: [WorkoutTemplateRecord]
    @Query private var exercises: [ExercisePrescriptionRecord]
    @Query private var anchors: [CycleAnchorRecord]
    @Query private var settingsRecords: [AppSettingsRecord]
    @State private var saveError: String?

    private var orderedWorkouts: [WorkoutTemplateRecord] {
        workouts.filter { !$0.isArchived }.sorted {
            ($0.sequenceIndex, $0.id.uuidString) < ($1.sequenceIndex, $1.id.uuidString)
        }
    }

    private var anchor: CycleAnchorRecord? {
        anchors.max { ($0.updatedAt, $0.id.uuidString) < ($1.updatedAt, $1.id.uuidString) }
    }

    var body: some View {
        Section {
            ForEach(orderedWorkouts) { workout in
                NavigationLink {
                    WorkoutPlanEditor(workoutID: workout.id)
                } label: {
                    VStack(alignment: .leading, spacing: MomentumSpacing.xs) {
                        HStack {
                            Text(workout.name).font(.headline)
                            Spacer()
                            if anchor?.nextWorkoutTemplateID == workout.id {
                                Text("Next")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(MomentumTheme.pulse)
                            }
                        }
                        Text(workout.focus).foregroundStyle(.secondary)
                        Text("\(exercises.count { $0.workoutTemplateID == workout.id && !$0.isArchived }) exercises · \(workout.recoveryDaysAfter) recovery day\(workout.recoveryDaysAfter == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if anchor?.nextWorkoutTemplateID != workout.id {
                        Button("Make next") { chooseNext(workout) }
                            .tint(MomentumTheme.pulse)
                    }
                }
            }
            .onMove(perform: moveWorkouts)
        } header: {
            Text("Workout cycle")
        } footer: {
            Text("Drag to reorder the continuous cycle. Open a workout to edit recovery and its exercises.")
        }
        .alert("Couldn’t save plan", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "Your existing plan is unchanged.")
        }
    }

    private func moveWorkouts(from source: IndexSet, to destination: Int) {
        var reordered = orderedWorkouts
        reordered.move(fromOffsets: source, toOffset: destination)
        do { try PlanEditingService.reorderWorkouts(reordered, in: modelContext) }
        catch { saveError = "The workout order was not changed." }
    }

    private func chooseNext(_ workout: WorkoutTemplateRecord) {
        do {
            try PlanEditingService.chooseNextWorkout(
                workout,
                canonicalAnchor: anchor,
                currentDay: DomainDay.containing(
                    .now,
                    calendar: .autoupdatingCurrent,
                    cutoffMinutes: AppSettingsRecord.canonical(in: settingsRecords)?.domainDayCutoffMinutes ?? 180
                ),
                in: modelContext
            )
        } catch {
            saveError = "The next workout was not changed."
        }
    }
}

struct WorkoutPlanEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var workouts: [WorkoutTemplateRecord]
    @Query private var exercises: [ExercisePrescriptionRecord]
    @State private var name = ""
    @State private var focus = ""
    @State private var recoveryDays = 0
    @State private var didLoad = false
    @State private var editor: ExerciseEditorDestination?
    @State private var saveError: String?

    let workoutID: UUID
    private var workout: WorkoutTemplateRecord? { workouts.first { $0.id == workoutID } }
    private var orderedExercises: [ExercisePrescriptionRecord] {
        exercises.filter { $0.workoutTemplateID == workoutID && !$0.isArchived }.sorted {
            ($0.orderIndex, $0.id.uuidString) < ($1.orderIndex, $1.id.uuidString)
        }
    }

    var body: some View {
        List {
            Section("Workout") {
                TextField("Name", text: $name)
                TextField("Focus", text: $focus)
                Stepper("Recovery days after: \(recoveryDays)", value: $recoveryDays, in: 0...14)
                Button("Save workout") { saveWorkout() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section("Exercises") {
                ForEach(orderedExercises) { exercise in
                    Button { editor = .edit(exercise.id) } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(exercise.displayName).foregroundStyle(.primary)
                                Text("\(exercise.workingSetCount) × \(exercise.repMinimum)–\(exercise.repMaximum) \(exercise.repUnitRaw)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) { archive(exercise) }
                    }
                }
                .onMove(perform: moveExercises)
                Button("Add exercise", systemImage: "plus") { editor = .new(workoutID) }
            }
        }
        .navigationTitle(workout?.name ?? "Workout")
        .toolbar { EditButton() }
        .onAppear(perform: load)
        .sheet(item: $editor) { destination in
            ExercisePlanEditor(destination: destination)
        }
        .alert("Couldn’t save workout", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(saveError ?? "Try again.") }
    }

    private func load() {
        guard !didLoad, let workout else { return }
        name = workout.name
        focus = workout.focus
        recoveryDays = workout.recoveryDaysAfter
        didLoad = true
    }

    private func saveWorkout() {
        guard let workout else { return }
        workout.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        workout.focus = focus.trimmingCharacters(in: .whitespacesAndNewlines)
        workout.recoveryDaysAfter = recoveryDays
        workout.updatedAt = .now
        do { try PlanEditingService.save(modelContext) }
        catch { saveError = "The workout changes were not saved."; didLoad = false; load() }
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        var reordered = orderedExercises
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, exercise) in reordered.enumerated() {
            exercise.orderIndex = index
            exercise.updatedAt = .now
        }
        do { try PlanEditingService.save(modelContext) }
        catch { saveError = "The exercise order was not changed." }
    }

    private func archive(_ exercise: ExercisePrescriptionRecord) {
        exercise.isArchived = true
        exercise.updatedAt = .now
        do { try PlanEditingService.save(modelContext) }
        catch { saveError = "The exercise was not removed." }
    }
}

enum ExerciseEditorDestination: Identifiable {
    case new(UUID)
    case edit(UUID)

    var id: String {
        switch self {
        case let .new(id): "new-\(id)"
        case let .edit(id): "edit-\(id)"
        }
    }
}

struct ExercisePlanEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var exercises: [ExercisePrescriptionRecord]
    @Query private var alternatives: [ExerciseAlternativeRecord]
    @Query private var settingsRecords: [AppSettingsRecord]
    @State private var name = ""
    @State private var sets = 3
    @State private var repMinimum = 8
    @State private var repMaximum = 12
    @State private var repUnit = "reps"
    @State private var loadIncrement = 2.5
    @State private var isOptional = false
    @State private var notes = ""
    @State private var alternativeNames = ""
    @State private var didLoad = false
    @State private var saveError: String?

    let destination: ExerciseEditorDestination
    private var exerciseID: UUID? { if case let .edit(id) = destination { id } else { nil } }
    private var workoutID: UUID {
        switch destination {
        case let .new(id): id
        case let .edit(id): exercises.first { $0.id == id }?.workoutTemplateID ?? UUID()
        }
    }
    private var exercise: ExercisePrescriptionRecord? { exerciseID.flatMap { id in exercises.first { $0.id == id } } }
    private var unitSystem: UnitSystemOption {
        UnitSystemOption(rawValue: AppSettingsRecord.canonical(in: settingsRecords)?.unitSystemRaw ?? "metric") ?? .metric
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    TextField("Name", text: $name)
                    Stepper("Working sets: \(sets)", value: $sets, in: 1...12)
                    Stepper("Minimum reps: \(repMinimum)", value: $repMinimum, in: 1...100)
                    Stepper("Maximum reps: \(repMaximum)", value: $repMaximum, in: repMinimum...100)
                    Picker("Unit", selection: $repUnit) {
                        Text("Reps").tag("reps")
                        Text("Seconds").tag("seconds")
                    }
                    TextField(
                        "Load increment (\(MeasurementKind.weight.unit(unitSystem: unitSystem)))",
                        value: $loadIncrement,
                        format: .number
                    )
                        .keyboardType(.decimalPad)
                    Toggle("Optional", isOn: $isOptional)
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5)
                }
                Section {
                    TextField("Alternatives", text: $alternativeNames, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("Alternatives")
                } footer: {
                    Text("Enter one alternative per line. Order is preserved.")
                }
            }
            .navigationTitle(exerciseID == nil ? "Add exercise" : "Edit exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || repMaximum < repMinimum || loadIncrement < 0)
                }
            }
            .onAppear(perform: load)
            .alert("Couldn’t save exercise", isPresented: Binding(
                get: { saveError != nil }, set: { if !$0 { saveError = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(saveError ?? "Try again.") }
        }
    }

    private func load() {
        guard !didLoad else { return }
        if let exercise {
            name = exercise.displayName
            sets = exercise.workingSetCount
            repMinimum = exercise.repMinimum
            repMaximum = exercise.repMaximum
            repUnit = exercise.repUnitRaw
            loadIncrement = MeasurementKind.weight.displayValue(
                metricValue: exercise.loadIncrementKg,
                unitSystem: unitSystem
            )
            isOptional = exercise.isOptional
            notes = exercise.notes
            alternativeNames = alternatives.filter { $0.prescriptionID == exercise.id }
                .sorted { ($0.orderIndex, $0.id.uuidString) < ($1.orderIndex, $1.id.uuidString) }
                .map(\.displayName).joined(separator: "\n")
        } else {
            loadIncrement = MeasurementKind.weight.displayValue(metricValue: 2.5, unitSystem: unitSystem)
        }
        didLoad = true
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let record = exercise ?? ExercisePrescriptionRecord(
            workoutTemplateID: workoutID,
            displayName: trimmed,
            orderIndex: exercises.count { $0.workoutTemplateID == workoutID && !$0.isArchived },
            workingSetCount: sets,
            repMinimum: repMinimum,
            repMaximum: repMaximum
        )
        if exercise == nil { modelContext.insert(record) }
        record.displayName = trimmed
        record.workingSetCount = sets
        record.repMinimum = repMinimum
        record.repMaximum = repMaximum
        record.repUnitRaw = repUnit
        record.loadIncrementKg = MeasurementKind.weight.metricValue(
            displayValue: loadIncrement,
            unitSystem: unitSystem
        )
        record.isOptional = isOptional
        record.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        record.updatedAt = .now

        let names = alternativeNames.split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let existing = alternatives.filter { $0.prescriptionID == record.id }.sorted { $0.orderIndex < $1.orderIndex }
        for (index, alternativeName) in names.enumerated() {
            let alternative: ExerciseAlternativeRecord
            if existing.indices.contains(index) { alternative = existing[index] }
            else {
                alternative = ExerciseAlternativeRecord(prescriptionID: record.id, displayName: alternativeName, orderIndex: index)
                modelContext.insert(alternative)
            }
            alternative.displayName = alternativeName
            alternative.orderIndex = index
            alternative.updatedAt = .now
        }
        for obsolete in existing.dropFirst(names.count) { modelContext.delete(obsolete) }

        do { try PlanEditingService.save(modelContext); dismiss() }
        catch { saveError = "The exercise changes were not saved." }
    }
}
