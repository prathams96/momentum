import Foundation
import SwiftData

struct CSVExportFile: Identifiable, Hashable, Sendable {
    let name: String
    let url: URL

    var id: String { name }
}

enum CSVExportError: LocalizedError {
    case cannotEncodeUTF8(fileName: String)

    var errorDescription: String? {
        switch self {
        case .cannotEncodeUTF8:
            "Momentum couldn’t prepare the export. Try again."
        }
    }
}

struct CSVExportSnapshot: Sendable {
    let workouts: [WorkoutExportRow]
    let food: [FoodExportRow]
    let measurements: [MeasurementExportRow]
    let care: [CareExportRow]
    let adherence: [AdherenceExportRow]

    init(
        workouts: [WorkoutExportRow] = [],
        food: [FoodExportRow] = [],
        measurements: [MeasurementExportRow] = [],
        care: [CareExportRow] = [],
        adherence: [AdherenceExportRow] = []
    ) {
        self.workouts = workouts
        self.food = food
        self.measurements = measurements
        self.care = care
        self.adherence = adherence
    }

    @MainActor
    init(context: ModelContext) throws {
        let sessions = try context.fetch(FetchDescriptor<WorkoutSessionRecord>())
        let exerciseLogs = try context.fetch(FetchDescriptor<ExerciseLogRecord>())
        let setLogs = try context.fetch(FetchDescriptor<SetLogRecord>())
        let workoutEvents = try context.fetch(FetchDescriptor<WorkoutDayEventRecord>())
        let foodEntries = try context.fetch(FetchDescriptor<FoodEntryRecord>())
        let nutritionDays = try context.fetch(FetchDescriptor<NutritionDayRecord>())
        let measurementRecords = try context.fetch(FetchDescriptor<BodyMeasurementRecord>())
        let occurrences = try context.fetch(FetchDescriptor<CareOccurrenceRecord>())
        let taskCompletions = try context.fetch(FetchDescriptor<CareTaskCompletionRecord>())

        workouts = Self.makeWorkoutRows(
            sessions: sessions,
            exerciseLogs: exerciseLogs,
            setLogs: setLogs,
            events: workoutEvents
        )
        food = Self.makeFoodRows(entries: foodEntries, days: nutritionDays)
        measurements = measurementRecords
            .map(MeasurementExportRow.init)
            .sorted { ($0.domainDay, $0.measuredAt, $0.id) < ($1.domainDay, $1.measuredAt, $1.id) }
        care = Self.makeCareRows(occurrences: occurrences, tasks: taskCompletions)
        adherence = Self.makeAdherenceRows(
            sessions: sessions,
            workoutEvents: workoutEvents,
            nutritionDays: nutritionDays,
            careOccurrences: occurrences
        )
    }

    @MainActor
    private static func makeWorkoutRows(
        sessions: [WorkoutSessionRecord],
        exerciseLogs: [ExerciseLogRecord],
        setLogs: [SetLogRecord],
        events: [WorkoutDayEventRecord]
    ) -> [WorkoutExportRow] {
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
    }

