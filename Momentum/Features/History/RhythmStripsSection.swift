import MomentumCore
import SwiftData
import SwiftUI

/// One category's model behind a rhythm strip row. Registry-driven: a fifth
/// module adds a row, not a screen (pre-launch spec §3). Scoring folds the
/// module's own facts through its own adherence rule.
struct CategoryRhythmModel: Identifiable {
    let metadata: ModuleMetadata
    let category: HistoryCategory
    /// Score for one day, derived from the contributing module's fold rule.
    let score: (DomainDay) -> DailyAdherenceScore
    /// nil when the module has no streak semantics.
    let streak: Int?
    let pausedDays: Set<DomainDay>

    var id: ModuleID { metadata.id }

    func isPaused(_ day: DomainDay) -> Bool {
        pausedDays.contains(day)
    }

    func presentation(for day: DomainDay) -> RhythmCellPresentation {
        RhythmCellPresentation(score: score(day), isPaused: isPaused(day))
    }
}

/// Registry-driven rhythm strips: one compact row per enabled category with
/// the last 28 days as day cells and the Category Streak right-aligned.
/// Tapping a row opens that category's full 16-week heatmap drill-down.
struct RhythmStripsSection: View {
    let title: String?
    let settings: AppSettingsRecord?
    let currentDay: DomainDay
    let calendar: Calendar

    @Environment(\.modelContext) private var modelContext

    private var models: [CategoryRhythmModel] {
        let context = ModuleContext.make(in: modelContext, settings: settings, calendar: calendar)
        let engine = AdherenceEngine()
        return ModuleRegistry.standard
            .enabledModules(ModuleEnablementStore.enabledIDs(from: settings))
            .compactMap { $0 as? any HistoryContributing }
            .map { contributor in
                let facts = contributor.historyFacts(in: context)
                return CategoryRhythmModel(
                    metadata: contributor.metadata,
                    category: Self.category(for: contributor.metadata.id),
                    score: { day in
                        engine.dailyScore(activities: contributor.adherenceActivities(on: day, facts: facts))
                    },
                    streak: contributor.categoryStreak(asOf: currentDay, in: context),
                    pausedDays: ModuleEnablementLedger.pausedDays(
                        for: contributor.metadata.id,
                        through: currentDay,
                        calendar: calendar,
                        in: modelContext
                    )
                )
            }
    }

    private static func category(for id: ModuleID) -> HistoryCategory {
        switch id {
        case BuiltInModuleID.workout: .workouts
        case BuiltInModuleID.nutrition: .nutrition
        case BuiltInModuleID.care: .care
        case BuiltInModuleID.hydration: .hydration
        default: .measurements
        }
    }

    var body: some View {
        Section {
            ForEach(models) { model in
                NavigationLink {
                    CategoryRhythmDrillDownView(
                        model: model,
                        currentDay: currentDay,
                        calendar: calendar
                    )
                } label: {
                    CategoryRhythmStripRow(model: model, currentDay: currentDay, calendar: calendar)
                }
            }
        } header: {
            if let title {
                Text(title)
            }
        } footer: {
            Text("Recovery days add no obligation. Paused days never break a streak.")
        }
    }
}

/// One compact strip row: label, 28 day cells, streak count right-aligned.
struct CategoryRhythmStripRow: View {
    let model: CategoryRhythmModel
    let currentDay: DomainDay
    let calendar: Calendar

    private var days: [DomainDay] {
        HistoryProjection.heatmapDays(endingOn: currentDay, calendar: calendar, weekCount: 4)
    }

    private var accessibilitySummary: String {
        func scoredPercentage(_ presentation: RhythmCellPresentation) -> Double? {
            if case let .scored(percentage) = presentation { return percentage }
            return nil
        }

        var parts: [String] = []
        if let streak = model.streak {
            parts.append("\(streak) \(streak == 1 ? "day" : "days") streak")
        }
        let percentages = days.map { model.presentation(for: $0) }
        let complete = percentages.compactMap(scoredPercentage).count(where: { $0 >= 99.5 })
        let partial = percentages.compactMap(scoredPercentage).count(where: { $0 > 0 && $0 < 99.5 })
        let missed = percentages.compactMap(scoredPercentage).count(where: { $0 <= 0 })
        let noObligation = percentages.count(where: { $0 == .noObligation })
        let paused = percentages.count(where: { $0 == .paused })
        parts.append("Last 28 days: \(complete) complete, \(partial) partial, \(missed) missed, \(noObligation) without obligation, \(paused) paused, not broken.")
        return parts.joined(separator: ". ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Label(model.metadata.displayName, systemImage: model.metadata.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: MomentumSpacing.sm)
                if let streak = model.streak {
                    Text("\(streak)")
                        .font(.title3.weight(.semibold).monospacedDigit())
                    Text(streak == 1 ? "day" : "days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 2) {
                ForEach(days, id: \.self) { day in
                    RhythmDayCell(presentation: model.presentation(for: day), cornerRadius: 2)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.vertical, MomentumSpacing.xxs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.metadata.displayName). \(accessibilitySummary)")
        .accessibilityHint("Opens the full heatmap")
    }
}

/// The full 16-week heatmap for one category, reusing the shared component.
struct CategoryRhythmDrillDownView: View {
    let model: CategoryRhythmModel
    let currentDay: DomainDay
    let calendar: Calendar

    @State private var page = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MomentumSpacing.lg) {
                if let streak = model.streak {
                    VStack(alignment: .leading, spacing: MomentumSpacing.xxs) {
                        Text("\(streak)")
                            .font(.largeTitle.weight(.bold).monospacedDigit())
                            .foregroundStyle(MomentumTheme.pulseDeep)
                        Text(streak == 1 ? "day streak" : "day streak")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }

                HistoryHeatmapView(
                    currentDay: currentDay,
                    page: $page,
                    calendar: calendar,
                    pausedDays: model.pausedDays
                ) { day in
                    model.score(day)
                }
            }
            .padding(.horizontal, MomentumSpacing.md)
            .padding(.top, MomentumSpacing.xs)
        }
        .navigationTitle(model.metadata.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemBackground))
    }
}
