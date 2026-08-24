import Foundation
import MomentumCore
import SwiftData

struct WorkoutExportRow: Sendable {
    let recordType: String
    let eventID: String?
    let eventKind: String?
    let sessionID: String?
    let workoutTemplateID: String?
    let workoutName: String?
    let focus: String?
    let sequenceIndex: Int?
    let domainDay: String
    let completionDomainDay: String?
    let startedAt: String?
    let finishedAt: String?
    let startedEarly: Bool?
    let sessionNote: String?
    let exerciseLogID: String?
    let prescriptionID: String?
    let exerciseName: String?
    let exerciseOrder: Int?
    let setCountSnapshot: Int?
    let repMinimumSnapshot: Int?
    let repMaximumSnapshot: Int?
    let exerciseNotes: String?
    let exerciseStatus: String?
    let setLogID: String?
    let setNumber: Int?
    let weightKg: Double?
    let repetitions: Int?
    let rir: Int?
    let setStatus: String?
    let setNote: String?
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    @MainActor
    init(session: WorkoutSessionRecord, exercise: ExerciseLogRecord? = nil, set: SetLogRecord? = nil) {
        recordType = "session"
        eventID = nil
        eventKind = nil
        sessionID = CSVFormat.uuid(session.id)
        workoutTemplateID = session.workoutTemplateID.map(CSVFormat.uuid)
        workoutName = session.workoutNameSnapshot
        focus = session.focusSnapshot
        sequenceIndex = session.sequenceIndexSnapshot
        domainDay = session.scheduledDomainDay
        completionDomainDay = session.completionDomainDay
        startedAt = CSVFormat.date(session.startedAt)
        finishedAt = session.finishedAt.map(CSVFormat.date)
        startedEarly = session.startedEarly
        sessionNote = session.note
        exerciseLogID = exercise.map { CSVFormat.uuid($0.id) }
        prescriptionID = exercise?.prescriptionID.map(CSVFormat.uuid)
        exerciseName = exercise?.exerciseNameSnapshot
        exerciseOrder = exercise?.orderIndex
        setCountSnapshot = exercise?.setCountSnapshot
        repMinimumSnapshot = exercise?.repMinimumSnapshot
        repMaximumSnapshot = exercise?.repMaximumSnapshot
        exerciseNotes = exercise?.notesSnapshot
        exerciseStatus = exercise?.statusRaw
        setLogID = set.map { CSVFormat.uuid($0.id) }
        setNumber = set?.setNumber
        weightKg = set?.weightKg
        repetitions = set?.repetitions
        rir = set?.rir
        setStatus = set?.statusRaw
        setNote = set?.note
        createdAt = CSVFormat.date(session.createdAt)
        updatedAt = CSVFormat.date(session.updatedAt)
        deletedAt = session.deletedAt.map(CSVFormat.date)
    }

    @MainActor
    init(event: WorkoutDayEventRecord) {
        recordType = "day_event"
        eventID = CSVFormat.uuid(event.id)
        eventKind = event.kindRaw
        sessionID = nil
        workoutTemplateID = CSVFormat.uuid(event.dueWorkoutTemplateID)
        workoutName = nil
        focus = nil
        sequenceIndex = nil
        domainDay = event.domainDay
        completionDomainDay = nil
        startedAt = nil
        finishedAt = nil
        startedEarly = nil
        sessionNote = nil
        exerciseLogID = nil
        prescriptionID = nil
        exerciseName = nil
        exerciseOrder = nil
        setCountSnapshot = nil
        repMinimumSnapshot = nil
        repMaximumSnapshot = nil
        exerciseNotes = nil
        exerciseStatus = nil
        setLogID = nil
        setNumber = nil
        weightKg = nil
        repetitions = nil
        rir = nil
        setStatus = nil
        setNote = nil
        createdAt = CSVFormat.date(event.createdAt)
        updatedAt = CSVFormat.date(event.updatedAt)
        deletedAt = event.deletedAt.map(CSVFormat.date)
    }
}

