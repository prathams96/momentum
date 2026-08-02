import SwiftData

enum ModelContainerFactory {
    static let cloudContainerIdentifier = "iCloud.com.pratham.momentum"

    static let schema = Schema([
        AppSettingsRecord.self,
        NutritionTargetRecord.self,
        WorkoutTemplateRecord.self,
        CycleAnchorRecord.self,
        ExercisePrescriptionRecord.self,
        ExerciseAlternativeRecord.self,
        WorkoutSessionRecord.self,
        ExerciseLogRecord.self,
        SetLogRecord.self,
        WorkoutDayEventRecord.self,
        LoadSuggestionRecord.self,
        FoodPresetRecord.self,
        FoodEntryRecord.self,
        NutritionDayRecord.self,
        CareRoutineTemplateRecord.self,
        CareTaskTemplateRecord.self,
        CareOccurrenceRecord.self,
        CareTaskCompletionRecord.self,
        BodyMeasurementRecord.self,
        MilestoneRecord.self
    ])

    static func makeProduction() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "Momentum",
            schema: schema,
            cloudKitDatabase: .private(cloudContainerIdentifier)
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func makePreview() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "Momentum Preview",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
