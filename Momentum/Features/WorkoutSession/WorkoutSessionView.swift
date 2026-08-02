import MomentumCore
import SwiftData
import SwiftUI

struct WorkoutSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var sessions: [WorkoutSessionRecord]
    @Query private var allSessions: [WorkoutSessionRecord]
    @Query private var exerciseLogs: [ExerciseLogRecord]
    @Query private var allExerciseLogs: [ExerciseLogRecord]
    @Query private var setLogs: [SetLogRecord]
    @Query private var prescriptions: [ExercisePrescriptionRecord]
    @Query private var alternatives: [ExerciseAlternativeRecord]
    @Query private var loadSuggestions: [LoadSuggestionRecord]

    @State private var showFinishConfirmation = false
    @State private var showPostWorkoutCheckIn = false
    @State private var saveError: String?

    private let sessionID: UUID
    private let domainDayCutoffMinutes: Int

    init(sessionID: UUID, domainDayCutoffMinutes: Int) {
        self.sessionID = sessionID
        self.domainDayCutoffMinutes = domainDayCutoffMinutes
        _sessions = Query(filter: #Predicate<WorkoutSessionRecord> { $0.id == sessionID })
        _allSessions = Query()
        _exerciseLogs = Query(
            filter: #Predicate<ExerciseLogRecord> { $0.workoutSessionID == sessionID },
            sort: \ExerciseLogRecord.orderIndex
        )
        _allExerciseLogs = Query()
    }

    private var session: WorkoutSessionRecord? { sessions.first }

    private var hasUnfinishedSets: Bool {
        setLogsForSession.contains { $0.statusRaw == "pending" }
    }

    private var setLogsForSession: [SetLogRecord] {
        let exerciseIDs = Set(exerciseLogs.map(\.id))
        return setLogs.filter { exerciseIDs.contains($0.exerciseLogID) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let session {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: MomentumSpacing.xl) {
                            sessionHeader(session)

                            ForEach(exerciseLogs) { exercise in
                                ExerciseLoggingSection(
                                    exercise: exercise,
                                    sets: setLogs
                                        .filter { $0.exerciseLogID == exercise.id }
                                        .sorted { $0.setNumber < $1.setNumber },
                                    previousSets: previousSets(for: exercise),
                                    alternatives: alternatives.filter { $0.prescriptionID == exercise.prescriptionID },
                                    onSelectAlternative: { alternative in
                                        exercise.exerciseNameSnapshot = alternative.displayName
                                        exercise.updatedAt = .now
                                    },
                                    onSkipExercise: { skipExercise(exercise) }
                                )
                            }

                            WorkoutNoteField(session: session)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2...5)
                                .accessibilityLabel("Workout note")
                        }
                        .padding(MomentumSpacing.md)
                        .padding(.bottom, 88)
                    }
                } else {
                    ContentUnavailableView(
                        "Workout unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("This workout session could not be loaded.")
                    )
                }
            }
            .navigationTitle(session?.workoutNameSnapshot ?? "Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { saveAndDismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Finish workout") {
                    if hasUnfinishedSets {
                        showFinishConfirmation = true
                    } else {
                        finishWorkout()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(MomentumTheme.pulse)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, MomentumSpacing.md)
                .padding(.vertical, MomentumSpacing.sm)
                .background(.bar)
                .disabled(session == nil)
            }
        }
        .interactiveDismissDisabled()
        .sheet(isPresented: $showPostWorkoutCheckIn, onDismiss: { dismiss() }) {
            if let session {
                PostWorkoutCheckInView(session: session)
            }
        }
        .alert("Finish workout?", isPresented: $showFinishConfirmation) {
            Button("Keep logging", role: .cancel) {}
            Button("Finish workout") { finishWorkout() }
        } message: {
            Text("Some sets are unfinished. Finish this workout anyway?")
        }
        .alert("Couldn’t save workout", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("Retry") { persist() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(saveError ?? "Your entries are still on screen.")
        }
    }

    private func sessionHeader(_ session: WorkoutSessionRecord) -> some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.xs) {
            if session.startedEarly {
                Label("Started early", systemImage: "forward.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MomentumTheme.warning)
            }
            Text(session.focusSnapshot)
                .font(.body)
                .foregroundStyle(.secondary)
            Text("Log working sets only. Warm-up sets are not tracked.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func saveAndDismiss() {
        guard persist() else { return }
        dismiss()
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            saveError = "Your set entries were kept. Try saving again."
            return false
        }
    }

    private func finishWorkout() {
        guard let session else { return }

        for set in setLogsForSession where set.statusRaw == "pending" {
            set.statusRaw = "skipped"
            set.updatedAt = .now
        }
        for exercise in exerciseLogs {
            let sets = setLogs.filter { $0.exerciseLogID == exercise.id }
            exercise.statusRaw = sets.allSatisfy { $0.statusRaw == "completed" }
                ? "completed"
                : "skipped"
            exercise.updatedAt = .now

            guard exercise.statusRaw == "completed",
                  let prescriptionID = exercise.prescriptionID,
                  let prescription = prescriptions.first(where: { $0.id == prescriptionID }),
                  !loadSuggestions.contains(where: { $0.sourceSessionID == session.id && $0.prescriptionID == prescriptionID }) else {
                continue
            }
            let performance = ProgressionExerciseInput(
                prescriptionID: prescriptionID,
                isOptional: prescription.isOptional,
                exerciseStatus: .completed,
                prescribedWorkingSetCount: exercise.setCountSnapshot,
                repMaximumSnapshot: exercise.repMaximumSnapshot,
                loadIncrementKilograms: Decimal(string: String(prescription.loadIncrementKg)) ?? 0,
                workingSets: sets.map {
                    WorkingSetPerformance(
                        weightKilograms: Decimal(string: String($0.weightKg)) ?? 0,
                        repetitions: $0.repetitions,
                        status: $0.statusRaw == "completed" ? .completed : .skipped
                    )
                }
            )
            if let suggestion = ProgressionEngine().suggestion(for: performance) {
                let record = LoadSuggestionRecord(
                    prescriptionID: suggestion.prescriptionID,
                    sourceSessionID: session.id,
                    suggestedWeightKg: NSDecimalNumber(decimal: suggestion.suggestedWeightKilograms).doubleValue
                )
                modelContext.insert(record)
            }
        }

        let finishedAt = Date.now
        let day = DomainDay.containing(
            finishedAt,
            calendar: .autoupdatingCurrent,
            cutoffMinutes: domainDayCutoffMinutes
        )
        session.finishedAt = finishedAt
        session.completionDomainDay = PersistedDomainDay.encode(day)
        session.updatedAt = finishedAt

        guard persist() else { return }
        showPostWorkoutCheckIn = true
    }

    private func previousSets(for exercise: ExerciseLogRecord) -> [SetLogRecord] {
        guard let prescriptionID = exercise.prescriptionID,
              let session,
              let previousLog = (allExerciseLogs
                  .filter { $0.prescriptionID == prescriptionID && $0.workoutSessionID != session.id }
                  .compactMap { log -> (ExerciseLogRecord, WorkoutSessionRecord)? in
                      guard let source = allSessions.first(where: { $0.id == log.workoutSessionID }),
                            source.finishedAt != nil,
                            source.startedAt < session.startedAt else { return nil }
                      return (log, source)
                  }
                  .sorted(by: { $0.1.startedAt > $1.1.startedAt })
                  .first?.0) else {
            return []
        }

        let previousSetIDs = setLogs.filter { $0.exerciseLogID == previousLog.id }
        return previousSetIDs.sorted { $0.setNumber < $1.setNumber }
    }

    private func skipExercise(_ exercise: ExerciseLogRecord) {
        for set in setLogs where set.exerciseLogID == exercise.id && set.statusRaw == "pending" {
            set.statusRaw = "skipped"
            set.updatedAt = .now
        }
        exercise.statusRaw = "skipped"
        exercise.updatedAt = .now
        _ = persist()
    }
}

