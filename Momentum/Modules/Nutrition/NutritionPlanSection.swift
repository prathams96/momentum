import MomentumCore
import SwiftData
import SwiftUI

/// The nutrition module's contribution to the Plans surface: the
/// effective-dated Nutrition Target editor.
struct NutritionPlanSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRecords: [AppSettingsRecord]
    @Query private var nutritionTargets: [NutritionTargetRecord]
    @State private var calorieDisplayTarget = 2_400
    @State private var calorieMinimum = 2_300
    @State private var calorieMaximum = 2_500
    @State private var proteinMinimum = 150
    @State private var saveError: String?
    @State private var loadedTargetID: UUID?

    private var currentDomainDay: DomainDay {
        DomainDay.containing(
            .now,
            calendar: .autoupdatingCurrent,
            cutoffMinutes: AppSettingsRecord.canonical(in: settingsRecords)?.domainDayCutoffMinutes ?? 180
        )
    }

    var body: some View {
        Section {
            Stepper("Display target: \(calorieDisplayTarget) kcal", value: $calorieDisplayTarget, in: 0...10_000, step: 50)
            Stepper("Minimum calories: \(calorieMinimum)", value: $calorieMinimum, in: 0...calorieMaximum, step: 50)
            Stepper("Maximum calories: \(calorieMaximum)", value: $calorieMaximum, in: calorieMinimum...10_000, step: 50)
            Stepper("Minimum protein: \(proteinMinimum) g", value: $proteinMinimum, in: 0...500, step: 5)
            Button("Save target from today") { saveNutritionTarget() }
                .buttonStyle(.borderedProminent)
                .disabled(calorieDisplayTarget < calorieMinimum || calorieDisplayTarget > calorieMaximum)
        } header: {
            Text("Nutrition target")
        } footer: {
            Text("A new effective-dated target starts today. Finalized days retain their historical snapshots.")
        }
        .onAppear { loadTarget() }
        .alert("Couldn’t save plan", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "Your existing plan is unchanged.")
        }
    }

    private func loadTarget() {
        let today = currentDomainDay
        guard let target = NutritionPlanService.target(for: today, in: nutritionTargets),
              loadedTargetID != target.id else { return }
        calorieDisplayTarget = target.calorieDisplayTarget
        calorieMinimum = target.calorieMinimum
        calorieMaximum = target.calorieMaximum
        proteinMinimum = target.proteinMinimumGrams
        loadedTargetID = target.id
    }

    private func saveNutritionTarget() {
        do {
            try NutritionPlanService.saveTarget(
                effectiveFrom: currentDomainDay,
                displayTarget: calorieDisplayTarget,
                calorieMinimum: calorieMinimum,
                calorieMaximum: calorieMaximum,
                proteinMinimum: proteinMinimum,
                in: modelContext
            )
            loadedTargetID = NutritionPlanService.target(for: currentDomainDay, in: nutritionTargets)?.id
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription ?? "The nutrition target was not saved."
        }
    }
}