    @MainActor
    private static func makeFoodRows(
        entries: [FoodEntryRecord],
        days: [NutritionDayRecord]
    ) -> [FoodExportRow] {
        let dayByDomainDay = Dictionary(
            days.sorted { $0.updatedAt < $1.updatedAt }.map { ($0.domainDay, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        var rows = entries.map { FoodExportRow(entry: $0, day: dayByDomainDay[$0.domainDay]) }
        let entryDays = Set(entries.map(\.domainDay))
        rows.append(contentsOf: days.filter { !entryDays.contains($0.domainDay) }.map {
            FoodExportRow(day: $0)
        })
        return rows.sorted { ($0.domainDay, $0.consumedAt ?? "", $0.entryID ?? "") < ($1.domainDay, $1.consumedAt ?? "", $1.entryID ?? "") }
    }

    @MainActor
    private static func makeCareRows(
        occurrences: [CareOccurrenceRecord],
        tasks: [CareTaskCompletionRecord]
    ) -> [CareExportRow] {
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
    }

    @MainActor
    private static func makeAdherenceRows(
        sessions: [WorkoutSessionRecord],
        workoutEvents: [WorkoutDayEventRecord],
        nutritionDays: [NutritionDayRecord],
        careOccurrences: [CareOccurrenceRecord]
    ) -> [AdherenceExportRow] {
        var days: [String: AdherenceAccumulator] = [:]

        for session in sessions where session.deletedAt == nil {
            let day = session.completionDomainDay ?? session.scheduledDomainDay
            days[day, default: .init()].add(
                category: "workout",
                completed: session.finishedAt != nil,
                sourceID: session.id
            )
        }
        for event in workoutEvents where event.deletedAt == nil {
            days[event.domainDay, default: .init()].add(
                category: "workout",
                completed: false,
                sourceID: event.id
            )
        }
        for day in nutritionDays {
            days[day.domainDay, default: .init()].add(
                category: "nutrition",
                completed: day.finalizedAt != nil,
                sourceID: day.id
            )
        }
        for occurrence in careOccurrences {
            days[occurrence.dueDomainDay, default: .init()].add(
                category: "care",
                completed: occurrence.statusRaw == "completed",
                sourceID: occurrence.id
            )
        }

        return days.map { day, value in
            AdherenceExportRow(
                domainDay: day,
                completedCount: value.completedCount,
                dueCount: value.dueCount,
                percentage: value.dueCount == 0
                    ? nil
                    : Double(value.completedCount) / Double(value.dueCount) * 100,
                categories: value.categories.sorted().joined(separator: ";"),
                sourceRecordIDs: value.sourceIDs.sorted().joined(separator: ";")
            )
        }
        .sorted { $0.domainDay < $1.domainDay }
    }
}

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

struct FoodExportRow: Sendable {
    let entryID: String?
    let nutritionDayID: String?
    let domainDay: String
    let consumedAt: String?
    let presetID: String?
    let nameSnapshot: String?
    let caloriesPerBaseServing: Double?
    let proteinPerBaseServing: Double?
    let servingMultiplier: Double?
    let totalCalories: Double?
    let totalProteinGrams: Double?
    let finalizedAt: String?
    let calorieDisplayTarget: Int?
    let calorieMinimum: Int?
    let calorieMaximum: Int?
    let proteinMinimum: Int?
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    @MainActor
    init(entry: FoodEntryRecord, day: NutritionDayRecord?) {
        entryID = CSVFormat.uuid(entry.id)
        nutritionDayID = day.map { CSVFormat.uuid($0.id) }
        domainDay = entry.domainDay
        consumedAt = CSVFormat.date(entry.consumedAt)
        presetID = entry.presetID.map(CSVFormat.uuid)
        nameSnapshot = entry.nameSnapshot
        caloriesPerBaseServing = entry.caloriesPerBaseServing
        proteinPerBaseServing = entry.proteinPerBaseServing
        servingMultiplier = entry.servingMultiplier
        totalCalories = entry.totalCalories
        totalProteinGrams = entry.totalProteinGrams
        finalizedAt = day?.finalizedAt.map(CSVFormat.date)
        calorieDisplayTarget = day?.calorieDisplayTargetSnapshot
        calorieMinimum = day?.calorieMinimumSnapshot
        calorieMaximum = day?.calorieMaximumSnapshot
        proteinMinimum = day?.proteinMinimumSnapshot
        createdAt = CSVFormat.date(entry.createdAt)
        updatedAt = CSVFormat.date(entry.updatedAt)
        deletedAt = entry.deletedAt.map(CSVFormat.date)
    }

    @MainActor
    init(day: NutritionDayRecord) {
        entryID = nil
        nutritionDayID = CSVFormat.uuid(day.id)
        domainDay = day.domainDay
        consumedAt = nil
        presetID = nil
        nameSnapshot = nil
        caloriesPerBaseServing = nil
        proteinPerBaseServing = nil
        servingMultiplier = nil
        totalCalories = nil
        totalProteinGrams = nil
        finalizedAt = day.finalizedAt.map(CSVFormat.date)
        calorieDisplayTarget = day.calorieDisplayTargetSnapshot
        calorieMinimum = day.calorieMinimumSnapshot
        calorieMaximum = day.calorieMaximumSnapshot
        proteinMinimum = day.proteinMinimumSnapshot
        createdAt = CSVFormat.date(day.createdAt)
        updatedAt = CSVFormat.date(day.updatedAt)
        deletedAt = nil
    }
}

struct MeasurementExportRow: Sendable {
    let id: String
    let kind: String
    let value: Double
    let measuredAt: String
    let domainDay: String
    let source: String
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    @MainActor
    init(_ record: BodyMeasurementRecord) {
        id = CSVFormat.uuid(record.id)
        kind = record.kindRaw
        value = record.value
        measuredAt = CSVFormat.date(record.measuredAt)
        domainDay = record.domainDay
        source = record.sourceRaw
        createdAt = CSVFormat.date(record.createdAt)
        updatedAt = CSVFormat.date(record.updatedAt)
        deletedAt = record.deletedAt.map(CSVFormat.date)
    }
}

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

struct AdherenceExportRow: Sendable {
    let domainDay: String
    let completedCount: Int
    let dueCount: Int
    let percentage: Double?
    let categories: String
    let sourceRecordIDs: String
}

struct CSVExportService {
    private let fileManager: FileManager
    private let baseDirectory: URL
    private let now: @Sendable () -> Date

    init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory ?? fileManager.temporaryDirectory
            .appending(path: "MomentumExports", directoryHint: .isDirectory)
        self.now = now
    }

    func export(_ snapshot: CSVExportSnapshot) throws -> [CSVExportFile] {
        try cleanupStaleExports()
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let directory = baseDirectory
            .appending(path: UUID().uuidString.lowercased(), directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)

        let documents: [(String, String)] = [
            ("workouts.csv", workoutsCSV(snapshot.workouts)),
            ("food.csv", foodCSV(snapshot.food)),
            ("measurements.csv", measurementsCSV(snapshot.measurements)),
            ("care.csv", careCSV(snapshot.care)),
            ("adherence.csv", adherenceCSV(snapshot.adherence))
        ]

        return try documents.map { name, contents in
            guard let data = contents.data(using: .utf8) else {
                throw CSVExportError.cannotEncodeUTF8(fileName: name)
            }
            let url = directory.appending(path: name)
            try data.write(to: url, options: .atomic)
            return CSVExportFile(name: name, url: url)
        }
    }

    func cleanupStaleExports(olderThan maximumAge: TimeInterval = 24 * 60 * 60) throws {
        guard fileManager.fileExists(atPath: baseDirectory.path()) else { return }
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey]
        for url in try fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) {
            let values = try url.resourceValues(forKeys: keys)
            let modifiedAt = values.contentModificationDate ?? .distantPast
            if now().timeIntervalSince(modifiedAt) > maximumAge {
                try fileManager.removeItem(at: url)
            }
        }
    }

