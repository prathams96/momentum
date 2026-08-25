import Foundation
import MomentumCore
import SwiftData

extension HydrationModuleAdapter: ExportDefinitionProviding {
    func exportDefinitions() -> [ModuleExportDefinition] {
        [ModuleExportDefinition(
            moduleID: metadata.id,
            fileName: "hydration.csv",
            header: Self.header,
            rowsProvider: { context in
                let entries = try context.fetch(FetchDescriptor<HydrationEntryRecord>())
                return Self.makeRows(entries: entries)
            }
        )]
    }

    private static let header = [
        "id", "amount_ml", "consumed_at", "domain_day", "deleted_at", "created_at", "updated_at",
    ]

    @MainActor
    private static func makeRows(entries: [HydrationEntryRecord]) -> [[String]] {
        entries
            .sorted {
                ($0.domainDay, $0.consumedAt, $0.id.uuidString) < ($1.domainDay, $1.consumedAt, $1.id.uuidString)
            }
            .map { entry in
                [
                    CSVFormat.uuid(entry.id),
                    String(entry.amountML),
                    CSVFormat.date(entry.consumedAt),
                    entry.domainDay,
                    entry.deletedAt.map(CSVFormat.date) ?? "",
                    CSVFormat.date(entry.createdAt),
                    CSVFormat.date(entry.updatedAt),
                ]
            }
    }
}
