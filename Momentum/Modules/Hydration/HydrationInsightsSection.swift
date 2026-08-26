import MomentumCore
import SwiftData
import SwiftUI

/// The hydration module's contribution to the Progress surface: average
/// daily intake and target-reached rate across the last 30 eligible days.
/// A day is eligible when it has a HydrationDayRecord; the module being asked
/// implies it is enabled.
struct HydrationInsightsSection: View {
    @Query private var settings: [AppSettingsRecord]
    @Query private var hydrationEntries: [HydrationEntryRecord]
    @Query private var hydrationDays: [HydrationDayRecord]

    private var projection: HydrationInsightsProjection {
        HydrationInsightsProjection.make(
            entries: hydrationEntries,
            dayRecords: hydrationDays,
            cutoffMinutes: AppSettingsRecord.canonical(in: settings)?.domainDayCutoffMinutes ?? 180,
            calendar: .autoupdatingCurrent
        )
    }

    var body: some View {
        Section {
            if projection.eligibleDays.isEmpty {
                Text("Log water to see intake trends.")
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent(
                    "Average daily intake",
                    value: HydrationVolumeFormatting.volume(
                        projection.averageDailyML,
                        unitSystem: UnitSystemOption(
                            rawValue: AppSettingsRecord.canonical(in: settings)?.unitSystemRaw ?? "metric"
                        ) ?? .metric
                    )
                )
                LabeledContent(
                    "Days target reached",
                    value: "\(projection.reachedCount) of \(projection.eligibleDays.count) · \(projection.reachedPercentage)%"
                )
            }
        } header: {
            Text("Hydration")
        } footer: {
            Text("Averaged over the last 30 days with a recorded target.")
        }
    }
}

@MainActor
struct HydrationInsightsProjection {
    struct EligibleDay: Identifiable {
        let dayKey: String
        let totalML: Int
        let targetML: Int

        var id: String { dayKey }
        var isReached: Bool { totalML >= targetML }
    }

    let eligibleDays: [EligibleDay]

    static func make(
        entries: [HydrationEntryRecord],
        dayRecords: [HydrationDayRecord],
        cutoffMinutes: Int,
        calendar: Calendar,
        now: Date = .now,
        windowLength: Int = 30
    ) -> HydrationInsightsProjection {
        let currentDay = DomainDay.containing(now, calendar: calendar, cutoffMinutes: cutoffMinutes)
        let recordByDay = Dictionary(
            dayRecords.map { ($0.domainDay, $0) },
            uniquingKeysWith: { lhs, rhs in lhs.createdAt <= rhs.createdAt ? lhs : rhs }
        )

        var eligible: [EligibleDay] = []
        for offset in 0..<windowLength {
            let day = currentDay.adding(days: -offset, calendar: calendar)
            let dayKey = PersistedDomainDay.encode(day)
            guard let record = recordByDay[dayKey] else { continue }
            let total = entries
                .filter { $0.domainDay == dayKey && $0.deletedAt == nil }
                .reduce(0) { $0 + $1.amountML }
            eligible.append(EligibleDay(dayKey: dayKey, totalML: total, targetML: record.targetMLSnapshot))
        }
        return HydrationInsightsProjection(eligibleDays: eligible)
    }

    var averageDailyML: Int {
        guard !eligibleDays.isEmpty else { return 0 }
        return Int((Double(eligibleDays.map(\.totalML).reduce(0, +)) / Double(eligibleDays.count)).rounded())
    }

    var reachedCount: Int {
        eligibleDays.count(where: \.isReached)
    }

    var reachedPercentage: Int {
        guard !eligibleDays.isEmpty else { return 0 }
        return Int((Double(reachedCount) / Double(eligibleDays.count) * 100).rounded())
    }
}

// MARK: - Insights contribution

extension HydrationModuleAdapter: InsightsContributing {
    func insightsSection(in context: ModuleContext) -> AnyView? {
        AnyView(HydrationInsightsSection())
    }
}
