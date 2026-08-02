import SwiftData

enum ModelContainerFactory {
    static let cloudContainerIdentifier = "iCloud.com.pratham.momentum"

    static let schema = Schema([
        AppSettingsRecord.self,
        WorkoutTemplateRecord.self,
        CycleAnchorRecord.self,
        ExercisePrescriptionRecord.self,
        ExerciseAlternativeRecord.self,
        CareRoutineTemplateRecord.self,
        CareTaskTemplateRecord.self
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
