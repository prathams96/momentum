import Foundation
import MomentumCore
import SwiftData

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

extension NutritionModuleAdapter: ExportDefinitionProviding {
    func exportDefinitions() -> [ModuleExportDefinition] {
        [ModuleExportDefinition(
            moduleID: metadata.id,
            fileName: "food.csv",
            header: Self.header,
            rowsProvider: { context in
                let entries = try context.fetch(FetchDescriptor<FoodEntryRecord>())
                let days = try context.fetch(FetchDescriptor<NutritionDayRecord>())
                return Self.makeRows(entries: entries, days: days)
            }
        )]
    }

    private static let header = ["entry_id", "nutrition_day_id", "domain_day", "consumed_at", "preset_id", "name_snapshot", "calories_per_base_serving", "protein_per_base_serving", "serving_multiplier", "total_calories", "total_protein_grams", "finalized_at", "calorie_display_target_snapshot", "calorie_minimum_snapshot", "calorie_maximum_snapshot", "protein_minimum_snapshot", "created_at", "updated_at", "deleted_at"]

    @MainActor
    private static func makeRows(
        entries: [FoodEntryRecord],
        days: [NutritionDayRecord]
    ) -> [[String]] {
        let dayByDomainDay = Dictionary(
            days.sorted { $0.updatedAt < $1.updatedAt }.map { ($0.domainDay, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        var rows = entries.map { FoodExportRow(entry: $0, day: dayByDomainDay[$0.domainDay]) }
        let entryDays = Set(entries.map(\.domainDay))
        rows.append(contentsOf: days.filter { !entryDays.contains($0.domainDay) }.map {
            FoodExportRow(day: $0)
        })
        return rows.sorted {
            ($0.domainDay, $0.consumedAt ?? "", $0.entryID ?? "") < ($1.domainDay, $1.consumedAt ?? "", $1.entryID ?? "")
        }
        .map(fields)
    }

    private static func fields(_ row: FoodExportRow) -> [String] {
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
}
