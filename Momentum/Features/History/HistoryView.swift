import MomentumCore
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query private var sessions: [WorkoutSessionRecord]
    @Query private var workoutEvents: [WorkoutDayEventRecord]
    @Query private var nutritionDays: [NutritionDayRecord]
    @Query private var careOccurrences: [CareOccurrenceRecord]

    private var days: [DomainDay] {
        let values = sessions.compactMap { PersistedDomainDay.decode($0.completionDomainDay ?? $0.scheduledDomainDay) }
            + workoutEvents.compactMap { PersistedDomainDay.decode($0.domainDay) }
            + nutritionDays.compactMap { PersistedDomainDay.decode($0.domainDay) }
            + careOccurrences.compactMap { PersistedDomainDay.decode($0.dueDomainDay) }
        return Array(Set(values)).sorted(by: >)
    }

    var body: some View {
        Group {
            if days.isEmpty {
                ContentUnavailableView(
                    "No history yet",
                    systemImage: "calendar",
                    description: Text("Completed workouts, nutrition days, and care routines will appear here.")
                )
            } else {
                List(days, id: \.self) { day in
                    NavigationLink(value: day) {
                        HistoryDayRow(
                            day: day,
                            sessions: sessions,
                            workoutEvents: workoutEvents,
                            nutritionDays: nutritionDays,
                            careOccurrences: careOccurrences
                        )
                    }
                }
                .navigationDestination(for: DomainDay.self) { day in
                    HistoryDayDetail(
                        day: day,
                        sessions: sessions,
                        workoutEvents: workoutEvents,
                        nutritionDays: nutritionDays,
                        careOccurrences: careOccurrences
                    )
                }
            }
        }
        .navigationTitle("History")
    }
}

private struct HistoryDayRow: View {
    let day: DomainDay
    let sessions: [WorkoutSessionRecord]
    let workoutEvents: [WorkoutDayEventRecord]
    let nutritionDays: [NutritionDayRecord]
    let careOccurrences: [CareOccurrenceRecord]

    private var dayKey: String { PersistedDomainDay.encode(day) }
    private var workoutLabel: String {
        if sessions.contains(where: { $0.completionDomainDay == dayKey }) { return "Workout finished" }
        if workoutEvents.contains(where: { $0.domainDay == dayKey && $0.kindRaw == "skipped" }) { return "Workout skipped" }
        if workoutEvents.contains(where: { $0.domainDay == dayKey && $0.kindRaw == "missed" }) { return "Workout missed" }
        return "No workout"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.xs) {
            Text(day.foundationDate.formatted(date: .abbreviated, time: .omitted))
                .font(.headline)
            Text(workoutLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: MomentumSpacing.sm) {
                Label(nutritionDays.contains(where: { $0.domainDay == dayKey && $0.finalizedAt != nil }) ? "Nutrition done" : "Nutrition open", systemImage: "fork.knife")
                Label("\(careOccurrences.filter { $0.dueDomainDay == dayKey && $0.statusRaw == "completed" }.count) care", systemImage: "sparkles")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, MomentumSpacing.xs)
    }
}

private struct HistoryDayDetail: View {
    @Environment(\.modelContext) private var modelContext
    let day: DomainDay
    let sessions: [WorkoutSessionRecord]
    let workoutEvents: [WorkoutDayEventRecord]
    let nutritionDays: [NutritionDayRecord]
    let careOccurrences: [CareOccurrenceRecord]

    private var dayKey: String { PersistedDomainDay.encode(day) }

    var body: some View {
        List {
            Section("Workout") {
                ForEach(sessions.filter { ($0.completionDomainDay ?? $0.scheduledDomainDay) == dayKey }) { session in
                    VStack(alignment: .leading) {
                        Text(session.workoutNameSnapshot)
                        Text(session.finishedAt.map { "Finished \($0.formatted(date: .omitted, time: .shortened))" } ?? "Started, not finished")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(workoutEvents.filter { $0.domainDay == dayKey }) { event in
                    Label(event.kindRaw.capitalized, systemImage: event.kindRaw == "missed" ? "xmark.circle" : "forward.circle")
                }
            }
            Section("Nutrition") {
                if let dayRecord = nutritionDays.first(where: { $0.domainDay == dayKey }) {
                    Label(dayRecord.finalizedAt == nil ? "Still open" : "Finalized", systemImage: dayRecord.finalizedAt == nil ? "circle" : "checkmark.circle.fill")
                } else {
                    Text("No nutrition log")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Care") {
                ForEach(careOccurrences.filter { $0.dueDomainDay == dayKey }) { occurrence in
                    HStack {
                        Text(occurrence.routineNameSnapshot)
                        Spacer()
                        Text(occurrence.statusRaw.capitalized)
                            .foregroundStyle(occurrence.statusRaw == "completed" ? MomentumTheme.success : .secondary)
                    }
                }
            }
        }
        .navigationTitle(day.foundationDate.formatted(date: .abbreviated, time: .omitted))
    }
}

private extension DomainDay {
    var foundationDate: Date {
        PersistedDomainDay.date(for: self, calendar: .autoupdatingCurrent) ?? .now
    }
}
