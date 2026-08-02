import SwiftData
import SwiftUI
import UIKit
import UserNotifications

@MainActor
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query private var settingsRecords: [AppSettingsRecord]
    @Query private var routineRecords: [CareRoutineTemplateRecord]

    @State private var draft = SettingsDraft.fallback
    @State private var savedDraft: SettingsDraft?
    @State private var isSaving = false
    @State private var notificationStatus = SettingsNotificationStatus.checking
    @State private var exportFiles: [CSVExportFile] = []
    @State private var isPreparingExport = false
    @State private var presentedAlert: SettingsAlert?
    @State private var presentedSheet: SettingsSheet?

    var body: some View {
        Form {
            statusSection
            generalSection
            remindersSection
            exportSection
            aboutSection
            resetSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .tint(MomentumTheme.pulse)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveSettings()
                }
                .disabled(settings == nil || savedDraft == draft || isSaving)
            }
        }
        .task {
            loadDraftIfNeeded()
            await refreshNotificationStatus()
        }
        .alert(item: $presentedAlert) { alert in
            switch alert {
            case .saveFailed:
                Alert(
                    title: Text("Couldn’t save settings"),
                    message: Text("Your changes are still here. Try saving again."),
                    primaryButton: .default(Text("Retry"), action: saveSettings),
                    secondaryButton: .cancel()
                )
            case .exportFailed:
                Alert(
                    title: Text("Couldn’t prepare export"),
                    message: Text("Your data is unchanged. Try preparing the CSV files again."),
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
            LabeledContent {
                Label(notificationStatus.title, systemImage: notificationStatus.symbol)
                    .foregroundStyle(notificationStatus.isProblem ? .orange : .secondary)
            } label: {
                Text("Notifications")
            }

            if notificationStatus == .denied {
                Button("Open system settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
            }

            LabeledContent("iCloud", value: iCloudStatusTitle)
            if let detail = iCloudStatusDetail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Status")
        } footer: {
            Text("Momentum works locally when iCloud or notifications are unavailable.")
        }
    }

    private var generalSection: some View {
        Section {
            Picker("Units", selection: $draft.unitSystemRaw) {
                ForEach(UnitSystemOption.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }

            Picker("Appearance", selection: $draft.selectedAppearanceRaw) {
                ForEach(AppearanceOption.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }

            Stepper(
                value: $draft.domainDayCutoffMinutes,
                in: 0...(12 * 60),
                step: 30
            ) {
                LabeledContent("Domain Day cutoff", value: formattedTime(draft.domainDayCutoffMinutes))
            }
        } header: {
            Text("General")
        } footer: {
            Text("Activity before the cutoff belongs to the previous day. Changing it can alter how recent activity is grouped.")
        }
    }

    private var remindersSection: some View {
        Section {
            SettingsTimePicker(label: "Due workout", minutes: $draft.workoutNotificationMinutes)
            SettingsTimePicker(label: "Unfinished nutrition", minutes: $draft.nutritionReminderMinutes)

            ForEach($draft.routineReminders) { $reminder in
                SettingsTimePicker(label: reminder.name, minutes: $reminder.minutes)
            }
        } header: {
            Text("Reminder times")
        } footer: {
            Text("Times are local to your current time zone. Notification permission is managed by iOS.")
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
        Section("About and data") {
            LabeledContent("App", value: "Momentum")
            Text("Momentum stores workout, nutrition, care, and measurement data on this device and in your private iCloud database when available.")
            Text("There are no accounts, ads, analytics, or third-party data services.")
        }
    }

    private var resetSection: some View {
        Section {
            Button("Reset all data", role: .destructive) {
                presentedSheet = .resetAllData
            }
        } header: {
            Text("Data management")
        } footer: {
            Text("Reset deletes plans, history, food, care, measurements, milestones, and settings. The deletion can synchronize through iCloud.")
        }
    }

    private var settings: AppSettingsRecord? {
        settingsRecords.max { $0.updatedAt < $1.updatedAt }
    }

    private var activeRoutines: [CareRoutineTemplateRecord] {
        routineRecords.filter { !$0.isArchived }
    }

    private var iCloudStatusTitle: String {
        guard let settings else { return "Local only" }
        switch settings.iCloudStatusRaw {
        case "syncing": return "Syncing"
        case "synced", "available": return "Synced recently"
        case "unavailable", "noAccount", "restricted": return "iCloud unavailable"
        case "localOnly": return "Local only"
        default: return settings.lastSuccessfulSyncAt == nil ? "Local only" : "Synced recently"
        }
    }

    private var iCloudStatusDetail: String? {
        guard let settings else { return nil }
        if let lastSuccessfulSyncAt = settings.lastSuccessfulSyncAt {
            return "Last confirmed sync \(lastSuccessfulSyncAt.formatted(date: .abbreviated, time: .shortened))."
        }
        if settings.iCloudStatusRaw == "unavailable" {
            return "Your data remains available on this device."
        }
        return nil
    }

    private func loadDraftIfNeeded() {
        guard savedDraft == nil, let settings else { return }
        let loadedDraft = SettingsDraft(settings: settings, routines: activeRoutines)
        draft = loadedDraft
        savedDraft = loadedDraft
    }

    private func saveSettings() {
        guard let settings else { return }
        isSaving = true
        draft.apply(to: settings, routines: activeRoutines)
        do {
            try modelContext.save()
            savedDraft = draft
            isSaving = false
            Task { try? await DailyReconciler.reconcileAndNotify(in: modelContext) }
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
            try SeedData.install(in: modelContext)
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

    var symbol: String {
        switch self {
        case .checking: "bell"
        case .notDetermined: "bell.badge"
        case .allowed: "bell.fill"
        case .denied, .unavailable: "bell.slash"
        }
    }

    var isProblem: Bool {
        self == .denied || self == .unavailable
    }
}
