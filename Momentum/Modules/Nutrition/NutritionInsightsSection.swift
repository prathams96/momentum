import Charts
import MomentumCore
import SwiftData
import SwiftUI

/// The nutrition module's contribution to the Progress surface: daily
/// calorie and protein trends against the effective target for each
/// Domain Day.
struct NutritionInsightsSection: View {
    @Query private var foodEntries: [FoodEntryRecord]
    @Query private var nutritionDays: [NutritionDayRecord]
    @Query private var nutritionTargets: [NutritionTargetRecord]

    private var projection: NutritionInsightsProjection {
        NutritionInsightsProjection.make(
            entries: foodEntries,
            days: nutritionDays,
            targets: nutritionTargets,
            calendar: .autoupdatingCurrent
        )
    }

    var body: some View {
        Section {
            if projection.nutritionPoints.isEmpty {
                Text("Log food to see calorie and protein trends.").foregroundStyle(.secondary)
            } else {
                Chart(projection.nutritionPoints) { point in
                    BarMark(x: .value("Date", point.date), y: .value("Calories", point.calories))
                        .foregroundStyle(MomentumTheme.pulse.opacity(0.55))
                    LineMark(x: .value("Date", point.date), y: .value("Minimum", point.calorieMinimum))
                        .foregroundStyle(.secondary)
                    LineMark(x: .value("Date", point.date), y: .value("Maximum", point.calorieMaximum))
                        .foregroundStyle(.secondary)
                }
                .frame(height: 190)
                .accessibilityLabel("Daily calories and target range")
                .accessibilityValue(projection.nutritionSummary)

                Chart(projection.nutritionPoints) { point in
                    BarMark(x: .value("Date", point.date), y: .value("Protein", point.protein))
                        .foregroundStyle(MomentumTheme.pulseDeep.opacity(0.7))
                    LineMark(x: .value("Date", point.date), y: .value("Minimum", point.proteinMinimum))
                        .foregroundStyle(.secondary)
                }
                .frame(height: 150)
                .accessibilityLabel("Daily protein and minimum target")
                .accessibilityValue(projection.proteinSummary)
            }
        } header: {
            Text("Nutrition")
        } footer: {
            Text("Bars are daily totals. Lines show the effective target for each Domain Day.")
        }
    }
}

private struct NutritionProgressPoint: Identifiable {
    var id: String { domainDay }
    let domainDay: String
    let date: Date
    let calories: Double
    let protein: Double
    let calorieMinimum: Double
    let calorieMaximum: Double
    let proteinMinimum: Double
}

@MainActor
private struct NutritionInsightsProjection {
    let nutritionPoints: [NutritionProgressPoint]

    var nutritionSummary: String {
        guard let point = nutritionPoints.last else { return "No nutrition data." }
        return "Latest day: \(DecimalFormatter.whole(point.calories)) calories; target range \(DecimalFormatter.whole(point.calorieMinimum)) to \(DecimalFormatter.whole(point.calorieMaximum))."
    }

    var proteinSummary: String {
        guard let point = nutritionPoints.last else { return "No protein data." }
        return "Latest day: \(DecimalFormatter.onePlace(point.protein)) grams; minimum \(DecimalFormatter.onePlace(point.proteinMinimum)) grams."
    }

    static func make(
        entries: [FoodEntryRecord],
        days: [NutritionDayRecord],
        targets: [NutritionTargetRecord],
        calendar: Calendar
    ) -> NutritionInsightsProjection {
        NutritionInsightsProjection(nutritionPoints: nutritionProjection(entries: entries, days: days, targets: targets, calendar: calendar))
    }

    private static func nutritionProjection(
        entries: [FoodEntryRecord],
        days: [NutritionDayRecord],
        targets: [NutritionTargetRecord],
        calendar: Calendar
    ) -> [NutritionProgressPoint] {
        let grouped = Dictionary(grouping: entries.filter { $0.deletedAt == nil }, by: \.domainDay)
        return grouped.compactMap { dayValue, values in
            guard let day = PersistedDomainDay.decode(dayValue),
                  let date = PersistedDomainDay.date(for: day, calendar: calendar) else { return nil }
            let calories = values.reduce(0) { $0 + $1.totalCalories }
            let protein = values.reduce(0) { $0 + $1.totalProteinGrams }
            let finalized = days.filter { $0.domainDay == dayValue }.max {
                ($0.updatedAt, $0.id.uuidString) < ($1.updatedAt, $1.id.uuidString)
            }
            let target = NutritionPlanService.target(for: day, in: targets)
            return NutritionProgressPoint(
                domainDay: dayValue,
                date: date,
                calories: calories,
                protein: protein,
                calorieMinimum: Double(finalized?.calorieMinimumSnapshot ?? target?.calorieMinimum ?? 0),
                calorieMaximum: Double(finalized?.calorieMaximumSnapshot ?? target?.calorieMaximum ?? 0),
                proteinMinimum: Double(finalized?.proteinMinimumSnapshot ?? target?.proteinMinimumGrams ?? 0)
            )
        }.sorted { $0.domainDay < $1.domainDay }
    }
}

// MARK: - Module conformance

extension NutritionModuleAdapter: InsightsContributing {
    func insightsSection(in context: ModuleContext) -> AnyView? {
        AnyView(NutritionInsightsSection())
    }
}
