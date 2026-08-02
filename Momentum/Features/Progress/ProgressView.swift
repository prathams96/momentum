import MomentumCore
import SwiftData
import SwiftUI

struct ProgressTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var measurements: [BodyMeasurementRecord]
    @Query private var sessions: [WorkoutSessionRecord]
    @Query private var suggestions: [LoadSuggestionRecord]

    private var weightMeasurements: [BodyMeasurementRecord] {
        measurements
            .filter { $0.kindRaw == "weightKg" && $0.deletedAt == nil }
            .sorted { $0.measuredAt > $1.measuredAt }
    }

    private var completedSessions: [WorkoutSessionRecord] {
        sessions.filter { $0.finishedAt != nil && $0.deletedAt == nil }.sorted {
            ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast)
        }
    }

    var body: some View {
        List {
            Section("Body weight") {
                if let latest = weightMeasurements.first {
                    LabeledContent("Latest", value: "\(DecimalFormatter.onePlace(latest.value)) kg")
                    if let prior = weightMeasurements.dropFirst().first {
                        let delta = latest.value - prior.value
                        LabeledContent("Since previous", value: "\(delta >= 0 ? "+" : "")\(DecimalFormatter.onePlace(delta)) kg")
                    }
                } else {
                    Text("Add a post-workout check-in to start tracking weight.")
                        .foregroundStyle(.secondary)
                }
                NavigationLink("Log measurement") {
                    MeasurementEntryView()
                }
            }

            Section("Training") {
                LabeledContent("Workouts finished", value: "\(completedSessions.count)")
                if let latest = completedSessions.first {
                    Text("Last: \(latest.workoutNameSnapshot)")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Next load suggestions") {
                let pending = suggestions.filter { $0.statusRaw == "pending" }.sorted { $0.createdAt > $1.createdAt }
                if pending.isEmpty {
                    Text("Complete a workout at the top of its rep range to generate a suggestion.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pending) { suggestion in
                        HStack {
                            Text("\(DecimalFormatter.onePlace(suggestion.suggestedWeightKg)) kg")
                            Spacer()
                            Button("Use") {
                                suggestion.statusRaw = "accepted"
                                suggestion.resolvedAt = .now
                                suggestion.updatedAt = .now
                                try? modelContext.save()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .navigationTitle("Progress")
    }
}

private struct MeasurementEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettingsRecord]
    @State private var weight = ""

    var body: some View {
        Form {
            Section {
                TextField("Weight (kg)", text: $weight)
                    .keyboardType(.decimalPad)
            } footer: {
                Text("Measurements are saved to today’s domain day.")
            }
        }
        .navigationTitle("Log measurement")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(Double(weight) == nil || Double(weight)! <= 0)
            }
        }
    }

    private func save() {
        guard let value = Double(weight), value > 0 else { return }
        let day = DomainDay.containing(.now, calendar: .autoupdatingCurrent, cutoffMinutes: settings.first?.domainDayCutoffMinutes ?? 180)
        modelContext.insert(BodyMeasurementRecord(
            kindRaw: "weightKg",
            value: value,
            domainDay: PersistedDomainDay.encode(day)
        ))
        try? modelContext.save()
        dismiss()
    }
}
