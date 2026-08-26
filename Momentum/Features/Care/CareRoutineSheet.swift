import MomentumCore
import SwiftData
import SwiftUI

struct CareRoutineSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var occurrences: [CareOccurrenceRecord]
    @Query private var completions: [CareTaskCompletionRecord]
    @Query private var taskTemplates: [CareTaskTemplateRecord]
    @Query private var routines: [CareRoutineTemplateRecord]
    @Query private var settings: [AppSettingsRecord]

    @State private var saveError: String?

    private let occurrenceID: UUID

    init(occurrenceID: UUID) {
        self.occurrenceID = occurrenceID
        _occurrences = Query(filter: #Predicate<CareOccurrenceRecord> { $0.id == occurrenceID })
        _completions = Query(filter: #Predicate<CareTaskCompletionRecord> { $0.occurrenceID == occurrenceID })
    }

    private var occurrence: CareOccurrenceRecord? { occurrences.first }

    private var orderedCompletions: [CareTaskCompletionRecord] {
        completions.sorted { lhs, rhs in
            let left = lhs.taskTemplateID.flatMap(template)?.orderIndex ?? 0
            let right = rhs.taskTemplateID.flatMap(template)?.orderIndex ?? 0
            return left < right
        }
    }

    private var canCompleteRoutine: Bool {
        let required = orderedCompletions.filter { completion in
            template(completion.taskTemplateID)?.requirementKindRaw != "conditionalChoice"
        }
        let conditionalGroups = Dictionary(grouping: orderedCompletions.filter { completion in
            template(completion.taskTemplateID)?.requirementKindRaw == "conditionalChoice"
        }) { completion in
            template(completion.taskTemplateID)?.conditionGroup ?? "conditional"
        }
        return required.allSatisfy { $0.statusRaw == "completed" }
            && conditionalGroups.values.allSatisfy { group in group.contains { $0.statusRaw == "completed" } }
    }

    var body: some View {
        NavigationStack {
            List {
                if let occurrence {
                    Section {
                        LabeledContent("Due", value: occurrence.dueAt.formatted(date: .omitted, time: .shortened))
                        if let rolled = occurrence.rolledFromDomainDay {
                            Label("Rolled forward from \(rolled)", systemImage: "arrowshape.turn.up.right")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Tasks") {
                        ForEach(orderedCompletions) { completion in
                            CareTaskRow(
                                completion: completion,
                                template: template(completion.taskTemplateID),
                                selectConditional: { selectConditional(completion) }
                            )
                        }
                    }
                } else {
                    ContentUnavailableView("Routine unavailable", systemImage: "exclamationmark.triangle")
                }
            }
            .navigationTitle(occurrence?.routineNameSnapshot ?? "Personal care routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: MomentumSpacing.sm) {
                    if occurrence?.statusRaw == "completed" {
                        Button("Undo completion", systemImage: "arrow.uturn.backward") {
                            undoCompletion()
                        }
                        .buttonStyle(.bordered)
                    } else if occurrence?.statusRaw == "pending" {
                        Button("Skip today", systemImage: "forward") {
                            skipRoutine()
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(occurrence?.statusRaw == "completed" ? "Completed" : "Complete routine") {
                        completeRoutine()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MomentumTheme.pulse)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(!canCompleteRoutine || occurrence?.statusRaw == "completed")
                }
                .padding(MomentumSpacing.md)
                .background(.bar)
            }
        }
        .alert("Couldn’t save routine", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("Retry") { completeRoutine() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text(saveError ?? "Your task choices are still on screen.")
        }
    }

    private func template(_ id: UUID?) -> CareTaskTemplateRecord? {
        guard let id else { return nil }
        return taskTemplates.first { $0.id == id }
    }

    private func selectConditional(_ selected: CareTaskCompletionRecord) {
        guard let group = template(selected.taskTemplateID)?.conditionGroup else {
            toggle(selected)
            return
        }
        for completion in completions where template(completion.taskTemplateID)?.conditionGroup == group {
            let isSelected = completion.id == selected.id
            completion.statusRaw = isSelected ? "completed" : "skipped"
            completion.selectedVariant = isSelected ? completion.labelSnapshot : nil
            completion.completedAt = isSelected ? .now : nil
            completion.updatedAt = .now
        }
        persist()
    }

    private func toggle(_ completion: CareTaskCompletionRecord) {
        let isCompleting = completion.statusRaw != "completed"
        completion.statusRaw = isCompleting ? "completed" : "pending"
        completion.completedAt = isCompleting ? .now : nil
        completion.updatedAt = .now
        persist()
    }

    private func completeRoutine() {
        guard canCompleteRoutine, let occurrence else { return }
        occurrence.statusRaw = "completed"
        occurrence.completedAt = .now
        occurrence.skippedAt = nil
        occurrence.updatedAt = .now
        advanceAlternatingRoutineIfNeeded(for: occurrence)
        guard persist() else { return }
        dismiss()
    }

    private func skipRoutine() {
        guard let occurrence, occurrence.statusRaw == "pending" else { return }
        occurrence.statusRaw = "skipped"
        occurrence.skippedAt = .now
        occurrence.completedAt = nil
        occurrence.updatedAt = .now
        guard persist() else { return }
        dismiss()
    }

    private func undoCompletion() {
        guard let occurrence, occurrence.statusRaw == "completed" else { return }
        occurrence.statusRaw = "pending"
        occurrence.completedAt = nil
        occurrence.updatedAt = .now
        for completion in completions {
            completion.statusRaw = "pending"
            completion.completedAt = nil
            completion.selectedVariant = nil
            completion.updatedAt = .now
        }
        if let routineID = occurrence.routineTemplateID,
           let routine = routines.first(where: { $0.id == routineID }),
           let previousPayload = occurrence.recurrencePayloadBeforeCompletion {
            routine.recurrencePayload = previousPayload
            routine.updatedAt = .now
            occurrence.recurrencePayloadBeforeCompletion = nil
        }
        guard persist() else { return }
    }

    private func advanceAlternatingRoutineIfNeeded(for occurrence: CareOccurrenceRecord) {
        guard let routineID = occurrence.routineTemplateID,
              let routine = routines.first(where: { $0.id == routineID }),
              routine.recurrenceKindRaw == "alternatingInterval",
              let data = routine.recurrencePayload.data(using: .utf8),
              let payload = try? JSONDecoder().decode(CareRecurrencePayload.self, from: data) else {
            return
        }
        let calendar = Calendar.autoupdatingCurrent
        let currentDay = DomainDay.containing(
            .now,
            calendar: calendar,
            cutoffMinutes: AppSettingsRecord.canonical(in: settings)?.domainDayCutoffMinutes ?? 180
        )
        guard let advanced = CareScheduleEngine().advancedAlternatingPayload(
            afterCompletionOn: currentDay,
            payload: payload,
            calendar: calendar
        ),
        let encoded = try? JSONEncoder().encode(advanced),
        let value = String(data: encoded, encoding: .utf8) else {
            return
        }
        occurrence.recurrencePayloadBeforeCompletion = routine.recurrencePayload
        routine.recurrencePayload = value
        routine.updatedAt = .now
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try modelContext.save()
            Task { try? await DailyReconciler.reconcileAndNotify(in: modelContext) }
            return true
        } catch {
            saveError = "Your changes were kept. Try saving again."
            return false
        }
    }
}

private struct CareTaskRow: View {
    @Bindable var completion: CareTaskCompletionRecord
    let template: CareTaskTemplateRecord?
    let selectConditional: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: MomentumSpacing.sm) {
                Image(systemName: completion.statusRaw == "completed" ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(completion.statusRaw == "completed" ? MomentumTheme.success : .secondary)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(completion.labelSnapshot)
                        .foregroundStyle(.primary)
                    if let instruction = completion.instructionSnapshot, !instruction.isEmpty {
                        Text(instruction)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if template?.requirementKindRaw == "conditionalChoice" {
                        Text("Choose one cleanse path")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityValue(completion.statusRaw)
    }

    private func action() {
        selectConditional()
    }
}
