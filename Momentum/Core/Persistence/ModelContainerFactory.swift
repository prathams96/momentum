import Foundation
import SwiftData

enum PersistenceStoreMode: Equatable {
    case production
    case localDevelopment
    case preview
}

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

    static func makeLocalDevelopment(at url: URL? = nil) throws -> ModelContainer {
        let storeURL = try url ?? localStoreURL()
        let configuration = ModelConfiguration(
            "Momentum Local",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func makePreview() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "Momentum Preview",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func localStoreURL() throws -> URL {
        let fileManager = FileManager.default
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw PersistenceStoreError.applicationSupportUnavailable
        }

        let directory = applicationSupport.appendingPathComponent("Momentum", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("Momentum.store")
    }
}

enum PersistenceStoreError: LocalizedError {
    case applicationSupportUnavailable

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            "Momentum could not locate its local application storage."
        }
    }
}
