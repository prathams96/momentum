import MomentumCore
import SwiftData
import SwiftUI

/// The care module's contribution to the Today surface: morning, night, hair,
/// and post-workout routine occurrences.
struct CareTodaySection: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettingsRecord]
    @Query private var occurrences: [CareOccurrenceRecord]

    @State private var presentedCareOccurrenceID: UUID?

    private let calendar = Calendar.autoupdatingCurrent

    private var currentDomainDay: DomainDay {
        ScheduleProjection.currentDomainDay(settings: settings, now: .now, calendar: calendar)
    }

    private var todayCareOccurrences: [CareOccurrenceRecord] {
        occurrences.filter {
            $0.dueDomainDay == PersistedDomainDay.encode(currentDomainDay)
        }
    }

    private var morningOccurrence: CareOccurrenceRecord? {
        occurrence { $0.routineRoleRaw == "morning" || $0.routineNameSnapshot == "Morning care" }
    }

    private var nightOccurrence: CareOccurrenceRecord? {
        occurrence { $0.routineRoleRaw == "night" || $0.routineNameSnapshot.hasPrefix("Night care") }
    }

    private var hairOccurrence: CareOccurrenceRecord? {
        occurrence { $0.routineRoleRaw == "hair" || $0.routineNameSnapshot == "Hair care" }
    }

    private var postWorkoutOccurrences: [CareOccurrenceRecord] {
        occurrences
            .filter {
                $0.dueDomainDay == PersistedDomainDay.encode(currentDomainDay) &&
                $0.routineRoleRaw == "postWorkout"
            }
            .sorted { $0.dueAt < $1.dueAt }
    }

    private func occurrence(where predicate: (CareOccurrenceRecord) -> Bool) -> CareOccurrenceRecord? {
        occurrences
            .filter { $0.dueDomainDay == PersistedDomainDay.encode(currentDomainDay) && predicate($0) }
            .sorted { $0.dueAt < $1.dueAt }
            .first
    }

    var body: some View {
        careContent
            .sheet(isPresented: Binding(
                get: { presentedCareOccurrenceID != nil },
                set: { if !$0 { presentedCareOccurrenceID = nil } }
            )) {
                if let occurrenceID = presentedCareOccurrenceID {
                    CareRoutineSheet(occurrenceID: occurrenceID)
                }
            }
    }

    private var careContent: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.md) {
            Text("Care")
                .font(.title3.bold())

            VStack(spacing: 0) {
                careButton(for: morningOccurrence, fallbackTitle: "Morning care", symbol: "sun.max", detail: "Daily routine")
                Divider().padding(.leading, 52)
                careButton(for: nightOccurrence, fallbackTitle: "Night care", symbol: "moon", detail: "Current weekday routine")
                Divider().padding(.leading, 52)
                careButton(for: hairOccurrence, fallbackTitle: "Hair care", symbol: "drop", detail: "Alternating routine")
                ForEach(postWorkoutOccurrences) { occurrence in
                    Divider().padding(.leading, 52)
                    careButton(
                        for: occurrence,
                        fallbackTitle: "Post-workout care",
                        symbol: "figure.cooldown",
                        detail: "Added after today’s workout"
                    )
                }
            }
        }
    }

    private func careButton(
        for occurrence: CareOccurrenceRecord?,
        fallbackTitle: String,
        symbol: String,
        detail: String
    ) -> some View {
        Button {
            if let occurrence { presentedCareOccurrenceID = occurrence.id }
        } label: {
            ActivityRow(
                symbol: symbol,
                title: fallbackTitle,
                detail: occurrence.map(careStatusDetail) ?? detail,
                tint: occurrence?.statusRaw == "completed" ? MomentumTheme.success : MomentumTheme.pulse
            )
        }
        .disabled(occurrence == nil)
    }

    private func careStatusDetail(_ occurrence: CareOccurrenceRecord) -> String {
        switch occurrence.statusRaw {
        case "completed":
            return "Completed at \(occurrence.completedAt?.formatted(date: .omitted, time: .shortened) ?? "today")"
        case "skipped":
            return "Skipped today"
        case "missed":
            return "Missed"
        default:
            return "Due at \(occurrence.dueAt.formatted(date: .omitted, time: .shortened))"
        }
    }
}

private struct ActivityRow: View {
    let symbol: String
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(spacing: MomentumSpacing.md) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.body).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, MomentumSpacing.sm)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Today contribution

extension CareModuleAdapter: TodayContributing {
    func todayContribution(in context: ModuleContext) -> TodayContribution? {
        let modelContext = context.modelContext
        let occurrences = (try? modelContext.fetch(FetchDescriptor<CareOccurrenceRecord>())) ?? []
        let todayOccurrences = occurrences.filter {
            $0.dueDomainDay == PersistedDomainDay.encode(context.currentDomainDay)
        }

        guard !todayOccurrences.isEmpty else {
            return TodayContribution(metadata: metadata, state: .optional, accessibilitySummary: "Care. No routines due.")
        }

        let completedCount = todayOccurrences.count { ["completed", "skipped"].contains($0.statusRaw) }
        let state: ContributionState = completedCount == todayOccurrences.count ? .completed : .ongoing

        return TodayContribution(
            metadata: metadata,
            state: state,
            accessibilitySummary: "Care. \(completedCount) of \(todayOccurrences.count) routines done."
        )
    }

    func todaySection(in context: ModuleContext) -> AnyView? {
        AnyView(CareTodaySection())
    }
}
