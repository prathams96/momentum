import Charts
import MomentumCore
import SwiftData
import SwiftUI

/// Progress is a shared shell: the milestone section is Core-owned and every
/// enabled module contributes its own insight section through the registry.
/// Adherence renders as registry-driven per-category rhythm strips — there is
/// no blended score anywhere.
struct ProgressTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var prescriptions: [ExercisePrescriptionRecord]
    @Query private var settingsRecords: [AppSettingsRecord]
    @Query private var milestones: [MilestoneRecord]

    @State private var actionError: String?

    private let calendar = Calendar.autoupdatingCurrent

    private var settings: AppSettingsRecord? { AppSettingsRecord.canonical(in: settingsRecords) }
    private var currentDay: DomainDay {
        ScheduleProjection.currentDomainDay(settings: settingsRecords, now: .now, calendar: calendar)
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
            RhythmStripsSection(
                title: "Adherence",
                settings: settings,
                currentDay: currentDay,
                calendar: calendar
            )
        }
        .navigationTitle("Progress")
        .alert("Couldn’t update progress", isPresented: Binding(
            get: { actionError != nil }, set: { if !$0 { actionError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(actionError ?? "Try again.") }
    }

    private var registryInsightSections: [AnyView] {
        let context = ModuleContext.make(in: modelContext, settings: settings)
        return ModuleRegistry.standard
            .enabledModules(ModuleEnablementStore.enabledIDs(from: settings))
            .compactMap { ($0 as? any InsightsContributing)?.insightsSection(in: context) }
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

    private func acknowledge(_ milestone: MilestoneRecord) {
        do { try MilestoneService.acknowledge(milestone, in: modelContext) }
        catch { actionError = "The milestone acknowledgement was not saved." }
    }
}
