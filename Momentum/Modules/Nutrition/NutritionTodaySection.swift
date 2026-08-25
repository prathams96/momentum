import MomentumCore
import SwiftData
import SwiftUI

private enum FoodEntryDestination: Identifiable {
    case new
    case edit(UUID)

    var id: String {
        switch self {
        case .new: "new"
        case let .edit(id): "edit-\(id.uuidString)"
        }
    }

    var existingEntryID: UUID? {
        if case let .edit(id) = self { return id }
        return nil
    }
}

/// The nutrition module's contribution to the Today surface: totals, targets,
/// food entries, and day finalization.
struct NutritionTodaySection: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettingsRecord]
    @Query private var foodEntries: [FoodEntryRecord]
    @Query private var nutritionDays: [NutritionDayRecord]
    @Query private var nutritionTargets: [NutritionTargetRecord]

    @State private var foodDestination: FoodEntryDestination?
    @State private var nutritionError: String?

    private let calendar = Calendar.autoupdatingCurrent

    private var currentDomainDay: DomainDay {
        ScheduleProjection.currentDomainDay(settings: settings, now: .now, calendar: calendar)
    }

    private var activeFoodEntries: [FoodEntryRecord] {
        let day = PersistedDomainDay.encode(currentDomainDay)
        return foodEntries
            .filter { $0.domainDay == day && $0.deletedAt == nil }
            .sorted { ($0.consumedAt, $0.id.uuidString) < ($1.consumedAt, $1.id.uuidString) }
    }

    private var nutritionDay: NutritionDayRecord? {
        NutritionDayService.day(for: currentDomainDay, in: nutritionDays)
    }

    private var nutritionTarget: NutritionTargetRecord? {
        NutritionDayService.target(for: currentDomainDay, targets: nutritionTargets)
    }

    private var nutritionTotals: NutritionTotals {
        NutritionCalculator().dayTotals(entries: activeFoodEntries.map {
            NutritionTotals(calories: Decimal(string: String($0.totalCalories)) ?? 0, proteinGrams: Decimal(string: String($0.totalProteinGrams)) ?? 0)
        })
    }

    var body: some View {
        nutritionContent
            .sheet(item: $foodDestination) { destination in
                FoodEntrySheet(
                    domainDay: PersistedDomainDay.encode(currentDomainDay),
                    existingEntryID: destination.existingEntryID
                )
            }
            .alert("Couldn’t update nutrition", isPresented: Binding(
                get: { nutritionError != nil },
                set: { if !$0 { nutritionError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(nutritionError ?? "Your food entries are still safe.")
            }
    }

    private var nutritionContent: some View {
        let target = nutritionTarget
        let evaluation = target.flatMap { target in
            try? NutritionCalculator().evaluate(
                totals: nutritionTotals,
                against: NutritionTargetRange(
                    calorieMinimum: Decimal(target.calorieMinimum),
                    calorieMaximum: Decimal(target.calorieMaximum),
                    proteinMinimum: Decimal(target.proteinMinimumGrams)
                )
            )
        }

        return VStack(alignment: .leading, spacing: MomentumSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Nutrition")
                    .font(.title3.bold())
                Spacer()
                Button("Log food", systemImage: "plus") { openFoodEntry(nil) }
                    .buttonStyle(.bordered)
                    .tint(MomentumTheme.pulse)
                    .frame(minHeight: 44)
            }

            VStack(alignment: .leading, spacing: MomentumSpacing.md) {
                NutritionGoalRow(
                    title: "Calories",
                    value: "\(DecimalFormatter.whole(nutritionTotals.calories)) kcal",
                    target: target.map { "\($0.calorieMinimum)–\($0.calorieMaximum) kcal" } ?? "Set a target in Plans",
                    visualization: .range(
                        current: NSDecimalNumber(decimal: nutritionTotals.calories).doubleValue,
                        minimum: Double(target?.calorieMinimum ?? 0),
                        maximum: Double(target?.calorieMaximum ?? 0)
                    ),
                    tint: MomentumTheme.success
                )

                NutritionGoalRow(
                    title: "Protein",
                    value: "\(DecimalFormatter.onePlace(nutritionTotals.proteinGrams)) g",
                    target: target.map { "\($0.proteinMinimumGrams) g minimum" } ?? "Set a target in Plans",
                    visualization: .threshold(
                        current: NSDecimalNumber(decimal: nutritionTotals.proteinGrams).doubleValue,
                        minimum: Double(target?.proteinMinimumGrams ?? 0)
                    ),
                    tint: MomentumTheme.dataCyan
                )

                if let evaluation {
                    Label(
                        evaluation.meetsTarget ? "Inside today’s targets" : "Keep logging to see the full picture",
                        systemImage: evaluation.meetsTarget ? "checkmark.circle.fill" : "circle.dashed"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(evaluation.meetsTarget ? MomentumTheme.success : .secondary)
                }
            }
            .padding(MomentumSpacing.md)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if activeFoodEntries.isEmpty {
                Text("Nothing logged yet. Start with the food you actually ate.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(activeFoodEntries) { entry in
                    HStack {
                        Button { openFoodEntry(entry.id) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.nameSnapshot).font(.headline)
                                Text("\(DecimalFormatter.whole(entry.totalCalories)) kcal · \(DecimalFormatter.onePlace(entry.totalProteinGrams)) g protein")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(entry.servingMultiplier.formatted(.number.precision(.fractionLength(0...2))))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button("Edit", systemImage: "pencil") { openFoodEntry(entry.id) }
                            Button("Duplicate", systemImage: "plus.square.on.square") { duplicateFoodEntry(entry) }
                            Button("Delete", systemImage: "trash", role: .destructive) { deleteFoodEntry(entry) }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Actions for \(entry.nameSnapshot)")
                    }
                }
            }

            Button(
                nutritionDay?.finalizedAt == nil ? "Finish logging today" : "Reopen nutrition",
                systemImage: nutritionDay?.finalizedAt == nil ? "checkmark" : "arrow.uturn.backward"
            ) {
                toggleNutritionFinalization()
            }
            .buttonStyle(.bordered)
        }
    }

    private func openFoodEntry(_ id: UUID?) {
        foodDestination = id.map(FoodEntryDestination.edit) ?? .new
    }

    private func duplicateFoodEntry(_ entry: FoodEntryRecord) {
        let duplicate = FoodEntryRecord(
            domainDay: entry.domainDay,
            consumedAt: .now,
            presetID: entry.presetID,
            nameSnapshot: entry.nameSnapshot,
            caloriesPerBaseServing: entry.caloriesPerBaseServing,
            proteinPerBaseServing: entry.proteinPerBaseServing,
            servingMultiplier: entry.servingMultiplier,
            totalCalories: entry.totalCalories,
            totalProteinGrams: entry.totalProteinGrams
        )
        modelContext.insert(duplicate)
        do {
            try modelContext.save()
            refreshReconciledState()
        }
        catch { nutritionError = "The duplicate was not saved. Try again." }
    }

    private func deleteFoodEntry(_ entry: FoodEntryRecord) {
        entry.deletedAt = .now
        entry.updatedAt = .now
        do {
            try modelContext.save()
            refreshReconciledState()
        }
        catch { nutritionError = "The food entry was kept. Try again." }
    }

    private func toggleNutritionFinalization() {
        do {
            if nutritionDay?.finalizedAt == nil {
                try NutritionDayService.finalize(
                    domainDay: currentDomainDay,
                    target: nutritionTarget,
                    existing: nutritionDay,
                    context: modelContext
                )
            } else {
                try NutritionDayService.reopen(existing: nutritionDay, context: modelContext)
            }
            refreshReconciledState()
        } catch {
            nutritionError = "Your nutrition status was not changed. Try again."
        }
    }

    private func refreshReconciledState() {
        Task {
            do { try await DailyReconciler.reconcileAndNotify(in: modelContext) }
            catch { nutritionError = "Today’s reminders could not be refreshed. Try again in a moment." }
        }
    }
}

private enum NutritionGoalVisualization {
    case range(current: Double, minimum: Double, maximum: Double)
    case threshold(current: Double, minimum: Double)

    var current: Double {
        switch self {
        case let .range(current, _, _), let .threshold(current, _): current
        }
    }

    var scaleMaximum: Double {
        switch self {
        case let .range(current, _, maximum): max(current, maximum * 1.08, 1)
        case let .threshold(current, minimum): max(current, minimum * 1.25, 1)
        }
    }

    var highlightedRange: ClosedRange<Double> {
        switch self {
        case let .range(_, minimum, maximum): minimum...max(minimum, maximum)
        case let .threshold(_, minimum): 0...minimum
        }
    }
}

private struct NutritionGoalRow: View {
    let title: String
    let value: String
    let target: String
    let visualization: NutritionGoalVisualization
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: MomentumSpacing.md)
                Text(value)
                    .font(.headline.monospacedDigit())
            }

            NutritionGoalTrack(visualization: visualization, tint: tint)

            Text(target)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(value), target \(target)")
    }
}

