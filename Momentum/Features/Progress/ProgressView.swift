import Charts
import MomentumCore
import SwiftData
import SwiftUI

/// Progress is a shared shell: the milestone section is Core-owned and every
/// enabled module contributes its own insight section through the registry.
/// Streak tiles are derived dynamically from enabled modules' categories.
struct ProgressTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [WorkoutSessionRecord]
    @Query private var exerciseLogs: [ExerciseLogRecord]
    @Query private var setLogs: [SetLogRecord]
    @Query private var prescriptions: [ExercisePrescriptionRecord]
    @Query private var foodEntries: [FoodEntryRecord]
    @Query private var nutritionDays: [NutritionDayRecord]
    @Query private var workoutEvents: [WorkoutDayEventRecord]
    @Query private var careOccurrences: [CareOccurrenceRecord]
    @Query private var settingsRecords: [AppSettingsRecord]
    @Query private var milestones: [MilestoneRecord]

    @State private var actionError: String?

    private var settings: AppSettingsRecord? { AppSettingsRecord.canonical(in: settingsRecords) }
    private var enabledModules: [any MomentumModule] {
        ModuleRegistry.standard.enabledModules(ModuleEnablementStore.enabledIDs(from: settings))
    }
    private var moduleContext: ModuleContext {
        ModuleContext.make(in: modelContext, settings: settings)
    }
    private var projection: ProgressProjection {
        ProgressProjection.make(
            sessions: sessions,
            workoutEvents: workoutEvents,
            nutritionDays: nutritionDays,
            careOccurrences: careOccurrences,
            calendar: .autoupdatingCurrent
        )
    }
    private var pendingMilestone: MilestoneRecord? {
        MilestoneService.nextUnacknowledged(in: milestones)
    }

    var body: some View {
        List {
            milestoneSection
            ForEach(Array(registryInsightSections.enumerated()), id: \.offset) { _, section in
                section
            }
            adherenceSection
        }
        .navigationTitle("Progress")
        .alert("Couldn’t update progress", isPresented: Binding(
            get: { actionError != nil }, set: { if !$0 { actionError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(actionError ?? "Try again.") }
    }

    private var registryInsightSections: [AnyView] {
        let context = moduleContext
        return enabledModules.compactMap { ($0 as? any InsightsContributing)?.insightsSection(in: context) }
    }

    @ViewBuilder
    private var milestoneSection: some View {
        if let pendingMilestone {
            let presentation = MilestoneService.presentation(
                for: pendingMilestone,
                prescriptions: prescriptions
            )
            Section("Milestone") {
                VStack(alignment: .leading, spacing: MomentumSpacing.sm) {
                    Label(presentation.title, systemImage: presentation.symbol)
                        .font(.headline)
                        .foregroundStyle(MomentumTheme.pulseDeep)
                    Text(presentation.message)
                        .foregroundStyle(.secondary)
                    Button("Noted") { acknowledge(pendingMilestone) }
                        .buttonStyle(.bordered)
                }
                .accessibilityElement(children: .contain)
            }
        }
    }

    private var adherenceSection: some View {
        Section {
            HStack {
                ForEach(Array(streakTiles.enumerated()), id: \.offset) { index, tile in
                    if index > 0 { Spacer() }
                    ProgressMetric(title: tile.title, value: "\(tile.value)")
                }
            }
            if projection.adherencePoints.isEmpty {
                Text("Complete due activities to build adherence history.").foregroundStyle(.secondary)
            } else {
                Chart(projection.adherencePoints) { point in
                    BarMark(x: .value("Date", point.date), y: .value("Adherence", point.percentage))
                        .foregroundStyle(point.percentage >= 100 ? MomentumTheme.success : MomentumTheme.pulse.opacity(0.65))
                }
                .chartYScale(domain: 0...100)
                .frame(height: 180)
                .accessibilityLabel("Daily adherence percentage")
                .accessibilityValue(projection.adherenceSummary)
            }
        } header: {
            Text("Adherence")
        } footer: {
            Text("Recovery days are neutral. Streaks reset only when a due category is incomplete.")
        }
    }

    private var streakTiles: [(title: String, value: Int)] {
        let facts = HistoryProjection.facts(
            sessions: sessions,
            workoutEvents: workoutEvents,
            nutritionDays: nutritionDays,
            careOccurrences: careOccurrences
        )
        let context = moduleContext
        return enabledModules.compactMap { module -> (title: String, value: Int)? in
            guard let category = Self.streakCategory(for: module.metadata.id) else { return nil }
            let streak = ModuleHistoryMath.categoryStreak(
                facts: facts,
                category: category,
                through: context.currentDomainDay,
                calendar: context.calendar
            )
            return (module.metadata.displayName, streak)
        }
    }

    private static func streakCategory(for id: ModuleID) -> HistoryCategory? {
        switch id {
        case BuiltInModuleID.workout: .workouts
        case BuiltInModuleID.nutrition: .nutrition
        case BuiltInModuleID.care: .care
        default: nil
        }
    }

    private func acknowledge(_ milestone: MilestoneRecord) {
        do { try MilestoneService.acknowledge(milestone, in: modelContext) }
        catch { actionError = "The milestone acknowledgement was not saved." }
    }
}

private struct ProgressMetric: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AdherencePoint: Identifiable {
    var id: String { domainDay }
    let domainDay: String
    let date: Date
    let percentage: Double
}

@MainActor
private struct ProgressProjection {
    let adherencePoints: [AdherencePoint]

    var adherenceSummary: String {
        guard let point = adherencePoints.last else { return "No adherence data." }
        return "Latest scored day: \(DecimalFormatter.whole(point.percentage)) percent."
    }

    static func make(
        sessions: [WorkoutSessionRecord],
        workoutEvents events: [WorkoutDayEventRecord],
        nutritionDays: [NutritionDayRecord],
        careOccurrences care: [CareOccurrenceRecord],
        calendar: Calendar
    ) -> ProgressProjection {
        var counts: [String: (completed: Int, due: Int)] = [:]
        for session in sessions where session.finishedAt != nil && session.deletedAt == nil {
            let day = session.completionDomainDay ?? session.scheduledDomainDay
            counts[day, default: (0, 0)].completed += 1
            counts[day, default: (0, 0)].due += 1
        }
        for event in events where event.deletedAt == nil { counts[event.domainDay, default: (0, 0)].due += 1 }
        for day in nutritionDays {
            counts[day.domainDay, default: (0, 0)].due += 1
            if day.finalizedAt != nil { counts[day.domainDay, default: (0, 0)].completed += 1 }
        }
        for occurrence in care where occurrence.statusRaw != "repairedDuplicate" {
            counts[occurrence.dueDomainDay, default: (0, 0)].due += 1
            if occurrence.statusRaw == "completed" { counts[occurrence.dueDomainDay, default: (0, 0)].completed += 1 }
        }
        let points = counts.compactMap { dayValue, value -> AdherencePoint? in
            guard value.due > 0, let day = PersistedDomainDay.decode(dayValue),
                  let date = PersistedDomainDay.date(for: day, calendar: calendar) else { return nil }
            return AdherencePoint(domainDay: dayValue, date: date, percentage: Double(value.completed) / Double(value.due) * 100)
        }.sorted { $0.domainDay < $1.domainDay }
        return ProgressProjection(adherencePoints: points)
    }
}
