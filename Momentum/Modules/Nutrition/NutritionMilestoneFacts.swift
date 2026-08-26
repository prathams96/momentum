import MomentumCore
import SwiftData

// MARK: - Milestone contribution

extension NutritionModuleAdapter: MilestoneContributing {
    func milestoneFacts(in context: ModuleContext) -> [MilestoneFact] {
        let modelContext = context.modelContext
        let days = (try? modelContext.fetch(FetchDescriptor<NutritionDayRecord>())) ?? []
        let entriesByDay = Dictionary(grouping:
            ((try? modelContext.fetch(FetchDescriptor<FoodEntryRecord>())) ?? [])
                .filter { $0.deletedAt == nil },
            by: \.domainDay
        )

        return days.compactMap { record in
            guard let day = PersistedDomainDay.decode(record.domainDay),
                  let finalizedAt = record.finalizedAt else { return nil }
            let totals = (entriesByDay[record.domainDay] ?? []).reduce(
                into: (calories: 0.0, protein: 0.0)
            ) {
                $0.calories += $1.totalCalories
                $0.protein += $1.totalProteinGrams
            }
            return .nutritionDayFinalized(
                day: day,
                finalizedAt: finalizedAt,
                calorieMinimum: record.calorieMinimumSnapshot,
                calorieMaximum: record.calorieMaximumSnapshot,
                proteinMinimum: record.proteinMinimumSnapshot,
                calories: totals.calories,
                proteinGrams: totals.protein
            )
        }
    }
}