private struct NutritionGoalTrack: View {
    let visualization: NutritionGoalVisualization
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let maximum = visualization.scaleMaximum
            let range = visualization.highlightedRange
            let start = min(max(range.lowerBound / maximum, 0), 1) * width
            let end = min(max(range.upperBound / maximum, 0), 1) * width
            let current = min(max(visualization.current / maximum, 0), 1) * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.16))
                    .frame(height: 6)

                Capsule()
                    .fill(tint)
                    .frame(width: max(end - start, 3), height: 6)
                    .offset(x: start)

                Circle()
                    .fill(Color.primary)
                    .frame(width: 10, height: 10)
                    .offset(x: min(max(current - 5, 0), max(width - 10, 0)))
            }
            .frame(height: 10)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.22),
                value: visualization.current
            )
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

// MARK: - Today contribution

extension NutritionModuleAdapter: TodayContributing {
    func todayContribution(in context: ModuleContext) -> TodayContribution? {
        let modelContext = context.modelContext
        let foodEntries = (try? modelContext.fetch(FetchDescriptor<FoodEntryRecord>())) ?? []
        let nutritionDays = (try? modelContext.fetch(FetchDescriptor<NutritionDayRecord>())) ?? []
        let nutritionTargets = (try? modelContext.fetch(FetchDescriptor<NutritionTargetRecord>())) ?? []

        guard let day = NutritionDayService.day(for: context.currentDomainDay, in: nutritionDays) else {
            return TodayContribution(metadata: metadata, state: .optional, accessibilitySummary: "Nutrition. Nothing logged yet.")
        }

        let encodedDay = PersistedDomainDay.encode(context.currentDomainDay)
        let calories = foodEntries
            .filter { $0.domainDay == encodedDay && $0.deletedAt == nil }
            .compactMap { Decimal(string: String($0.totalCalories)) }
            .reduce(0, +)
        let goal = NutritionDayService.target(for: context.currentDomainDay, targets: nutritionTargets)?.calorieMaximum ?? 0

        return TodayContribution(
            metadata: metadata,
            state: day.finalizedAt != nil ? .completed : .ongoing,
            accessibilitySummary: "Nutrition. \(DecimalFormatter.whole(calories)) of \(goal) calories logged."
        )
    }

    func todaySection(in context: ModuleContext) -> AnyView? {
        AnyView(NutritionTodaySection())
    }
}
