import MomentumCore
import SwiftData
import SwiftUI

/// Plans is a shared shell: every enabled module contributes its own plan
/// section through the registry. Adding a module never edits this file.
struct PlansView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRecords: [AppSettingsRecord]

    private var registrySections: [AnyView] {
        let context = ModuleContext.make(
            in: modelContext,
            settings: AppSettingsRecord.canonical(in: settingsRecords)
        )
        return ModuleRegistry.standard
            .enabledModules(ModuleEnablementStore.enabledIDs(from: AppSettingsRecord.canonical(in: settingsRecords)))
            .compactMap { ($0 as? any PlanContributing)?.planSection(in: context) }
    }

    var body: some View {
        List {
            ForEach(Array(registrySections.enumerated()), id: \.offset) { _, section in
                section
            }
        }
        .navigationTitle("Plans")
        .toolbar { EditButton() }
    }
}