    static func escape(_ value: String) -> String {
        let scalars = value.unicodeScalars
        guard scalars.contains(",") || scalars.contains("\"") || scalars.contains("\r") || scalars.contains("\n") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func workoutsCSV(_ rows: [WorkoutExportRow]) -> String {
        let header = ["record_type", "event_id", "event_kind", "session_id", "workout_template_id", "workout_name_snapshot", "focus_snapshot", "sequence_index_snapshot", "scheduled_domain_day", "completion_domain_day", "started_at", "finished_at", "started_early", "session_note", "exercise_log_id", "prescription_id", "exercise_name_snapshot", "exercise_order", "set_count_snapshot", "rep_minimum_snapshot", "rep_maximum_snapshot", "exercise_notes_snapshot", "exercise_status", "set_log_id", "set_number", "weight_kg", "repetitions", "rir", "set_status", "set_note", "created_at", "updated_at", "deleted_at"]
        return csv(header: header, rows: rows.map(workoutFields))
    }

    private func foodCSV(_ rows: [FoodExportRow]) -> String {
        let header = ["entry_id", "nutrition_day_id", "domain_day", "consumed_at", "preset_id", "name_snapshot", "calories_per_base_serving", "protein_per_base_serving", "serving_multiplier", "total_calories", "total_protein_grams", "finalized_at", "calorie_display_target_snapshot", "calorie_minimum_snapshot", "calorie_maximum_snapshot", "protein_minimum_snapshot", "created_at", "updated_at", "deleted_at"]
        return csv(header: header, rows: rows.map(foodFields))
    }

    private func workoutFields(_ row: WorkoutExportRow) -> [String] {
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

    private func foodFields(_ row: FoodExportRow) -> [String] {
        let values: [String?] = [
            row.entryID, row.nutritionDayID, row.domainDay, row.consumedAt, row.presetID, row.nameSnapshot,
            row.caloriesPerBaseServing.map(CSVFormat.decimal),
            row.proteinPerBaseServing.map(CSVFormat.decimal),
            row.servingMultiplier.map(CSVFormat.decimal), row.totalCalories.map(CSVFormat.decimal),
            row.totalProteinGrams.map(CSVFormat.decimal), row.finalizedAt,
            row.calorieDisplayTarget.map(String.init), row.calorieMinimum.map(String.init),
            row.calorieMaximum.map(String.init), row.proteinMinimum.map(String.init),
            row.createdAt, row.updatedAt, row.deletedAt
        ]
        return values.map { $0 ?? "" }
    }

    private func measurementsCSV(_ rows: [MeasurementExportRow]) -> String {
        csv(
            header: ["measurement_id", "kind", "value", "measured_at", "domain_day", "source", "created_at", "updated_at", "deleted_at"],
            rows: rows.map { row in
                [row.id, row.kind, CSVFormat.decimal(row.value), row.measuredAt, row.domainDay,
                 row.source, row.createdAt, row.updatedAt, row.deletedAt ?? ""]
            }
        )
    }

    private func careCSV(_ rows: [CareExportRow]) -> String {
        csv(
            header: ["occurrence_id", "routine_template_id", "routine_name_snapshot", "domain_day", "due_at", "occurrence_status", "occurrence_completed_at", "skipped_at", "rolled_from_domain_day", "task_completion_id", "task_template_id", "task_label_snapshot", "task_instruction_snapshot", "task_status", "selected_variant", "task_completed_at", "created_at", "updated_at"],
            rows: rows.map { row in
                [row.occurrenceID, row.routineTemplateID, row.routineName, row.domainDay, row.dueAt,
                 row.occurrenceStatus, row.occurrenceCompletedAt, row.skippedAt,
                 row.rolledFromDomainDay, row.taskCompletionID, row.taskTemplateID, row.taskLabel,
                 row.taskInstruction, row.taskStatus, row.selectedVariant, row.taskCompletedAt,
                 row.createdAt, row.updatedAt].map { $0 ?? "" }
            }
        )
    }

    private func adherenceCSV(_ rows: [AdherenceExportRow]) -> String {
        csv(
            header: ["domain_day", "completed_count", "due_count", "percentage", "categories", "source_record_ids"],
            rows: rows.map { row in
                [row.domainDay, String(row.completedCount), String(row.dueCount),
                 row.percentage.map(CSVFormat.decimal) ?? "", row.categories, row.sourceRecordIDs]
            }
        )
    }

    private func csv(header: [String], rows: [[String]]) -> String {
        ([header] + rows)
            .map { $0.map(Self.escape).joined(separator: ",") }
            .joined(separator: "\r\n") + "\r\n"
    }
}

private struct AdherenceAccumulator {
    var completedCount = 0
    var dueCount = 0
    var categories: Set<String> = []
    var sourceIDs: Set<String> = []

    mutating func add(category: String, completed: Bool, sourceID: UUID) {
        dueCount += 1
        if completed { completedCount += 1 }
        categories.insert(category)
        sourceIDs.insert(CSVFormat.uuid(sourceID))
    }
}

private enum CSVFormat {
    static func uuid(_ value: UUID) -> String {
        value.uuidString.lowercased()
    }

    static func date(_ value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: value)
    }

    static func decimal(_ value: Double) -> String {
        String(format: "%.15g", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
