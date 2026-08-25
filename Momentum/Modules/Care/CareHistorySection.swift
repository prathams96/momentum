import MomentumCore
import SwiftData
import SwiftUI

// MARK: - History contribution

extension CareModuleAdapter: HistoryContributing {
    func historyFacts(in context: ModuleContext) -> [HistoryAdherenceFact] {
        let modelContext = context.modelContext
        let careOccurrences = (try? modelContext.fetch(FetchDescriptor<CareOccurrenceRecord>())) ?? []
        return HistoryProjection.facts(
            sessions: [],
            workoutEvents: [],
            nutritionDays: [],
            careOccurrences: careOccurrences
        )
    }

    func historyDaySections(for day: DomainDay, in context: ModuleContext) -> [AnyView] {
        [AnyView(CareHistoryDaySection(day: day))]
    }

    func categoryStreak(asOf day: DomainDay, in context: ModuleContext) -> Int? {
        ModuleHistoryMath.categoryStreak(
            facts: historyFacts(in: context),
            category: .care,
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
        // Each due Care Routine counts as its own due activity (CONTEXT.md).
        facts
            .filter { $0.day == day && $0.category == .care }
            .map { DueAdherenceActivity(kind: .categoryDue, isCompleted: $0.isCompleted) }
    }
}

/// The care module's contribution to one recorded history day.
struct CareHistoryDaySection: View {
    let day: DomainDay

    @Query private var careOccurrences: [CareOccurrenceRecord]
    @Environment(\.historyDayActions) private var actions

    private var dayKey: String { PersistedDomainDay.encode(day) }

    private var dayCare: [CareOccurrenceRecord] {
        careOccurrences
            .filter { $0.dueDomainDay == dayKey && $0.statusRaw != "repairedDuplicate" }
            .sorted { $0.dueAt < $1.dueAt }
    }

    var body: some View {
        Section("Personal care") {
            if dayCare.isEmpty {
                Text("No personal care routines due")
                    .foregroundStyle(.secondary)
            }
            ForEach(dayCare) { occurrence in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(occurrence.routineNameSnapshot)
                        if occurrence.routineRoleRaw == "postWorkout" {
                            Text("Post-workout care")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(occurrence.statusRaw.capitalized)
                        .font(.subheadline)
                        .foregroundStyle(
                            occurrence.statusRaw == "completed" ? MomentumTheme.success : .secondary
                        )
                    if occurrence.statusRaw == "completed" {
                        Button("Undo") {
                            actions.requestCareCompletionUndo(occurrence)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Undo \(occurrence.routineNameSnapshot) completion")
                    }
                }
                .contextMenu {
                    if occurrence.statusRaw == "completed" {
                        Button("Undo completion") {
                            actions.requestCareCompletionUndo(occurrence)
                        }
                    }
                }
            }
        }
    }
}