private struct WorkoutNoteField: View {
    @Bindable var session: WorkoutSessionRecord

    var body: some View {
        TextField("Workout note", text: $session.note, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(2...5)
            .accessibilityLabel("Workout note")
    }
}

private struct PostWorkoutCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var session: WorkoutSessionRecord

    @State private var energy = "steady"
    @State private var soreness = "none"
    @State private var note = ""
    @State private var weight = ""

    private let energyOptions = [("low", "Low"), ("steady", "Steady"), ("strong", "Strong")]
    private let sorenessOptions = [("none", "None"), ("some", "Some"), ("high", "High")]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Energy", selection: $energy) {
                        ForEach(energyOptions, id: \.0) { value, label in
                            Text(label).tag(value)
                        }
                    }
                    Picker("Soreness", selection: $soreness) {
                        ForEach(sorenessOptions, id: \.0) { value, label in
                            Text(label).tag(value)
                        }
                    }
                } header: {
                    Text("How did that feel?")
                }

                Section("Optional") {
                    TextField("Body weight (kg)", text: $weight)
                        .keyboardType(.decimalPad)
                    TextField("Anything worth remembering?", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Workout complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                }
            }
        }
        .onAppear {
            energy = session.postWorkoutEnergyRaw ?? energy
            soreness = session.postWorkoutSorenessRaw ?? soreness
            note = session.postWorkoutNote ?? ""
        }
    }

    private func save() {
        session.postWorkoutEnergyRaw = energy
        session.postWorkoutSorenessRaw = soreness
        session.postWorkoutNote = note.isEmpty ? nil : note
        if let value = Double(weight), value > 0,
           let day = PersistedDomainDay.decode(session.completionDomainDay ?? session.scheduledDomainDay) {
            modelContext.insert(BodyMeasurementRecord(
                kindRaw: "weightKg",
                value: value,
                measuredAt: .now,
                domainDay: PersistedDomainDay.encode(day),
                sourceRaw: "postWorkout"
            ))
        }
        session.updatedAt = .now
        try? modelContext.save()
        dismiss()
    }
}

