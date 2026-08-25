import MomentumCore
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

@MainActor
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Query private var settingsRecords: [AppSettingsRecord]
    @Query private var routineRecords: [CareRoutineTemplateRecord]

    @State private var draft = SettingsDraft.fallback
    @State private var savedDraft: SettingsDraft?
    @State private var isSaving = false
    @State private var notificationStatus = SettingsNotificationStatus.checking
    @State private var exportFiles: [CSVExportFile] = []
    @State private var isPreparingExport = false
    @State private var isRestoringExamplePlan = false
    @State private var presentedAlert: SettingsAlert?
    @State private var presentedSheet: SettingsSheet?

    var body: some View {
        Form {
            statusSection
            generalSection
            modulesSection
            dailyRemindersSection
            careRemindersSection
            exportSection
            aboutSection
            resetSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .tint(MomentumTheme.pulse)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    requestSaveSettings()
                } label: {
                    ZStack {
                        Text("Save")
                            .opacity(isSaving ? 0 : 1)
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .frame(minWidth: 36)
                }
                .disabled(settings == nil || savedDraft == draft || isSaving)
                .accessibilityLabel(isSaving ? "Saving settings" : "Save settings")
            }
        }
        .task {
            loadDraftIfNeeded()
            await refreshNotificationStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshNotificationStatus() }
        }
        .alert(item: $presentedAlert) { alert in
            switch alert {
            case .saveFailed:
                Alert(
                    title: Text("Couldn’t save settings"),
                    message: Text("Your changes are still here. Try saving again."),
                    primaryButton: .default(Text("Retry"), action: persistSettings),
                    secondaryButton: .cancel()
                )
            case .confirmCutoffChange:
                Alert(
                    title: Text("Change Domain Day cutoff?"),
                    message: Text(cutoffChangeMessage),
                    primaryButton: .default(Text("Change cutoff"), action: persistSettings),
                    secondaryButton: .cancel(Text("Keep current cutoff"))
                )
            case .exportFailed:
                Alert(
                    title: Text("Couldn’t prepare export"),
                    message: Text("Your data is unchanged. Try preparing the CSV files again."),
                    dismissButton: .default(Text("OK"))
                )
            case .reminderRefreshFailed:
                Alert(
                    title: Text("Settings saved"),
                    message: Text("Reminder delivery could not be refreshed. Momentum will try again when the app becomes active."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .resetAllData:
                ResetAllDataSheet()
            }
        }
    }

    private var statusSection: some View {
        Section {
            SettingsStatusRow(
                title: "Notifications",
                symbol: "bell.fill",
                value: notificationStatus.title,
                valueSymbol: notificationStatus.valueSymbol,
                tint: notificationStatus.tint
            )

            if notificationStatus == .denied {
                Button {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                } label: {
                    Label("Open system settings", systemImage: "arrow.up.right")
                }
            }

            SettingsStatusRow(
                title: "iCloud",
                symbol: "icloud.fill",
                value: iCloudStatusTitle,
                valueSymbol: iCloudStatusSymbol,
                tint: iCloudStatusTint,
                detail: iCloudStatusDetail
            )

            if let schedulingStatusTitle {
                SettingsStatusRow(
                    title: "Reminder scheduling",
                    symbol: "clock.badge.checkmark.fill",
                    value: schedulingStatusTitle,
                    valueSymbol: settings?.notificationSchedulingStatusRaw == "failed"
                        ? "exclamationmark.triangle.fill"
                        : "checkmark.circle.fill",
                    tint: settings?.notificationSchedulingStatusRaw == "failed"
                        ? MomentumTheme.warning
                        : MomentumTheme.success
                )
            }
        } header: {
            Text("System status")
        } footer: {
            Text("Momentum works locally when iCloud or notifications are unavailable.")
        }
    }

    private var generalSection: some View {
        Section {
            Picker(selection: $draft.unitSystemRaw) {
                ForEach(UnitSystemOption.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            } label: {
                Label("Units", systemImage: "scalemass")
            }

            Picker(selection: $draft.selectedAppearanceRaw) {
                ForEach(AppearanceOption.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            } label: {
                Label("Appearance", systemImage: "circle.lefthalf.filled")
            }

            Stepper(
                value: $draft.domainDayCutoffMinutes,
                in: 0...(12 * 60),
                step: 30
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Domain Day cutoff", systemImage: "moon.stars.fill")
                    Text(formattedTime(draft.domainDayCutoffMinutes))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("General")
        } footer: {
            Text("Activity before the cutoff belongs to the previous day. Changing it can alter how recent activity is grouped.")
        }
    }

    private var modulesSection: some View {
        Section {
            ForEach(ModuleRegistry.standard.modules, id: \.metadata.id) { module in
                Toggle(isOn: moduleToggle(for: module.metadata.id)) {
                    Label(module.metadata.displayName, systemImage: module.metadata.symbolName)
                }
            }
        } header: {
            Text("Modules")
        } footer: {
            Text("With a module off, its surfaces are hidden and its reminders are cancelled. History stays readable and your data is retained. Its streak pauses—never breaks—and resumes the day after you turn it back on.")
        }
    }

    private func moduleToggle(for id: ModuleID) -> Binding<Bool> {
        Binding(
            get: { draft.enabledModuleIDs.contains(id) },
            set: { isIncluded in
                if isIncluded {
                    draft.enabledModuleIDs.insert(id)
                } else {
                    draft.enabledModuleIDs.remove(id)
                }
            }
        )
    }

    private var dailyRemindersSection: some View {
        Section {
            if draft.enabledModuleIDs.contains(BuiltInModuleID.workout) {
                SettingsTimePicker(label: "Due workout", minutes: $draft.workoutNotificationMinutes)
            }
            if draft.enabledModuleIDs.contains(BuiltInModuleID.nutrition) {
                SettingsTimePicker(label: "Unfinished nutrition", minutes: $draft.nutritionReminderMinutes)
            }
        } header: {
            Text("Daily reminders")
        } footer: {
            Text("Times are local to your current time zone. Notification permission is managed by iOS.")
        }
    }

    @ViewBuilder
    private var careRemindersSection: some View {
        if !draft.routineReminders.isEmpty,
           draft.enabledModuleIDs.contains(BuiltInModuleID.care) {
            Section("Personal care reminders") {
                ForEach($draft.routineReminders) { $reminder in
                    SettingsTimePicker(label: reminder.name, minutes: $reminder.minutes)
                }
            }
        }
    }

    private var exportSection: some View {
        Section {
            Button {
                Task { await prepareExport() }
            } label: {
                HStack {
                    Label(exportFiles.isEmpty ? "Prepare CSV files" : "Refresh CSV files", systemImage: "square.and.arrow.up")
                    Spacer()
                    if isPreparingExport {
                        ProgressView()
                    }
                }
            }
            .disabled(isPreparingExport)

            ForEach(exportFiles) { file in
                ShareLink(
                    item: file.url,
                    preview: SharePreview(file.name, image: Image(systemName: "tablecells"))
                ) {
                    Label(file.name, systemImage: "doc.text")
                }
            }
        } header: {
            Text("CSV export")
        } footer: {
            Text("Exports are UTF-8 CSV files containing stable IDs, timestamps, Domain Days, and historical snapshot values.")
        }
    }

    private var aboutSection: some View {
        Section("About and privacy") {
            LabeledContent("App", value: "Momentum")
            VStack(alignment: .leading, spacing: MomentumSpacing.xs) {
                Label("Data storage", systemImage: "hand.raised.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Momentum stores workout, nutrition, care, and measurement data on this device and in your private iCloud database when available.")
                Text("There are no accounts, ads, analytics, or third-party data services.")
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, MomentumSpacing.xxs)
        }
    }

    private var resetSection: some View {
        Section {
            Button {
                Task { await restoreExamplePlan() }
            } label: {
                HStack {
                    Label("Install example plan", systemImage: "sparkles")
                    Spacer()
                    if isRestoringExamplePlan {
                        ProgressView()
                    }
                }
            }
            .disabled(isRestoringExamplePlan)

            Button("Reset all data", role: .destructive) {
                presentedSheet = .resetAllData
            }
        } header: {
            Text("Data management")
        } footer: {
            Text("The example plan installs the built-in Upper/Lower workout templates and personal care routines, and enables their modules. Reset deletes plans, history, food, care, measurements, milestones, and settings. The deletion can synchronize through iCloud.")
        }
    }

    private func restoreExamplePlan() async {
        isRestoringExamplePlan = true
        defer { isRestoringExamplePlan = false }
        do {
            try SeedData.install(in: modelContext)
            if let settings {
                var ids = ModuleEnablementStore.enabledIDs(from: settings)
                ids.formUnion(ModuleRegistry.defaultEnabledIDs)
                ModuleEnablementStore.apply(ids, to: settings)
            }
            try modelContext.save()
            draft = SettingsDraft(
                settings: AppSettingsRecord.canonical(in: settingsRecords) ?? AppSettingsRecord(),
                routines: activeRoutines
            )
            savedDraft = draft
        } catch {
            presentedAlert = .saveFailed
        }
    }

    private var settings: AppSettingsRecord? {
        AppSettingsRecord.canonical(in: settingsRecords)
    }

    private var activeRoutines: [CareRoutineTemplateRecord] {
        routineRecords.filter { !$0.isArchived }
    }

    private var iCloudStatusTitle: String {
        guard let settings else { return "Local only" }
        switch settings.iCloudStatusRaw {
        case "syncing", "available": return "Syncing"
        case "synced": return "Synced recently"
        case "unavailable", "noAccount", "restricted": return "iCloud unavailable"
        case "localOnly": return "Local only"
        default: return settings.lastSuccessfulSyncAt == nil ? "Local only" : "Synced recently"
        }
    }

    private var iCloudStatusDetail: String? {
        guard let settings else { return nil }
        switch settings.iCloudStatusRaw {
        case "syncing", "available":
            return "iCloud is available. Waiting for a confirmed sync event."
        case "unavailable", "noAccount", "restricted":
            return "Your data remains available on this device."
        case "localOnly":
            return "This build stores data only on this device."
        default:
            break
        }
        if settings.iCloudStatusRaw == "synced",
           let lastSuccessfulSyncAt = settings.lastSuccessfulSyncAt {
            return "Last confirmed sync \(lastSuccessfulSyncAt.formatted(date: .abbreviated, time: .shortened))."
        }
        return nil
    }

    private var iCloudStatusSymbol: String {
        switch settings?.iCloudStatusRaw {
        case "synced": "checkmark.circle.fill"
        case "unavailable", "noAccount", "restricted": "exclamationmark.triangle.fill"
        case "syncing", "available": "arrow.triangle.2.circlepath"
        default: "iphone"
        }
    }

    private var iCloudStatusTint: Color {
        switch settings?.iCloudStatusRaw {
        case "synced": MomentumTheme.success
        case "unavailable", "noAccount", "restricted": MomentumTheme.warning
        default: .secondary
        }
    }

    private func loadDraftIfNeeded() {
        guard savedDraft == nil, let settings else { return }
        let loadedDraft = SettingsDraft(settings: settings, routines: activeRoutines)
        draft = loadedDraft
        savedDraft = loadedDraft
    }

    private var schedulingStatusTitle: String? {
        switch settings?.notificationSchedulingStatusRaw {
        case "healthy": "Up to date"
        case "failed": "Needs retry"
        default: nil
        }
    }

    private var cutoffChangeMessage: String {
        let previous = savedDraft?.domainDayCutoffMinutes ?? settings?.domainDayCutoffMinutes ?? 180
        let next = draft.domainDayCutoffMinutes
        let oldDay = DomainDay.containing(.now, calendar: .autoupdatingCurrent, cutoffMinutes: previous)
        let newDay = DomainDay.containing(.now, calendar: .autoupdatingCurrent, cutoffMinutes: next)
        let attribution = oldDay == newDay
            ? "Today remains \(PersistedDomainDay.encode(newDay))."
            : "The current moment moves from \(PersistedDomainDay.encode(oldDay)) to \(PersistedDomainDay.encode(newDay))."
        return "The cutoff will change from \(formattedTime(previous)) to \(formattedTime(next)). \(attribution) Recent history, streaks, and reminders will be recalculated."
    }

    private func requestSaveSettings() {
        if let savedDraft,
           savedDraft.domainDayCutoffMinutes != draft.domainDayCutoffMinutes {
            presentedAlert = .confirmCutoffChange
        } else {
            persistSettings()
        }
    }

    private func persistSettings() {
        guard let settings else { return }
        isSaving = true
        draft.apply(to: settings, routines: activeRoutines)
        do {
            try modelContext.save()
            savedDraft = draft
            isSaving = false
            Task {
                do { try await DailyReconciler.reconcileAndNotify(in: modelContext) }
                catch { presentedAlert = .reminderRefreshFailed }
            }
        } catch {
            modelContext.rollback()
            isSaving = false
            presentedAlert = .saveFailed
        }
    }

    private func prepareExport() async {
        isPreparingExport = true
        defer { isPreparingExport = false }
        do {
            let snapshot = try CSVExportSnapshot(context: modelContext)
            exportFiles = try await Task.detached {
                try CSVExportService().export(snapshot)
            }.value
        } catch {
            presentedAlert = .exportFailed
        }
    }

    private func refreshNotificationStatus() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationStatus = SettingsNotificationStatus(status)
    }

    private func formattedTime(_ minutes: Int) -> String {
        let date = Calendar.autoupdatingCurrent.date(
            from: DateComponents(hour: minutes / 60, minute: minutes % 60)
        ) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private struct SettingsStatusRow: View {
    let title: String
    let symbol: String
    let value: String
    let valueSymbol: String
    let tint: Color
    var detail: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: MomentumSpacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MomentumTheme.pulse)
                .frame(width: 30, height: 30)
                .background(MomentumTheme.pulseWash)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: MomentumSpacing.xxs) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: MomentumSpacing.xxs) {
                        Text(title)
                            .font(.body.weight(.medium))
                        statusLabel
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: MomentumSpacing.sm) {
                        Text(title)
                            .font(.body.weight(.medium))
                        Spacer(minLength: 0)
                        statusLabel
                    }
                }

                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, MomentumSpacing.xxs)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
    }

    private var statusLabel: some View {
        Label(value, systemImage: valueSymbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SettingsTimePicker: View {
    let label: String
    @Binding var minutes: Int

    var body: some View {
        DatePicker(selection: timeBinding, displayedComponents: .hourAndMinute) {
            Text(label)
        }
        .datePickerStyle(.compact)
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.autoupdatingCurrent.date(
                    from: DateComponents(hour: minutes / 60, minute: minutes % 60)
                ) ?? .now
            },
            set: { date in
                let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
                minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }
}

@MainActor
private struct ResetAllDataSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var confirmation = ""
    @State private var isResetting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("This cannot be undone", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("Plans, workout history, food logs, care history, measurements, milestones, and settings will be deleted.")
                }

                Section {
                    TextField(ResetAllDataService.confirmationPhrase, text: $confirmation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } header: {
                    Text("Type \(ResetAllDataService.confirmationPhrase) to continue")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Reset all data")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isResetting)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isResetting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Delete", role: .destructive) {
                        Task { await resetAllData() }
                    }
                    .disabled(confirmation != ResetAllDataService.confirmationPhrase || isResetting)
                }
            }
        }
    }

    private func resetAllData() async {
        isResetting = true
        errorMessage = nil
        do {
            try ResetAllDataService.reset(context: modelContext)
            // Empty by default: a reset returns to the empty app, not the
            // example plan. The example plan comes back only on request.
            try SeedData.ensureSettingsRecord(in: modelContext)
            await NotificationScheduler().cancelAllMomentumReminders()
            dismiss()
        } catch {
            errorMessage = "Nothing was deleted. Try again."
            isResetting = false
        }
    }
}

private enum SettingsAlert: String, Identifiable {
    case saveFailed
    case exportFailed
    case reminderRefreshFailed
    case confirmCutoffChange

    var id: String { rawValue }
}

private enum SettingsSheet: String, Identifiable {
    case resetAllData

    var id: String { rawValue }
}

private enum SettingsNotificationStatus: Equatable {
    case checking
    case notDetermined
    case allowed
    case denied
    case unavailable

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .authorized, .provisional, .ephemeral: self = .allowed
        @unknown default: self = .unavailable
        }
    }

    var title: String {
        switch self {
        case .checking: "Checking"
        case .notDetermined: "Not requested"
        case .allowed: "Allowed"
        case .denied: "Off"
        case .unavailable: "Unavailable"
        }
    }

    var valueSymbol: String {
        switch self {
        case .checking: "ellipsis.circle"
        case .notDetermined: "questionmark.circle"
        case .allowed: "checkmark.circle.fill"
        case .denied, .unavailable: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .allowed: MomentumTheme.success
        case .denied, .unavailable: MomentumTheme.warning
        case .checking, .notDetermined: .secondary
        }
    }

}
