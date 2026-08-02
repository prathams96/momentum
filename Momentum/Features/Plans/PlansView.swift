import MomentumCore
import SwiftData
import SwiftUI

struct PlansView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutTemplateRecord.sequenceIndex) private var workouts: [WorkoutTemplateRecord]
    @Query private var exercises: [ExercisePrescriptionRecord]
    @Query private var anchors: [CycleAnchorRecord]
    @Query private var settingsRecords: [AppSettingsRecord]
    @Query private var nutritionTargets: [NutritionTargetRecord]

    @State private var calorieMinimum = 2300
    @State private var calorieMaximum = 2500
    @State private var proteinMinimum = 150

    private var settings: AppSettingsRecord? { settingsRecords.max { $0.updatedAt < $1.updatedAt } }
    private var target: NutritionTargetRecord? { nutritionTargets.max { $0.effectiveFrom < $1.effectiveFrom } }

    var body: some View {
        List {
            Section("Workout cycle") {
                ForEach(workouts.filter { !$0.isArchived }) { workout in
                    VStack(alignment: .leading, spacing: MomentumSpacing.xs) {
                        HStack {
                            Text("\(workout.sequenceIndex + 1). \(workout.name)")
                                .font(.headline)
                            Spacer()
                            if anchors.first?.nextWorkoutTemplateID == workout.id {
                                Text("Next")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(MomentumTheme.pulse)
                            } else {
                                Button("Make next") { choose(workout) }
                                    .buttonStyle(.bordered)
                            }
                        }
                        Text(workout.focus)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(exercises.filter { $0.workoutTemplateID == workout.id && !$0.isArchived }.count) exercises · \(workout.recoveryDaysAfter) recovery day\(workout.recoveryDaysAfter == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, MomentumSpacing.xs)
                }
            }

            Section("Nutrition target") {
                Stepper("Minimum calories: \(calorieMinimum)", value: $calorieMinimum, in: 0...10_000, step: 50)
                Stepper("Maximum calories: \(calorieMaximum)", value: $calorieMaximum, in: calorieMinimum...10_000, step: 50)
                Stepper("Minimum protein: \(proteinMinimum) g", value: $proteinMinimum, in: 0...500, step: 5)
                Button("Save nutrition target") { saveTarget() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Plans")
        .onAppear {
            calorieMinimum = target?.calorieMinimum ?? settings?.calorieMinimum ?? 2300
            calorieMaximum = target?.calorieMaximum ?? settings?.calorieMaximum ?? 2500
            proteinMinimum = target?.proteinMinimumGrams ?? settings?.proteinMinimum ?? 150
        }
    }

    private func choose(_ workout: WorkoutTemplateRecord) {
        let anchor = anchors.first ?? CycleAnchorRecord(
            nextWorkoutTemplateID: workout.id,
            firstDueDomainDay: PersistedDomainDay.encode(DomainDay.containing(.now, calendar: .autoupdatingCurrent, cutoffMinutes: settings?.domainDayCutoffMinutes ?? 180))
        )
        anchor.nextWorkoutTemplateID = workout.id
        anchor.updatedAt = .now
        if anchors.isEmpty { modelContext.insert(anchor) }
        try? modelContext.save()
    }

    private func saveTarget() {
        guard let settings else { return }
        settings.calorieMinimum = calorieMinimum
        settings.calorieMaximum = calorieMaximum
        settings.proteinMinimum = proteinMinimum
        settings.updatedAt = .now
        if let target {
            target.calorieMinimum = calorieMinimum
            target.calorieMaximum = calorieMaximum
            target.proteinMinimumGrams = proteinMinimum
            target.updatedAt = .now
        }
        try? modelContext.save()
    }
}
