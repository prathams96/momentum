import Foundation
import MomentumCore
import SwiftData

struct CareExportRow: Sendable {
    let occurrenceID: String
    let routineTemplateID: String?
    let routineName: String
    let domainDay: String
    let dueAt: String
    let occurrenceStatus: String
    let occurrenceCompletedAt: String?
    let skippedAt: String?
    let rolledFromDomainDay: String?
    let taskCompletionID: String?
    let taskTemplateID: String?
    let taskLabel: String?
    let taskInstruction: String?
    let taskStatus: String?
    let selectedVariant: String?
    let taskCompletedAt: String?
    let createdAt: String
    let updatedAt: String

    @MainActor
    init(occurrence: CareOccurrenceRecord, task: CareTaskCompletionRecord? = nil) {
        occurrenceID = CSVFormat.uuid(occurrence.id)
        routineTemplateID = occurrence.routineTemplateID.map(CSVFormat.uuid)
        routineName = occurrence.routineNameSnapshot
        domainDay = occurrence.dueDomainDay
        dueAt = CSVFormat.date(occurrence.dueAt)
        occurrenceStatus = occurrence.statusRaw
        occurrenceCompletedAt = occurrence.completedAt.map(CSVFormat.date)
        skippedAt = occurrence.skippedAt.map(CSVFormat.date)
        rolledFromDomainDay = occurrence.rolledFromDomainDay
        taskCompletionID = task.map { CSVFormat.uuid($0.id) }
        taskTemplateID = task?.taskTemplateID.map(CSVFormat.uuid)
        taskLabel = task?.labelSnapshot
        taskInstruction = task?.instructionSnapshot
        taskStatus = task?.statusRaw
        selectedVariant = task?.selectedVariant
        taskCompletedAt = task?.completedAt.map(CSVFormat.date)
        createdAt = CSVFormat.date(occurrence.createdAt)
        updatedAt = CSVFormat.date(occurrence.updatedAt)
    }
}

extension CareModuleAdapter: ExportDefinitionProviding {
    func exportDefinitions() -> [ModuleExportDefinition] {
        [ModuleExportDefinition(
            moduleID: metadata.id,
            fileName: "care.csv",
            header: Self.header,
            rowsProvider: { context in
                let occurrences = try context.fetch(FetchDescriptor<CareOccurrenceRecord>())
                let tasks = try context.fetch(FetchDescriptor<CareTaskCompletionRecord>())
                return Self.makeRows(occurrences: occurrences, tasks: tasks)
            }
        )]
    }

    private static let header = ["occurrence_id", "routine_template_id", "routine_name_snapshot", "domain_day", "due_at", "occurrence_status", "occurrence_completed_at", "skipped_at", "rolled_from_domain_day", "task_completion_id", "task_template_id", "task_label_snapshot", "task_instruction_snapshot", "task_status", "selected_variant", "task_completed_at", "created_at", "updated_at"]

    @MainActor
    private static func makeRows(
        occurrences: [CareOccurrenceRecord],
        tasks: [CareTaskCompletionRecord]
    ) -> [[String]] {
        let tasksByOccurrence = Dictionary(grouping: tasks, by: \.occurrenceID)
        var rows: [CareExportRow] = []
        for occurrence in occurrences {
            let occurrenceTasks = (tasksByOccurrence[occurrence.id] ?? []).sorted {
                ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
            }
            if occurrenceTasks.isEmpty {
                rows.append(CareExportRow(occurrence: occurrence))
            } else {
                rows.append(contentsOf: occurrenceTasks.map {
                    CareExportRow(occurrence: occurrence, task: $0)
                })
            }
        }
        return rows.sorted {
            ($0.domainDay, $0.dueAt, $0.occurrenceID, $0.taskCompletionID ?? "") <
                ($1.domainDay, $1.dueAt, $1.occurrenceID, $1.taskCompletionID ?? "")
        }
        .map(fields)
    }

    private static func fields(_ row: CareExportRow) -> [String] {
        [row.occurrenceID, row.routineTemplateID, row.routineName, row.domainDay, row.dueAt,
         row.occurrenceStatus, row.occurrenceCompletedAt, row.skippedAt,
         row.rolledFromDomainDay, row.taskCompletionID, row.taskTemplateID, row.taskLabel,
         row.taskInstruction, row.taskStatus, row.selectedVariant, row.taskCompletedAt,
         row.createdAt, row.updatedAt].map { $0 ?? "" }
    }
}
