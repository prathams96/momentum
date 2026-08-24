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

struct EvaluatedModuleExportDocument: Sendable {
    let fileName: String
    let header: [String]
    let rows: [[String]]
}

/// Snapshot for one export run. Module-owned documents (workouts, food, care)
/// are evaluated here — on the main actor, where the model context lives — by
/// asking enabled modules for their export definitions. Core retains the
/// measurements file (cut feature, retained data) and the cross-module
/// adherence projection.
struct CSVExportSnapshot: Sendable {
    let moduleDocuments: [EvaluatedModuleExportDocument]
    let measurements: [MeasurementExportRow]
    let adherence: [AdherenceExportRow]

    @MainActor
    init(
        context: ModelContext,
        registry: ModuleRegistry = .standard
    ) throws {
        let settings = AppSettingsRecord.canonical(
            in: try context.fetch(FetchDescriptor<AppSettingsRecord>())
        )
        let enabled = ModuleEnablementStore.enabledIDs(from: settings)
        let definitions = registry.enabledModules(enabled).flatMap { module in
            (module as? any ExportDefinitionProviding)?.exportDefinitions() ?? []
        }
        moduleDocuments = definitions.map { definition in
            EvaluatedModuleExportDocument(
                fileName: definition.fileName,
                header: definition.header,
                rows: (try? definition.rowsProvider(context)) ?? []
            )
        }

        let sessions = try context.fetch(FetchDescriptor<WorkoutSessionRecord>())
        let workoutEvents = try context.fetch(FetchDescriptor<WorkoutDayEventRecord>())
        let nutritionDays = try context.fetch(FetchDescriptor<NutritionDayRecord>())
        let occurrences = try context.fetch(FetchDescriptor<CareOccurrenceRecord>())
        let measurementRecords = try context.fetch(FetchDescriptor<BodyMeasurementRecord>())

        measurements = measurementRecords
            .map(MeasurementExportRow.init)
            .sorted { ($0.domainDay, $0.measuredAt, $0.id) < ($1.domainDay, $1.measuredAt, $1.id) }
        adherence = Self.makeAdherenceRows(
            sessions: sessions,
            workoutEvents: workoutEvents,
            nutritionDays: nutritionDays,
            careOccurrences: occurrences
        )
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

    /// Frozen historical file order for migrated modules plus Core-owned
    /// files. Output order must stay byte-compatible with the pre-modular
    /// exporter, so assembled documents are sorted into this sequence.
    private static let frozenFileOrder = [
        "workouts.csv",
        "food.csv",
        "measurements.csv",
        "care.csv",
        "adherence.csv",
    ]

    func export(_ snapshot: CSVExportSnapshot) throws -> [CSVExportFile] {
        try cleanupStaleExports()
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let directory = baseDirectory
            .appending(path: UUID().uuidString.lowercased(), directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)

        var rendered: [(name: String, contents: String)] = snapshot.moduleDocuments.map {
            ($0.fileName, csv(header: $0.header, rows: $0.rows))
        }
        rendered.append(("measurements.csv", measurementsCSV(snapshot.measurements)))
        rendered.append(("adherence.csv", adherenceCSV(snapshot.adherence)))

        let documents = rendered.enumerated().sorted { lhs, rhs in
            let lhsOrder = Self.frozenFileOrder.firstIndex(of: lhs.element.name) ?? Int.max
            let rhsOrder = Self.frozenFileOrder.firstIndex(of: rhs.element.name) ?? Int.max
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            return lhs.offset < rhs.offset
        }.map(\.element)

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

    private func measurementsCSV(_ rows: [MeasurementExportRow]) -> String {
        csv(
            header: ["measurement_id", "kind", "value", "measured_at", "domain_day", "source", "created_at", "updated_at", "deleted_at"],
            rows: rows.map { row in
                [row.id, row.kind, CSVFormat.decimal(row.value), row.measuredAt, row.domainDay,
                 row.source, row.createdAt, row.updatedAt, row.deletedAt ?? ""]
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

enum CSVFormat {
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
