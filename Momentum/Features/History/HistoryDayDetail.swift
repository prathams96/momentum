import MomentumCore
import SwiftData
import SwiftUI

/// Registry-driven shell for one recorded day. Each enabled module supplies
/// its own sections; this view owns no domain knowledge.
struct HistoryDayDetail: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRecords: [AppSettingsRecord]

    let day: DomainDay

    var body: some View {
        List {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                section
            }
        }
        .navigationTitle(day.historyDate?.formatted(date: .abbreviated, time: .omitted) ?? PersistedDomainDay.encode(day))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sections: [AnyView] {
        let settings = AppSettingsRecord.canonical(in: settingsRecords)
        let context = ModuleContext.make(in: modelContext, settings: settings)
        return ModuleRegistry.standard
            .enabledModules(ModuleEnablementStore.enabledIDs(from: settings))
            .flatMap { ($0 as? any HistoryContributing)?.historyDaySections(for: day, in: context) ?? [] }
    }
}
