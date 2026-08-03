import MomentumCore
import SwiftData
import SwiftUI

struct HistoryWorkoutCompletionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var settings: [AppSettingsRecord]
    @Query private var workouts: [WorkoutTemplateRecord]
    @Query private var anchors: [CycleAnchorRecord]
    @Query private var sessions: [WorkoutSessionRecord]

    let sessionID: UUID
    @State private var proposedFinishedAt: Date
    @State private var preview: HistoryWorkoutTimestampPreview?
    @State private var showConfirmation = false
    @State private var isSaving = false
    @State private var saveError: String?

    private let calendar = Calendar.autoupdatingCurrent

    init(sessionID: UUID, currentCompletion: Date) {
        self.sessionID = sessionID
        _proposedFinishedAt = State(initialValue: currentCompletion)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Finished",
                        selection: $proposedFinishedAt,
                        in: ...Date.now,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                } header: {
                    Text("Completion")
                } footer: {
                    Text("Only the session timing changes. Logged exercises and sets remain unchanged.")
                }

                if let preview {
                    Section("Schedule preview") {
                        LabeledContent("Before", value: preview.beforeSummary)
                        LabeledContent("After", value: preview.afterSummary)
                        LabeledContent(
                            "Completion day",
                            value: PersistedDomainDay.encode(preview.proposedCompletionDay)
                        )
                    }
                }

                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit workout time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(preview == nil ? "Review" : "Save") {
                        reviewOrSave()
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving)
                }
            }
            .onChange(of: proposedFinishedAt) { _, _ in
                preview = nil
            }
        }
        .confirmationDialog(
            "Apply workout correction?",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Apply correction") { applyCorrection() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let preview {
                Text("Before: \(preview.beforeSummary). After: \(preview.afterSummary). Schedule, adherence, streaks, and reminders will be recalculated.")
            }
        }
    }

    private func reviewOrSave() {
        if preview != nil {
            showConfirmation = true
            return
        }
        preview = HistoryCorrectionProjection.workoutCompletionPreview(
            sessionID: sessionID,
            proposedFinishedAt: proposedFinishedAt,
            workouts: workouts,
            anchors: anchors,
            sessions: sessions,
            settings: settings,
            now: .now,
            calendar: calendar
        )
        if preview == nil {
            saveError = "A schedule preview could not be created. No changes were made."
        }
    }

    private func applyCorrection() {
        isSaving = true
        saveError = nil
        Task { @MainActor in
            do {
                try HistoryCorrectionService.updateWorkoutCompletion(
                    sessionID: sessionID,
                    finishedAt: proposedFinishedAt,
                    in: modelContext,
                    calendar: calendar
                )
            } catch {
                saveError = "The workout correction could not be saved. No partial correction was kept."
                isSaving = false
                return
            }

            do {
                try await DailyReconciler.reconcileAndNotify(
                    in: modelContext,
                    calendar: calendar
                )
                dismiss()
            } catch {
                saveError = "The correction was saved, but reminders could not be refreshed. Try Save again."
                isSaving = false
            }
        }
    }
}
