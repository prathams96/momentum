import MomentumCore
import SwiftData
import SwiftUI

// MARK: - History contribution

extension WorkoutModuleAdapter: HistoryContributing {
    func historyFacts(in context: ModuleContext) -> [HistoryAdherenceFact] {
        let modelContext = context.modelContext
        let sessions = (try? modelContext.fetch(FetchDescriptor<WorkoutSessionRecord>())) ?? []
        let events = (try? modelContext.fetch(FetchDescriptor<WorkoutDayEventRecord>())) ?? []
        return HistoryProjection.facts(
            sessions: sessions,
            workoutEvents: events,
            nutritionDays: [],
            careOccurrences: []
        )
    }

    func historyDaySections(for day: DomainDay, in context: ModuleContext) -> [AnyView] {
        [AnyView(WorkoutHistoryDaySection(day: day))]
    }

    func categoryStreak(asOf day: DomainDay, in context: ModuleContext) -> Int? {
        ModuleHistoryMath.categoryStreak(
            facts: historyFacts(in: context),
            category: .workouts,
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
        let matching = facts.filter { $0.day == day && $0.category == .workouts }
        guard !matching.isEmpty else { return [] }
        return [DueAdherenceActivity(
            kind: .workout,
            isCompleted: matching.contains(where: \.isCompleted)
        )]
    }
}

/// The workout module's contribution to one recorded history day.
struct WorkoutHistoryDaySection: View {
    let day: DomainDay

    @Query private var sessions: [WorkoutSessionRecord]
    @Query private var workoutEvents: [WorkoutDayEventRecord]
    @Environment(\.historyDayActions) private var actions

    private var dayKey: String { PersistedDomainDay.encode(day) }

    private var daySessions: [WorkoutSessionRecord] {
        sessions
            .filter {
                $0.deletedAt == nil
                    && ($0.completionDomainDay ?? $0.scheduledDomainDay) == dayKey
            }
            .sorted { ($0.finishedAt ?? $0.startedAt) < ($1.finishedAt ?? $1.startedAt) }
    }

    private var dayEvents: [WorkoutDayEventRecord] {
        workoutEvents.filter { $0.deletedAt == nil && $0.domainDay == dayKey }
    }

    var body: some View {
        Section("Workout") {
            if daySessions.isEmpty && dayEvents.isEmpty {
                Text("No workout fact")
                    .foregroundStyle(.secondary)
            }
            ForEach(daySessions) { session in
                VStack(alignment: .leading, spacing: MomentumSpacing.xxs) {
                    Text(session.workoutNameSnapshot)
                        .font(.headline)
                    if let finishedAt = session.finishedAt {
                        Text("Finished \(finishedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("In progress")
                            .font(.caption)
                            .foregroundStyle(MomentumTheme.warning)
                    }
                    if !session.note.isEmpty {
                        Text(session.note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .swipeActions(edge: .leading) {
                    if session.finishedAt != nil {
                        Button("Edit time") {
                            actions.editWorkoutCompletion(session)
                        }
                        .tint(MomentumTheme.pulse)
                    }
                }
                .swipeActions {
                    if session.finishedAt != nil {
                        Button("Delete", role: .destructive) {
                            actions.requestWorkoutDeletion(session)
                        }
                    }
                }
                .contextMenu {
                    if session.finishedAt != nil {
                        Button("Edit completion time") {
                            actions.editWorkoutCompletion(session)
                        }
                        Button("Delete workout", role: .destructive) {
                            actions.requestWorkoutDeletion(session)
                        }
                    }
                }
            }
            ForEach(dayEvents) { event in
                Label(
                    "Workout \(event.kindRaw)",
                    systemImage: event.kindRaw == "missed" ? "xmark.circle" : "forward.circle"
                )
                .foregroundStyle(.secondary)
            }
        }
    }
}
