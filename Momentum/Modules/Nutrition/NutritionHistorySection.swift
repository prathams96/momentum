import MomentumCore
import SwiftData
import SwiftUI

// MARK: - History contribution

extension NutritionModuleAdapter: HistoryContributing {
    func historyFacts(in context: ModuleContext) -> [HistoryAdherenceFact] {
        let modelContext = context.modelContext
        let nutritionDays = (try? modelContext.fetch(FetchDescriptor<NutritionDayRecord>())) ?? []
        return HistoryProjection.facts(
            sessions: [],
            workoutEvents: [],
            nutritionDays: nutritionDays,
            careOccurrences: []
        )
    }

    func historyDaySections(for day: DomainDay, in context: ModuleContext) -> [AnyView] {
        [AnyView(NutritionHistoryDaySection(day: day))]
    }

    func categoryStreak(asOf day: DomainDay, in context: ModuleContext) -> Int? {
        ModuleHistoryMath.categoryStreak(
            facts: historyFacts(in: context),
            category: .nutrition,
            through: day,
            calendar: context.calendar,
            pausedDays: ModuleEnablementLedger.pausedDays(
                for: metadata.id,
                through: day,
                calendar: context.calendar,
                in: context.modelContext
            )
        )
    }

    func adherenceActivities(on day: DomainDay, facts: [HistoryAdherenceFact]) -> [DueAdherenceActivity] {
        let matching = facts.filter { $0.day == day && $0.category == .nutrition }
        guard !matching.isEmpty else { return [] }
        return [DueAdherenceActivity(
            kind: .nutritionFinalization,
            isCompleted: matching.contains(where: \.isCompleted)
        )]
    }
}

/// The nutrition module's contribution to one recorded history day.
struct NutritionHistoryDaySection: View {
    let day: DomainDay

    @Query private var nutritionDays: [NutritionDayRecord]
    @Query private var foodEntries: [FoodEntryRecord]
    @Environment(\.historyDayActions) private var actions

    private var dayKey: String { PersistedDomainDay.encode(day) }

    private var dayFoods: [FoodEntryRecord] {
        foodEntries
            .filter { $0.deletedAt == nil && $0.domainDay == dayKey }
            .sorted { $0.consumedAt < $1.consumedAt }
    }

    var body: some View {
        Section("Nutrition") {
            if let record = nutritionDays.first(where: { $0.domainDay == dayKey }) {
                Label(
                    record.finalizedAt == nil ? "Logging not finalized" : "Logging finalized",
                    systemImage: record.finalizedAt == nil ? "circle" : "checkmark.circle.fill"
                )
                .foregroundStyle(record.finalizedAt == nil ? .secondary : MomentumTheme.success)

                let calorieTotal = dayFoods.reduce(0) { $0 + $1.totalCalories }
                let proteinTotal = dayFoods.reduce(0) { $0 + $1.totalProteinGrams }
                LabeledContent(
                    "Day total",
                    value: "\(calorieTotal.formatted(.number.precision(.fractionLength(0)))) kcal · \(proteinTotal.formatted(.number.precision(.fractionLength(0...1)))) g"
                )
                LabeledContent(
                    "Target",
                    value: "\(record.calorieMinimumSnapshot)–\(record.calorieMaximumSnapshot) kcal · \(record.proteinMinimumSnapshot) g protein"
                )

                Button(record.finalizedAt == nil ? "Finalize logging" : "Reopen logging") {
                    actions.toggleNutritionFinalization(day)
                }
            } else if dayFoods.isEmpty {
                Text("No nutrition facts")
                    .foregroundStyle(.secondary)
            } else {
                Button("Finalize logging") {
                    actions.toggleNutritionFinalization(day)
                }
            }

            ForEach(dayFoods) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.nameSnapshot)
                        Text(entry.consumedAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(entry.totalCalories.formatted(.number.precision(.fractionLength(0)))) kcal")
                        Text("\(entry.totalProteinGrams.formatted(.number.precision(.fractionLength(0...1)))) g protein")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .swipeActions(edge: .leading) {
                    Button("Edit") { actions.editFood(entry) }
                        .tint(MomentumTheme.pulse)
                    Button("Move") { actions.backdateFood(entry) }
                        .tint(MomentumTheme.dataCyan)
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", role: .destructive) {
                        actions.requestFoodDeletion(entry)
                    }
                }
                .contextMenu {
                    Button("Edit food") { actions.editFood(entry) }
                    Button("Move to another day") { actions.backdateFood(entry) }
                    Button("Delete food", role: .destructive) {
                        actions.requestFoodDeletion(entry)
                    }
                }
            }
        }
    }
}