extension WorkoutModuleAdapter: ExportDefinitionProviding {
    func exportDefinitions() -> [ModuleExportDefinition] {
        [ModuleExportDefinition(
            moduleID: metadata.id,
            fileName: "workouts.csv",
            header: Self.header,
            rowsProvider: { context in
                let sessions = try context.fetch(FetchDescriptor<WorkoutSessionRecord>())
                let exerciseLogs = try context.fetch(FetchDescriptor<ExerciseLogRecord>())
                let setLogs = try context.fetch(FetchDescriptor<SetLogRecord>())
                let events = try context.fetch(FetchDescriptor<WorkoutDayEventRecord>())
                return Self.makeRows(
                    sessions: sessions,
                    exerciseLogs: exerciseLogs,
                    setLogs: setLogs,
                    events: events
                )
            }
        )]
    }

    private static let header = ["record_type", "event_id", "event_kind", "session_id", "workout_template_id", "workout_name_snapshot", "focus_snapshot", "sequence_index_snapshot", "scheduled_domain_day", "completion_domain_day", "started_at", "finished_at", "started_early", "session_note", "exercise_log_id", "prescription_id", "exercise_name_snapshot", "exercise_order", "set_count_snapshot", "rep_minimum_snapshot", "rep_maximum_snapshot", "exercise_notes_snapshot", "exercise_status", "set_log_id", "set_number", "weight_kg", "repetitions", "rir", "set_status", "set_note", "created_at", "updated_at", "deleted_at"]

    @MainActor
    private static func makeRows(
        sessions: [WorkoutSessionRecord],
        exerciseLogs: [ExerciseLogRecord],
        setLogs: [SetLogRecord],
        events: [WorkoutDayEventRecord]
    ) -> [[String]] {
        var rows: [WorkoutExportRow] = []
        let exercisesBySession = Dictionary(grouping: exerciseLogs, by: \.workoutSessionID)
        let setsByExercise = Dictionary(grouping: setLogs, by: \.exerciseLogID)

        for session in sessions.sorted(by: {
            ($0.scheduledDomainDay, $0.startedAt, $0.id.uuidString) <
                ($1.scheduledDomainDay, $1.startedAt, $1.id.uuidString)
        }) {
            let exercises = (exercisesBySession[session.id] ?? []).sorted {
                ($0.orderIndex, $0.id.uuidString) < ($1.orderIndex, $1.id.uuidString)
            }
            if exercises.isEmpty {
                rows.append(WorkoutExportRow(session: session))
                continue
            }

            for exercise in exercises {
                let sets = (setsByExercise[exercise.id] ?? []).sorted {
                    ($0.setNumber, $0.id.uuidString) < ($1.setNumber, $1.id.uuidString)
                }
                if sets.isEmpty {
                    rows.append(WorkoutExportRow(session: session, exercise: exercise))
                } else {
                    rows.append(contentsOf: sets.map {
                        WorkoutExportRow(session: session, exercise: exercise, set: $0)
                    })
                }
            }
        }

        rows.append(contentsOf: events.map(WorkoutExportRow.init(event:)))
        return rows.sorted {
            ($0.domainDay, $0.recordType, $0.sessionID ?? $0.eventID ?? "", $0.exerciseOrder ?? -1, $0.setNumber ?? -1) <
                ($1.domainDay, $1.recordType, $1.sessionID ?? $1.eventID ?? "", $1.exerciseOrder ?? -1, $1.setNumber ?? -1)
        }
        .map(fields)
    }

    private static func fields(_ row: WorkoutExportRow) -> [String] {
        let values: [String?] = [
            row.recordType, row.eventID, row.eventKind, row.sessionID, row.workoutTemplateID,
            row.workoutName, row.focus, row.sequenceIndex.map(String.init), row.domainDay,
            row.completionDomainDay, row.startedAt, row.finishedAt, row.startedEarly.map(String.init),
            row.sessionNote, row.exerciseLogID, row.prescriptionID, row.exerciseName,
            row.exerciseOrder.map(String.init), row.setCountSnapshot.map(String.init),
            row.repMinimumSnapshot.map(String.init), row.repMaximumSnapshot.map(String.init),
            row.exerciseNotes, row.exerciseStatus, row.setLogID, row.setNumber.map(String.init),
            row.weightKg.map(CSVFormat.decimal), row.repetitions.map(String.init),
            row.rir.map(String.init), row.setStatus, row.setNote, row.createdAt, row.updatedAt,
            row.deletedAt
        ]
        return values.map { $0 ?? "" }
    }
}
