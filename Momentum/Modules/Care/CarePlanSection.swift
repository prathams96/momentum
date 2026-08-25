import MomentumCore
import SwiftData
import SwiftUI

/// The Care module's contribution to the Plans surface: routine list and the
/// routine/task editors.
struct CarePlanSection: View {
    @Query private var careRoutines: [CareRoutineTemplateRecord]
    @Query private var careTasks: [CareTaskTemplateRecord]
    @State private var saveError: String?

    private var orderedRoutines: [CareRoutineTemplateRecord] {
        careRoutines.filter { !$0.isArchived }.sorted {
            ($0.notificationMinutes, $0.name, $0.id.uuidString) <
                ($1.notificationMinutes, $1.name, $1.id.uuidString)
        }
    }

    var body: some View {
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

    private func formattedTime(_ minutes: Int) -> String {
        let date = Calendar.autoupdatingCurrent.date(
            from: DateComponents(hour: minutes / 60, minute: minutes % 60)
        ) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

struct CarePlanEditor: View {
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

struct CareRecurrenceDraft {
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

enum CareTaskEditorDestination: Identifiable {
    case new(UUID)
    case edit(UUID)
    var id: String {
        switch self { case let .new(id): "new-\(id)"; case let .edit(id): "edit-\(id)" }
    }
}

struct CareTaskPlanEditor: View {
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

extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
