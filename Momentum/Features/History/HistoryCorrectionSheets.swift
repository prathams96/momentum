import MomentumCore
import SwiftData
import SwiftUI

enum HistorySheetDestination: Identifiable {
    case editFood(id: UUID, domainDay: String)
    case editWorkoutCompletion(id: UUID, currentCompletion: Date)
    case backdate(HistoryBackdateTarget)

    var id: String {
        switch self {
        case let .editFood(id, _): "edit-food-\(id.uuidString)"
        case let .editWorkoutCompletion(id, _): "edit-workout-\(id.uuidString)"
        case let .backdate(target): "backdate-\(target.id)"
        }
    }
}

enum HistoryBackdateTarget: Identifiable {
    case food(id: UUID, currentDay: String)
    case measurement(id: UUID, currentDay: String)

    var id: String {
        switch self {
        case let .food(id, _): "food-\(id.uuidString)"
        case let .measurement(id, _): "measurement-\(id.uuidString)"
        }
    }

    var currentDay: String {
        switch self {
        case let .food(_, day), let .measurement(_, day): day
        }
    }
}

enum HistoryDeletionRequest: Identifiable {
    case food(id: UUID)
    case measurement(id: UUID)
    case workout(id: UUID, preview: HistoryWorkoutDeletionPreview?)

    var id: String {
        switch self {
        case let .food(id): "food-\(id.uuidString)"
        case let .measurement(id): "measurement-\(id.uuidString)"
        case let .workout(id, _): "workout-\(id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .food: "Delete food entry?"
        case .measurement: "Delete measurement?"
        case .workout: "Delete completed workout?"
        }
    }

    var message: String {
        switch self {
        case .food:
            return "Daily nutrition totals and adherence will be recalculated. You can undo this deletion while History remains open."
        case .measurement:
            return "This removes the reading from trends. You can undo this deletion while History remains open."
        case let .workout(_, preview):
            guard let preview else {
                return "Workout order, recovery, adherence, and progression may change. You can undo this deletion while History remains open."
            }
            return "Workout order, recovery, adherence, and progression may change. Before: \(preview.beforeSummary). After: \(preview.afterSummary). You can undo this deletion while History remains open."
        }
    }
}

struct HistoryCareUndoRequest: Identifiable {
    let occurrenceID: UUID
    let routineName: String

    var id: UUID { occurrenceID }
}

struct HistoryBackdateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var settings: [AppSettingsRecord]
    @Query private var foodEntries: [FoodEntryRecord]
    @Query private var measurements: [BodyMeasurementRecord]

    let target: HistoryBackdateTarget

    @State private var selectedDate: Date
    @State private var isSaving = false
    @State private var saveError: String?

    private let calendar = Calendar.autoupdatingCurrent

    init(target: HistoryBackdateTarget) {
        self.target = target
        let initialDay = PersistedDomainDay.decode(target.currentDay)
        _selectedDate = State(initialValue: initialDay.flatMap {
            PersistedDomainDay.date(for: $0, calendar: .autoupdatingCurrent)
        } ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Domain Day",
                        selection: $selectedDate,
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                } footer: {
                    Text("Moving a fact recalculates both the original day and the selected day.")
                }

                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Move to another day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        save()
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        saveError = nil

        let cutoff = AppSettingsRecord.canonical(in: settings)?
            .domainDayCutoffMinutes ?? 180
        let newDay = DomainDay.containing(
            selectedDate,
            calendar: calendar,
            cutoffMinutes: cutoff
        )
        let newDayValue = PersistedDomainDay.encode(newDay)

        switch target {
        case let .food(id, _):
            guard let entry = foodEntries.first(where: { $0.id == id && $0.deletedAt == nil }) else {
                saveError = "The food entry is no longer available."
                isSaving = false
                return
            }
            entry.domainDay = newDayValue
            entry.consumedAt = moving(entry.consumedAt, to: newDay)
            entry.updatedAt = .now
        case let .measurement(id, _):
            guard let measurement = measurements.first(where: {
                $0.id == id && $0.deletedAt == nil
            }) else {
                saveError = "The measurement is no longer available."
                isSaving = false
                return
            }
            measurement.domainDay = newDayValue
            measurement.measuredAt = moving(measurement.measuredAt, to: newDay)
            measurement.updatedAt = .now
        }

        Task { @MainActor in
            do {
                try modelContext.save()
                try await DailyReconciler.reconcileAndNotify(
                    in: modelContext,
                    calendar: calendar
                )
                dismiss()
            } catch {
                saveError = "The new day could not be saved and refreshed. Try again."
                isSaving = false
            }
        }
    }

    private func moving(_ timestamp: Date, to day: DomainDay) -> Date {
        let time = calendar.dateComponents([.hour, .minute, .second], from: timestamp)
        return calendar.date(from: DateComponents(
            year: day.year,
            month: day.month,
            day: day.day,
            hour: time.hour,
            minute: time.minute,
            second: time.second
        )) ?? selectedDate
    }
}
