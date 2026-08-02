import SwiftData
import SwiftUI

struct FoodEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var entries: [FoodEntryRecord]
    @Query private var presets: [FoodPresetRecord]

    @State private var name = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var multiplier = "1"
    @State private var isFavorite = false
    @State private var validationMessage: String?
    @State private var saveError: String?

    private let domainDay: String
    private let existingEntryID: UUID?

    init(domainDay: String, existingEntryID: UUID? = nil) {
        self.domainDay = domainDay
        self.existingEntryID = existingEntryID
    }

    private var existingEntry: FoodEntryRecord? {
        entries.first { $0.id == existingEntryID }
    }

    private var recentPresets: [FoodPresetRecord] {
        presets
            .filter { $0.deletedAt == nil }
            .sorted {
                if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
                return ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast)
            }
    }

    var body: some View {
        NavigationStack {
            Form {
                if !recentPresets.isEmpty {
                    Section("Recent and favorites") {
                        ForEach(recentPresets.prefix(8)) { preset in
                            Button {
                                apply(preset)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(preset.name)
                                            .foregroundStyle(.primary)
                                        Text("\(preset.caloriesPerBaseServing.formatted()) kcal · \(preset.proteinGramsPerBaseServing.formatted()) g protein")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if preset.isFavorite {
                                        Image(systemName: "star.fill")
                                            .foregroundStyle(MomentumTheme.pulse)
                                            .accessibilityLabel("Favorite")
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Food") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.sentences)
                    TextField("Calories per serving", text: $calories)
                        .keyboardType(.numberPad)
                    TextField("Protein per serving (g)", text: $protein)
                        .keyboardType(.decimalPad)
                    TextField("Serving multiplier", text: $multiplier)
                        .keyboardType(.decimalPad)
                    Toggle("Save as favorite", isOn: $isFavorite)
                }

                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }

                if let total = calculatedTotal {
                    Section("Entry total") {
                        LabeledContent("Calories", value: "\(total.calories.formatted()) kcal")
                        LabeledContent("Protein", value: "\(total.protein.formatted()) g")
                    }
                }
            }
            .navigationTitle(existingEntryID == nil ? "Log food" : "Edit food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear(perform: populateExistingEntry)
        .interactiveDismissDisabled(saveError != nil)
        .alert("Couldn’t save food", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("Retry") { save() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text(saveError ?? "Your entry is still on screen.")
        }
    }

    private var calculatedTotal: (calories: Double, protein: Double)? {
        guard
            let calorieValue = Double(calories),
            let proteinValue = Double(protein),
            let multiplierValue = Double(multiplier),
            calorieValue >= 0,
            proteinValue >= 0,
            multiplierValue > 0
        else { return nil }

        return (calorieValue * multiplierValue, proteinValue * multiplierValue)
    }

    private func apply(_ preset: FoodPresetRecord) {
        name = preset.name
        calories = preset.caloriesPerBaseServing.formatted()
        protein = preset.proteinGramsPerBaseServing.formatted()
        multiplier = "1"
        isFavorite = preset.isFavorite
    }

    private func populateExistingEntry() {
        guard name.isEmpty, let entry = existingEntry else { return }
        name = entry.nameSnapshot
        calories = entry.caloriesPerBaseServing.formatted()
        protein = entry.proteinPerBaseServing.formatted()
        multiplier = entry.servingMultiplier.formatted()
        isFavorite = entry.presetID.flatMap { id in presets.first { $0.id == id } }?.isFavorite ?? false
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = "Enter a food name."
            return
        }
        guard let calorieValue = Int(calories), calorieValue >= 0 else {
            validationMessage = "Calories must be a nonnegative whole number."
            return
        }
        guard let proteinValue = Double(protein), proteinValue >= 0 else {
            validationMessage = "Protein must be a nonnegative number."
            return
        }
        guard let multiplierValue = Double(multiplier), multiplierValue > 0 else {
            validationMessage = "Serving multiplier must be greater than zero."
            return
        }
        validationMessage = nil

        let existingPreset = presets.first {
            $0.deletedAt == nil && $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
        }
        let preset = existingPreset ?? FoodPresetRecord(
            name: trimmedName,
            caloriesPerBaseServing: Double(calorieValue),
            proteinGramsPerBaseServing: proteinValue
        )
        if existingPreset == nil {
            modelContext.insert(preset)
        }
        preset.name = trimmedName
        preset.caloriesPerBaseServing = Double(calorieValue)
        preset.proteinGramsPerBaseServing = proteinValue
        preset.isFavorite = isFavorite
        preset.lastUsedAt = .now
        preset.updatedAt = .now

        let priorEntry = existingEntry
        let entry = priorEntry ?? FoodEntryRecord(
            domainDay: domainDay,
            presetID: preset.id,
            nameSnapshot: trimmedName,
            caloriesPerBaseServing: Double(calorieValue),
            proteinPerBaseServing: proteinValue,
            servingMultiplier: multiplierValue,
            totalCalories: Double(calorieValue) * multiplierValue,
            totalProteinGrams: proteinValue * multiplierValue
        )
        if priorEntry == nil {
            modelContext.insert(entry)
        }
        entry.domainDay = domainDay
        entry.presetID = preset.id
        entry.nameSnapshot = trimmedName
        entry.caloriesPerBaseServing = Double(calorieValue)
        entry.proteinPerBaseServing = proteinValue
        entry.servingMultiplier = multiplierValue
        entry.recomputeTotals()

        do {
            try modelContext.save()
            Task { try? await DailyReconciler.reconcileAndNotify(in: modelContext) }
            dismiss()
        } catch {
            saveError = "Your food entry was kept. Try saving again."
        }
    }
}