private struct ExerciseLoggingSection: View {
    let exercise: ExerciseLogRecord
    let sets: [SetLogRecord]
    let previousSets: [SetLogRecord]
    let alternatives: [ExerciseAlternativeRecord]
    let onSelectAlternative: (ExerciseAlternativeRecord) -> Void
    let onSkipExercise: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.exerciseNameSnapshot)
                    .font(.headline)
                Text("\(exercise.setCountSnapshot) sets · \(exercise.repMinimumSnapshot)–\(exercise.repMaximumSnapshot) \(exercise.repUnitSnapshot)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !exercise.notesSnapshot.isEmpty {
                    Text(exercise.notesSnapshot)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Menu {
                if !alternatives.isEmpty {
                    Section("Alternatives") {
                        ForEach(alternatives.sorted { $0.orderIndex < $1.orderIndex }) { alternative in
                            Button(alternative.displayName) { onSelectAlternative(alternative) }
                        }
                    }
                }
                Button("Skip exercise", systemImage: "forward", role: .destructive, action: onSkipExercise)
            } label: {
                Label("Exercise options", systemImage: "ellipsis.circle")
                    .font(.subheadline.weight(.medium))
            }
            .accessibilityLabel("Options for \(exercise.exerciseNameSnapshot)")

            ForEach(sets) { set in
                WorkingSetRow(
                    set: set,
                    repetitionUnit: exercise.repUnitSnapshot,
                    previous: previousSets.first { $0.setNumber == set.setNumber }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, MomentumSpacing.sm)
    }
}

private struct WorkingSetRow: View {
    @Bindable var set: SetLogRecord
    let repetitionUnit: String
    let previous: SetLogRecord?

    private var rirBinding: Binding<Int> {
        Binding(
            get: { set.rir ?? 0 },
            set: { set.rir = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.xs) {
            HStack(alignment: .center, spacing: MomentumSpacing.sm) {
                Text("Set \(set.setNumber)")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 46, alignment: .leading)

                VStack(spacing: 2) {
                    TextField(
                        "kg",
                        value: $set.weightKg,
                        format: .number.precision(.fractionLength(0...2))
                    )
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    Text("kg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 2) {
                    TextField("reps", value: $set.repetitions, format: .number)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                    Text(repetitionUnit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 2) {
                    TextField("RIR", value: rirBinding, format: .number)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                    Text("RIR")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Menu {
                    Button("Complete", systemImage: "checkmark.circle") {
                        set.statusRaw = "completed"
                        set.updatedAt = .now
                    }
                    Button("Skip set", systemImage: "forward") {
                        set.statusRaw = "skipped"
                        set.updatedAt = .now
                    }
                } label: {
                    Image(systemName: statusSymbol)
                        .foregroundStyle(statusColor)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Set \(set.setNumber), \(set.statusRaw)")
            }

            if let previous, previous.statusRaw == "completed" {
                Button {
                    set.weightKg = previous.weightKg
                    set.repetitions = previous.repetitions
                    set.rir = previous.rir
                    set.updatedAt = .now
                } label: {
                    Label(
                        "Copy last time: \(DecimalFormatter.onePlace(previous.weightKg)) kg × \(previous.repetitions)",
                        systemImage: "arrow.down.doc"
                    )
                    .font(.caption)
                    .foregroundStyle(MomentumTheme.pulse)
                }
                .buttonStyle(.plain)
            }

            TextField("Optional set note", text: $set.note)
                .font(.footnote)
                .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, MomentumSpacing.xs)
    }

    private var statusSymbol: String {
        switch set.statusRaw {
        case "completed": "checkmark.circle.fill"
        case "skipped": "forward.circle.fill"
        default: "circle"
        }
    }

    private var statusColor: Color {
        switch set.statusRaw {
        case "completed": MomentumTheme.success
        case "skipped": MomentumTheme.warning
        default: .secondary
        }
    }
}
