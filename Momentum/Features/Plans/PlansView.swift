import MomentumCore
import SwiftData
import SwiftUI

struct PlansView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var workouts: [WorkoutTemplateRecord]
    @Query private var exercises: [ExercisePrescriptionRecord]
    @Query private var anchors: [CycleAnchorRecord]
    @Query private var settingsRecords: [AppSettingsRecord]
    @Query private var nutritionTargets: [NutritionTargetRecord]
    @Query private var careRoutines: [CareRoutineTemplateRecord]
    @Query private var careTasks: [CareTaskTemplateRecord]

    @State private var calorieDisplayTarget = 2_400
    @State private var calorieMinimum = 2_300
    @State private var calorieMaximum = 2_500
    @State private var proteinMinimum = 150
    @State private var saveError: String?
    @State private var loadedTargetID: UUID?

    private var settings: AppSettingsRecord? { AppSettingsRecord.canonical(in: settingsRecords) }
    private var orderedWorkouts: [WorkoutTemplateRecord] {
        workouts.filter { !$0.isArchived }.sorted {
            ($0.sequenceIndex, $0.id.uuidString) < ($1.sequenceIndex, $1.id.uuidString)
        }
    }
    private var orderedRoutines: [CareRoutineTemplateRecord] {
        careRoutines.filter { !$0.isArchived }.sorted {
            ($0.notificationMinutes, $0.name, $0.id.uuidString) <
                ($1.notificationMinutes, $1.name, $1.id.uuidString)
        }
    }
    private var anchor: CycleAnchorRecord? {
        anchors.max { ($0.updatedAt, $0.id.uuidString) < ($1.updatedAt, $1.id.uuidString) }
    }

    var body: some View {
        List {
            workoutSection
            nutritionSection
            careSection
        }
        .navigationTitle("Plans")
        .toolbar { EditButton() }
        .onAppear { loadNutritionTarget() }
        .alert("Couldn’t save plan", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "Your existing plan is unchanged.")
        }
    }

    private var workoutSection: some View {
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
    }

    private var nutritionSection: some View {
        Section {
            Stepper("Display target: \(calorieDisplayTarget) kcal", value: $calorieDisplayTarget, in: 0...10_000, step: 50)
            Stepper("Minimum calories: \(calorieMinimum)", value: $calorieMinimum, in: 0...calorieMaximum, step: 50)
            Stepper("Maximum calories: \(calorieMaximum)", value: $calorieMaximum, in: calorieMinimum...10_000, step: 50)
            Stepper("Minimum protein: \(proteinMinimum) g", value: $proteinMinimum, in: 0...500, step: 5)
            Button("Save target from today") { saveNutritionTarget() }
                .buttonStyle(.borderedProminent)
                .disabled(calorieDisplayTarget < calorieMinimum || calorieDisplayTarget > calorieMaximum)
        } header: {
            Text("Nutrition target")
        } footer: {
            Text("A new effective-dated target starts today. Finalized days retain their historical snapshots.")
        }
    }

    private var careSection: some View {
        Section {
            ForEach(orderedRoutines) { routine in
                NavigationLink {
                    CarePlanEditor(routineID: routine.id)
                } label: {
                    VStack(alignment: .leading, spacing: MomentumSpacing.xs) {
                        Text(routine.name).font(.headline)
                        Text("\(careTasks.count { $0.routineTemplateID == routine.id && !$0.isArchived }) tasks · \(formattedTime(routine.notificationMinutes))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Care routines")
        } footer: {
            Text("Edit future recurrence, task order, instructions, ingredients, and reminder times. Logged occurrences keep their snapshots.")
        }
    }

    private func loadNutritionTarget() {
        let today = currentDomainDay
        guard let target = NutritionPlanService.target(for: today, in: nutritionTargets),
              loadedTargetID != target.id else { return }
        calorieDisplayTarget = target.calorieDisplayTarget
        calorieMinimum = target.calorieMinimum
        calorieMaximum = target.calorieMaximum
        proteinMinimum = target.proteinMinimumGrams
        loadedTargetID = target.id
    }

    private func saveNutritionTarget() {
        do {
            try NutritionPlanService.saveTarget(
                effectiveFrom: currentDomainDay,
                displayTarget: calorieDisplayTarget,
                calorieMinimum: calorieMinimum,
                calorieMaximum: calorieMaximum,
                proteinMinimum: proteinMinimum,
                in: modelContext
            )
            loadedTargetID = NutritionPlanService.target(for: currentDomainDay, in: nutritionTargets)?.id
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription ?? "The nutrition target was not saved."
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
                currentDay: currentDomainDay,
                in: modelContext
            )
        } catch {
            saveError = "The next workout was not changed."
        }
    }

    private var currentDomainDay: DomainDay {
        DomainDay.containing(
            .now,
            calendar: .autoupdatingCurrent,
            cutoffMinutes: settings?.domainDayCutoffMinutes ?? 180
        )
    }

    private func formattedTime(_ minutes: Int) -> String {
        let date = Calendar.autoupdatingCurrent.date(
            from: DateComponents(hour: minutes / 60, minute: minutes % 60)
        ) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

@MainActor
enum NutritionPlanService {
    enum SaveError: LocalizedError {
        case invalidRange

        var errorDescription: String? {
            "The display target must be inside the calorie range, and all targets must be non-negative."
        }
    }

    static func target(for day: DomainDay, in targets: [NutritionTargetRecord]) -> NutritionTargetRecord? {
        let value = PersistedDomainDay.encode(day)
        return targets
            .filter { $0.effectiveFrom <= value && ($0.effectiveTo == nil || $0.effectiveTo! >= value) }
            .max { ($0.effectiveFrom, $0.updatedAt, $0.id.uuidString) < ($1.effectiveFrom, $1.updatedAt, $1.id.uuidString) }
    }

    static func saveTarget(
        effectiveFrom day: DomainDay,
        displayTarget: Int,
        calorieMinimum: Int,
        calorieMaximum: Int,
        proteinMinimum: Int,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        in context: ModelContext
    ) throws {
        guard calorieMinimum >= 0, calorieMaximum >= calorieMinimum,
              displayTarget >= calorieMinimum, displayTarget <= calorieMaximum,
              proteinMinimum >= 0 else { throw SaveError.invalidRange }

        let dayValue = PersistedDomainDay.encode(day)
        let previousDay = PersistedDomainDay.encode(day.adding(days: -1, calendar: calendar))
        let targets = try context.fetch(FetchDescriptor<NutritionTargetRecord>())
        let sameDay = targets.filter { $0.effectiveFrom == dayValue }.sorted {
            ($0.updatedAt, $0.id.uuidString) > ($1.updatedAt, $1.id.uuidString)
        }
        let target = sameDay.first ?? NutritionTargetRecord(effectiveFrom: dayValue)
        if sameDay.isEmpty { context.insert(target) }
        for duplicate in sameDay.dropFirst() { context.delete(duplicate) }

        for existing in targets where existing.id != target.id {
            if existing.effectiveFrom < dayValue,
               existing.effectiveTo == nil || existing.effectiveTo! >= dayValue {
                existing.effectiveTo = previousDay
                existing.updatedAt = now
            } else if existing.effectiveFrom > dayValue {
                context.delete(existing)
            }
        }

        target.effectiveTo = nil
        target.calorieDisplayTarget = displayTarget
        target.calorieMinimum = calorieMinimum
        target.calorieMaximum = calorieMaximum
        target.proteinMinimumGrams = proteinMinimum
        target.updatedAt = now
        do { try context.save() }
        catch { context.rollback(); throw error }
    }
}

@MainActor
enum PlanEditingService {
    static func reorderWorkouts(_ workouts: [WorkoutTemplateRecord], now: Date = .now, in context: ModelContext) throws {
        for (index, workout) in workouts.enumerated() {
            workout.sequenceIndex = index
            workout.updatedAt = now
        }
        try save(context)
    }

    static func chooseNextWorkout(
        _ workout: WorkoutTemplateRecord,
        canonicalAnchor: CycleAnchorRecord?,
        currentDay: DomainDay,
        now: Date = .now,
        in context: ModelContext
    ) throws {
        let anchor = canonicalAnchor ?? CycleAnchorRecord(
            nextWorkoutTemplateID: workout.id,
            firstDueDomainDay: PersistedDomainDay.encode(currentDay)
        )
        anchor.nextWorkoutTemplateID = workout.id
        anchor.updatedAt = now
        if canonicalAnchor == nil { context.insert(anchor) }
        try save(context)
    }

    static func save(_ context: ModelContext) throws {
        do { try context.save() }
        catch { context.rollback(); throw error }
    }
}

private struct WorkoutPlanEditor: View {
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

private enum ExerciseEditorDestination: Identifiable {
    case new(UUID)
    case edit(UUID)

    var id: String {
        switch self {
        case let .new(id): "new-\(id)"
        case let .edit(id): "edit-\(id)"
        }
    }
}

private struct ExercisePlanEditor: View {
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

private struct CarePlanEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var routines: [CareRoutineTemplateRecord]
    @Query private var tasks: [CareTaskTemplateRecord]
    @State private var name = ""
    @State private var notificationMinutes = 9 * 60
    @State private var recurrence = CareRecurrenceDraft.daily
    @State private var didLoad = false
    @State private var taskEditor: CareTaskEditorDestination?
    @State private var saveError: String?

    let routineID: UUID
    private var routine: CareRoutineTemplateRecord? { routines.first { $0.id == routineID } }
    private var orderedTasks: [CareTaskTemplateRecord] {
        tasks.filter { $0.routineTemplateID == routineID && !$0.isArchived }.sorted {
            ($0.orderIndex, $0.id.uuidString) < ($1.orderIndex, $1.id.uuidString)
        }
    }

    var body: some View {
        List {
            Section("Routine") {
                TextField("Name", text: $name)
                DatePicker("Reminder", selection: reminderBinding, displayedComponents: .hourAndMinute)
                Picker("Recurrence", selection: $recurrence.kind) {
                    ForEach(CareRecurrenceDraft.Kind.allCases) { kind in Text(kind.title).tag(kind) }
                }
                if recurrence.kind == .weekdays {
                    ForEach(1...7, id: \.self) { weekday in
                        Toggle(Calendar.current.weekdaySymbols[weekday - 1], isOn: weekdayBinding(weekday))
                    }
                } else if recurrence.kind == .alternating {
                    DatePicker("Next due", selection: $recurrence.anchorDate, displayedComponents: .date)
                    Text("Alternates every 3 and 4 days.").font(.footnote).foregroundStyle(.secondary)
                }
                Button("Save routine") { saveRoutine() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (recurrence.kind == .weekdays && recurrence.weekdays.isEmpty))
            }
            Section("Tasks") {
                ForEach(orderedTasks) { task in
                    Button { taskEditor = .edit(task.id) } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(task.label).foregroundStyle(.primary)
                                Text(task.genericProductRole ?? task.activeIngredient ?? "Instruction")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                    .swipeActions { Button("Remove", role: .destructive) { archive(task) } }
                }
                .onMove(perform: moveTasks)
                Button("Add task", systemImage: "plus") { taskEditor = .new(routineID) }
            }
        }
        .navigationTitle(routine?.name ?? "Care routine")
        .toolbar { EditButton() }
        .onAppear(perform: load)
        .sheet(item: $taskEditor) { destination in CareTaskPlanEditor(destination: destination) }
        .alert("Couldn’t save care plan", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(saveError ?? "Try again.") }
    }

    private func load() {
        guard !didLoad, let routine else { return }
        name = routine.name
        notificationMinutes = routine.notificationMinutes
        recurrence = CareRecurrenceDraft(payload: routine.recurrencePayload)
        didLoad = true
    }

    private var reminderBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: DateComponents(hour: notificationMinutes / 60, minute: notificationMinutes % 60)) ?? .now },
            set: {
                let components = Calendar.current.dateComponents([.hour, .minute], from: $0)
                notificationMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }

    private func weekdayBinding(_ weekday: Int) -> Binding<Bool> {
        Binding(
            get: { recurrence.weekdays.contains(weekday) },
            set: { selected in
                if selected { recurrence.weekdays.insert(weekday) } else { recurrence.weekdays.remove(weekday) }
            }
        )
    }

    private func saveRoutine() {
        guard let routine else { return }
        do {
            routine.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            routine.notificationMinutes = notificationMinutes
            routine.recurrenceKindRaw = recurrence.kind.rawValue
            routine.recurrencePayload = try recurrence.encodedPayload()
            routine.updatedAt = .now
            try PlanEditingService.save(modelContext)
        } catch {
            saveError = "The routine changes were not saved."
        }
    }

    private func moveTasks(from source: IndexSet, to destination: Int) {
        var reordered = orderedTasks
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, task) in reordered.enumerated() { task.orderIndex = index; task.updatedAt = .now }
        do { try PlanEditingService.save(modelContext) }
        catch { saveError = "The task order was not changed." }
    }

    private func archive(_ task: CareTaskTemplateRecord) {
        task.isArchived = true
        task.updatedAt = .now
        do { try PlanEditingService.save(modelContext) }
        catch { saveError = "The task was not removed." }
    }
}

private struct CareRecurrenceDraft {
    enum Kind: String, CaseIterable, Identifiable {
        case daily
        case weekdays
        case alternating
        var id: String { rawValue }
        var title: String {
            switch self { case .daily: "Daily"; case .weekdays: "Days of week"; case .alternating: "Alternating 3/4 days" }
        }
    }

    var kind: Kind
    var weekdays: Set<Int>
    var anchorDate: Date

    static let daily = CareRecurrenceDraft(kind: .daily, weekdays: Set(1...7), anchorDate: .now)

    init(kind: Kind, weekdays: Set<Int>, anchorDate: Date) {
        self.kind = kind
        self.weekdays = weekdays
        self.anchorDate = anchorDate
    }

    init(payload: String) {
        guard let data = payload.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(CareRecurrencePayload.self, from: data) else {
            self = .daily
            return
        }
        switch decoded.rule {
        case .daily: self = .daily
        case let .weekdays(days): self.init(kind: .weekdays, weekdays: days, anchorDate: .now)
        case let .alternating(anchor, _, _):
            self.init(
                kind: .alternating,
                weekdays: [],
                anchorDate: PersistedDomainDay.date(for: anchor, calendar: .autoupdatingCurrent) ?? .now
            )
        case .unsupported: self = .daily
        }
    }

    func encodedPayload() throws -> String {
        let rule: CareRecurrenceRule
        switch kind {
        case .daily: rule = .daily
        case .weekdays: rule = .weekdays(weekdays)
        case .alternating:
            let day = DomainDay.containing(anchorDate, calendar: .autoupdatingCurrent, cutoffMinutes: 0)
            rule = .alternating(anchorDueDay: day, intervals: [3, 4], intervalAfterAnchorIndex: 0)
        }
        let data = try JSONEncoder().encode(CareRecurrencePayload(rule: rule))
        guard let value = String(data: data, encoding: .utf8) else { throw CocoaError(.fileWriteInapplicableStringEncoding) }
        return value
    }
}

private enum CareTaskEditorDestination: Identifiable {
    case new(UUID)
    case edit(UUID)
    var id: String {
        switch self { case let .new(id): "new-\(id)"; case let .edit(id): "edit-\(id)" }
    }
}

private struct CareTaskPlanEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [CareTaskTemplateRecord]
    @State private var label = ""
    @State private var productRole = ""
    @State private var activeIngredient = ""
    @State private var instruction = ""
    @State private var requirement = "required"
    @State private var conditionGroup = ""
    @State private var didLoad = false
    @State private var saveError: String?

    let destination: CareTaskEditorDestination
    private var taskID: UUID? { if case let .edit(id) = destination { id } else { nil } }
    private var task: CareTaskTemplateRecord? { taskID.flatMap { id in tasks.first { $0.id == id } } }
    private var routineID: UUID {
        switch destination { case let .new(id): id; case let .edit(id): tasks.first { $0.id == id }?.routineTemplateID ?? UUID() }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Task", text: $label)
                TextField("Generic product role", text: $productRole)
                TextField("Active ingredient", text: $activeIngredient)
                TextField("Instructions", text: $instruction, axis: .vertical).lineLimit(2...5)
                Picker("Requirement", selection: $requirement) {
                    Text("Required").tag("required")
                    Text("Optional").tag("optional")
                    Text("Choose one").tag("conditional")
                }
                if requirement == "conditional" { TextField("Choice group", text: $conditionGroup) }
            }
            .navigationTitle(taskID == nil ? "Add task" : "Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (requirement == "conditional" && conditionGroup.isEmpty))
                }
            }
            .onAppear(perform: load)
            .alert("Couldn’t save task", isPresented: Binding(
                get: { saveError != nil }, set: { if !$0 { saveError = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(saveError ?? "Try again.") }
        }
    }

    private func load() {
        guard !didLoad else { return }
        if let task {
            label = task.label
            productRole = task.genericProductRole ?? ""
            activeIngredient = task.activeIngredient ?? ""
            instruction = task.instruction ?? ""
            requirement = task.requirementKindRaw
            conditionGroup = task.conditionGroup ?? ""
        }
        didLoad = true
    }

    private func save() {
        let value = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let record = task ?? CareTaskTemplateRecord(
            routineTemplateID: routineID,
            label: value,
            orderIndex: tasks.count { $0.routineTemplateID == routineID && !$0.isArchived }
        )
        if task == nil { modelContext.insert(record) }
        record.label = value
        record.genericProductRole = productRole.nilIfBlank
        record.activeIngredient = activeIngredient.nilIfBlank
        record.instruction = instruction.nilIfBlank
        record.requirementKindRaw = requirement
        record.conditionGroup = requirement == "conditional" ? conditionGroup.nilIfBlank : nil
        record.updatedAt = .now
        do { try PlanEditingService.save(modelContext); dismiss() }
        catch { saveError = "The task changes were not saved." }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
