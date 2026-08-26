import MomentumCore
import SwiftData
import SwiftUI

/// Registry-driven shell for one recorded day. Each enabled module supplies
/// its own sections; measurements are Core-owned facts and render here.
struct HistoryDayDetail: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRecords: [AppSettingsRecord]
    @Query private var measurements: [BodyMeasurementRecord]

    let day: DomainDay

    private var dayKey: String { PersistedDomainDay.encode(day) }

    var body: some View {
        List {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                section
            }
            measurementSection
        }
        .navigationTitle(day.historyDate?.formatted(date: .abbreviated, time: .omitted) ?? dayKey)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sections: [AnyView] {
        let settings = AppSettingsRecord.canonical(in: settingsRecords)
        let context = ModuleContext.make(in: modelContext, settings: settings)
        return ModuleRegistry.standard
            .enabledModules(ModuleEnablementStore.enabledIDs(from: settings))
            .flatMap { ($0 as? any HistoryContributing)?.historyDaySections(for: day, in: context) ?? [] }
    }

    @ViewBuilder
    private var measurementSection: some View {
        let unitSystem = UnitSystemOption(
            rawValue: AppSettingsRecord.canonical(in: settingsRecords)?.unitSystemRaw ?? "metric"
        ) ?? .metric
        let dayMeasurements = measurements
            .filter { $0.deletedAt == nil && $0.domainDay == dayKey }
            .sorted { $0.kindRaw < $1.kindRaw }

        if !dayMeasurements.isEmpty {
            Section("Measurements") {
                ForEach(dayMeasurements, id: \.id) { record in
                    LabeledContent(
                        MeasurementKind(rawValue: record.kindRaw)?.title ?? record.kindRaw,
                        value: (MeasurementKind(rawValue: record.kindRaw)?
                            .formatted(metricValue: record.value, unitSystem: unitSystem))
                            ?? DecimalFormatter.onePlace(record.value)
                    )
                }
            }
        }
    }
}
