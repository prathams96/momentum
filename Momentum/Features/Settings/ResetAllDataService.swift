import SwiftData

@MainActor
enum ResetAllDataService {
    static let confirmationPhrase = "RESET ALL DATA"

    static func reset(context: ModelContext) throws {
        do {
            try delete(AppSettingsRecord.self, from: context)
            try delete(NutritionTargetRecord.self, from: context)
            try delete(WorkoutTemplateRecord.self, from: context)
            try delete(CycleAnchorRecord.self, from: context)
            try delete(ExercisePrescriptionRecord.self, from: context)
            try delete(ExerciseAlternativeRecord.self, from: context)
            try delete(WorkoutSessionRecord.self, from: context)
            try delete(ExerciseLogRecord.self, from: context)
            try delete(SetLogRecord.self, from: context)
            try delete(WorkoutDayEventRecord.self, from: context)
            try delete(LoadSuggestionRecord.self, from: context)
            try delete(FoodPresetRecord.self, from: context)
            try delete(FoodEntryRecord.self, from: context)
            try delete(NutritionDayRecord.self, from: context)
            try delete(CareRoutineTemplateRecord.self, from: context)
            try delete(CareTaskTemplateRecord.self, from: context)
            try delete(CareOccurrenceRecord.self, from: context)
            try delete(CareTaskCompletionRecord.self, from: context)
            try delete(BodyMeasurementRecord.self, from: context)
            try delete(MilestoneRecord.self, from: context)
            try delete(HydrationPlanRecord.self, from: context)
            try delete(HydrationEntryRecord.self, from: context)
            try delete(HydrationDayRecord.self, from: context)
            try delete(ModuleFactRecord.self, from: context)
            try delete(ModuleActivationIntervalRecord.self, from: context)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func delete<T: PersistentModel>(_ type: T.Type, from context: ModelContext) throws {
        for record in try context.fetch(FetchDescriptor<T>()) {
            context.delete(record)
        }
    }
}
