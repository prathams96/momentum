import Foundation
import SwiftData

@Model
final class AppSettingsRecord {
    var id: UUID = UUID()
    var createdAt: Date = Foundation.Date()
    var updatedAt: Date = Foundation.Date()
    var onboardingCompleted: Bool = false
    var domainDayCutoffMinutes: Int = 180
    var unitSystemRaw: String = "metric"
    var selectedAppearanceRaw: String = "system"
    var workoutNotificationMinutes: Int = 18 * 60 + 30
    var morningCareNotificationMinutes: Int = 9 * 60
    var hairCareNotificationMinutes: Int = 8 * 60
    var eveningCareNotificationMinutes: Int = 22 * 60
    var nutritionReminderMinutes: Int = 22 * 60
    var notificationAuthorizationRaw: String = "notDetermined"
    var notificationSchedulingStatusRaw: String = "unknown"
    var iCloudStatusRaw: String = "unknown"
    var iCloudStatusUpdatedAt: Date?
    var lastSuccessfulSyncAt: Date?
    var seedVersion: Int = 0
    var calorieTarget: Int = 2400
    var calorieMinimum: Int = 2300
    var calorieMaximum: Int = 2500
    var proteinMinimum: Int = 150

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        onboardingCompleted: Bool = false,
        domainDayCutoffMinutes: Int = 180,
        unitSystemRaw: String = "metric",
        selectedAppearanceRaw: String = "system",
        workoutNotificationMinutes: Int = 18 * 60 + 30,
        morningCareNotificationMinutes: Int = 9 * 60,
        hairCareNotificationMinutes: Int = 8 * 60,
        eveningCareNotificationMinutes: Int = 22 * 60,
        nutritionReminderMinutes: Int = 22 * 60,
        notificationAuthorizationRaw: String = "notDetermined",
        notificationSchedulingStatusRaw: String = "unknown",
        iCloudStatusRaw: String = "unknown",
        iCloudStatusUpdatedAt: Date? = nil,
        lastSuccessfulSyncAt: Date? = nil,
        seedVersion: Int = 0,
        calorieTarget: Int = 2400,
        calorieMinimum: Int = 2300,
        calorieMaximum: Int = 2500,
        proteinMinimum: Int = 150
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.onboardingCompleted = onboardingCompleted
        self.domainDayCutoffMinutes = domainDayCutoffMinutes
        self.unitSystemRaw = unitSystemRaw
        self.selectedAppearanceRaw = selectedAppearanceRaw
        self.workoutNotificationMinutes = workoutNotificationMinutes
        self.morningCareNotificationMinutes = morningCareNotificationMinutes
        self.hairCareNotificationMinutes = hairCareNotificationMinutes
        self.eveningCareNotificationMinutes = eveningCareNotificationMinutes
        self.nutritionReminderMinutes = nutritionReminderMinutes
        self.notificationAuthorizationRaw = notificationAuthorizationRaw
        self.notificationSchedulingStatusRaw = notificationSchedulingStatusRaw
        self.iCloudStatusRaw = iCloudStatusRaw
        self.iCloudStatusUpdatedAt = iCloudStatusUpdatedAt
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.seedVersion = seedVersion
        self.calorieTarget = calorieTarget
        self.calorieMinimum = calorieMinimum
        self.calorieMaximum = calorieMaximum
        self.proteinMinimum = proteinMinimum
    }
}

extension AppSettingsRecord {
    /// Selects the same settings record everywhere, including when CloudKit briefly
    /// presents duplicate singleton records during conflict resolution.
    static func canonical(in records: [AppSettingsRecord]) -> AppSettingsRecord? {
        records.max {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt < $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

@Model
final class NutritionTargetRecord {
    var id: UUID = UUID()
    var effectiveFrom: String = ""
    var effectiveTo: String?
    var calorieDisplayTarget: Int = 2400
    var calorieMinimum: Int = 2300
    var calorieMaximum: Int = 2500
    var proteinMinimumGrams: Int = 150
    var createdAt: Date = Foundation.Date()
    var updatedAt: Date = Foundation.Date()

    init(
        id: UUID = UUID(),
        effectiveFrom: String,
        effectiveTo: String? = nil,
        calorieDisplayTarget: Int = 2400,
        calorieMinimum: Int = 2300,
        calorieMaximum: Int = 2500,
        proteinMinimumGrams: Int = 150,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.effectiveFrom = effectiveFrom
        self.effectiveTo = effectiveTo
        self.calorieDisplayTarget = calorieDisplayTarget
        self.calorieMinimum = calorieMinimum
        self.calorieMaximum = calorieMaximum
        self.proteinMinimumGrams = proteinMinimumGrams
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class WorkoutTemplateRecord {
    var id: UUID = UUID()
    var name: String = ""
    var focus: String = ""
    var sequenceIndex: Int = 0
    var recoveryDaysAfter: Int = 0
    var isArchived: Bool = false
    var createdAt: Date = Foundation.Date()
    var updatedAt: Date = Foundation.Date()

    init(
        id: UUID = UUID(),
        name: String,
        focus: String = "",
        sequenceIndex: Int,
        recoveryDaysAfter: Int,
        isArchived: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.focus = focus
        self.sequenceIndex = sequenceIndex
        self.recoveryDaysAfter = recoveryDaysAfter
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class CycleAnchorRecord {
    var id: UUID = UUID()
    var nextWorkoutTemplateID: UUID = UUID()
    var firstDueDomainDay: String = ""
    var createdAt: Date = Foundation.Date()
    var updatedAt: Date = Foundation.Date()

    init(
        id: UUID = UUID(),
        nextWorkoutTemplateID: UUID,
        firstDueDomainDay: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.nextWorkoutTemplateID = nextWorkoutTemplateID
        self.firstDueDomainDay = firstDueDomainDay
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class ExercisePrescriptionRecord {
    var id: UUID = UUID()
    var workoutTemplateID: UUID = UUID()
    var displayName: String = ""
    var orderIndex: Int = 0
    var workingSetCount: Int = 1
    var repMinimum: Int = 1
    var repMaximum: Int = 1
    var repUnitRaw: String = "reps"
    var rirMinimum: Int?
    var rirMaximum: Int?
    var notes: String = ""
    var loadIncrementKg: Double = 1
    var workingWeightKg: Double = 0
    var isOptional: Bool = false
    var isArchived: Bool = false
    var createdAt: Date = Foundation.Date()
    var updatedAt: Date = Foundation.Date()

    init(
        id: UUID = UUID(),
        workoutTemplateID: UUID,
        displayName: String,
        orderIndex: Int,
        workingSetCount: Int,
        repMinimum: Int,
        repMaximum: Int,
        repUnitRaw: String = "reps",
        rirMinimum: Int? = nil,
        rirMaximum: Int? = nil,
        notes: String = "",
        loadIncrementKg: Double = 1,
        workingWeightKg: Double = 0,
        isOptional: Bool = false,
        isArchived: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.workoutTemplateID = workoutTemplateID
        self.displayName = displayName
        self.orderIndex = orderIndex
        self.workingSetCount = workingSetCount
        self.repMinimum = repMinimum
        self.repMaximum = repMaximum
        self.repUnitRaw = repUnitRaw
        self.rirMinimum = rirMinimum
        self.rirMaximum = rirMaximum
        self.notes = notes
        self.loadIncrementKg = loadIncrementKg
        self.workingWeightKg = workingWeightKg
        self.isOptional = isOptional
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class WorkoutSessionRecord {
    var id: UUID = UUID()
    var workoutTemplateID: UUID?
    var workoutNameSnapshot: String = ""
    var focusSnapshot: String = ""
    var sequenceIndexSnapshot: Int = 0
    var recoveryDaysAfterSnapshot: Int = 0
    var nextWorkoutTemplateIDSnapshot: UUID?
    var scheduledDomainDay: String = ""
    var startedAt: Date = Foundation.Date()
    var finishedAt: Date?
    var completionDomainDay: String?
    var startedEarly: Bool = false
    var note: String = ""
    var postWorkoutEnergyRaw: String?
    var postWorkoutSorenessRaw: String?
    var postWorkoutNote: String?
    var createdAt: Date = Foundation.Date()
    var updatedAt: Date = Foundation.Date()
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        workoutTemplateID: UUID? = nil,
        workoutNameSnapshot: String,
        focusSnapshot: String = "",
        sequenceIndexSnapshot: Int = 0,
        recoveryDaysAfterSnapshot: Int = 0,
        nextWorkoutTemplateIDSnapshot: UUID? = nil,
        scheduledDomainDay: String,
        startedAt: Date = .now,
        finishedAt: Date? = nil,
        completionDomainDay: String? = nil,
        startedEarly: Bool = false,
        note: String = "",
        postWorkoutEnergyRaw: String? = nil,
        postWorkoutSorenessRaw: String? = nil,
        postWorkoutNote: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.workoutTemplateID = workoutTemplateID
        self.workoutNameSnapshot = workoutNameSnapshot
        self.focusSnapshot = focusSnapshot
        self.sequenceIndexSnapshot = sequenceIndexSnapshot
        self.recoveryDaysAfterSnapshot = recoveryDaysAfterSnapshot
        self.nextWorkoutTemplateIDSnapshot = nextWorkoutTemplateIDSnapshot
        self.scheduledDomainDay = scheduledDomainDay
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.completionDomainDay = completionDomainDay
        self.startedEarly = startedEarly
        self.note = note
        self.postWorkoutEnergyRaw = postWorkoutEnergyRaw
        self.postWorkoutSorenessRaw = postWorkoutSorenessRaw
        self.postWorkoutNote = postWorkoutNote
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

@Model
final class ExerciseLogRecord {
    var id: UUID = UUID()
    var workoutSessionID: UUID = UUID()
    var prescriptionID: UUID?
    var exerciseNameSnapshot: String = ""
    var orderIndex: Int = 0
    var setCountSnapshot: Int = 0
    var repMinimumSnapshot: Int = 0
    var repMaximumSnapshot: Int = 0
    var repUnitSnapshot: String = "reps"
    var notesSnapshot: String = ""
    var statusRaw: String = "pending"
    var createdAt: Date = Foundation.Date()
    var updatedAt: Date = Foundation.Date()

    init(
        id: UUID = UUID(),
        workoutSessionID: UUID,
        prescriptionID: UUID? = nil,
        exerciseNameSnapshot: String,
        orderIndex: Int,
        setCountSnapshot: Int,
        repMinimumSnapshot: Int,
        repMaximumSnapshot: Int,
        repUnitSnapshot: String = "reps",
        notesSnapshot: String = "",
        statusRaw: String = "pending",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.workoutSessionID = workoutSessionID
        self.prescriptionID = prescriptionID
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.orderIndex = orderIndex
        self.setCountSnapshot = setCountSnapshot
        self.repMinimumSnapshot = repMinimumSnapshot
        self.repMaximumSnapshot = repMaximumSnapshot
        self.repUnitSnapshot = repUnitSnapshot
        self.notesSnapshot = notesSnapshot
        self.statusRaw = statusRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class SetLogRecord {
    var id: UUID = UUID()
    var exerciseLogID: UUID = UUID()
    var setNumber: Int = 1
    var weightKg: Double = 0
    var repetitions: Int = 0
    var rir: Int?
    var statusRaw: String = "pending"
    var note: String = ""
    var createdAt: Date = Foundation.Date()
    var updatedAt: Date = Foundation.Date()

    init(
        id: UUID = UUID(),
        exerciseLogID: UUID,
        setNumber: Int,
        weightKg: Double = 0,
        repetitions: Int = 0,
        rir: Int? = nil,
        statusRaw: String = "pending",
        note: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.exerciseLogID = exerciseLogID
        self.setNumber = setNumber
        self.weightKg = weightKg
        self.repetitions = repetitions
        self.rir = rir
        self.statusRaw = statusRaw
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class WorkoutDayEventRecord {
    var id: UUID = UUID()
    var domainDay: String = ""
    var dueWorkoutTemplateID: UUID = UUID()
    var kindRaw: String = "missed"
    var createdAt: Date = Foundation.Date()
    var updatedAt: Date = Foundation.Date()
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        domainDay: String,
        dueWorkoutTemplateID: UUID,
        kindRaw: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.domainDay = domainDay
        self.dueWorkoutTemplateID = dueWorkoutTemplateID
        self.kindRaw = kindRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

@Model
final class LoadSuggestionRecord {
    var id: UUID = UUID()
    var prescriptionID: UUID = UUID()
    var sourceSessionID: UUID = UUID()
    var suggestedWeightKg: Double = 0
    var statusRaw: String = "pending"
    var createdAt: Date = Foundation.Date()
    var updatedAt: Date = Foundation.Date()
    var resolvedAt: Date?

    init(
        id: UUID = UUID(),
        prescriptionID: UUID,
        sourceSessionID: UUID,
        suggestedWeightKg: Double,
        statusRaw: String = "pending",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.prescriptionID = prescriptionID
        self.sourceSessionID = sourceSessionID
        self.suggestedWeightKg = suggestedWeightKg
        self.statusRaw = statusRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.resolvedAt = resolvedAt
    }
}

@Model
final class FoodPresetRecord {
    var id: UUID = UUID()
    var name: String = ""
    var caloriesPerBaseServing: Double = 0
    var proteinGramsPerBaseServing: Double = 0
    var isFavorite: Bool = false
    var lastUsedAt: Date?
    var createdAt: Date = Foundation.Date()
    var updatedAt: Date = Foundation.Date()
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        caloriesPerBaseServing: Double,
        proteinGramsPerBaseServing: Double,
        isFavorite: Bool = false,
        lastUsedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.caloriesPerBaseServing = caloriesPerBaseServing
        self.proteinGramsPerBaseServing = proteinGramsPerBaseServing
        self.isFavorite = isFavorite
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

@Model
final class FoodEntryRecord {
    var id: UUID = UUID()
    var domainDay: String = ""
    var consumedAt: Date = Foundation.Date()
    var presetID: UUID?
    var nameSnapshot: String = ""
    var caloriesPerBaseServing: Double = 0
    var proteinPerBaseServing: Double = 0
    var servingMultiplier: Double = 1
    var totalCalories: Double = 0
    var totalProteinGrams: Double = 0
    var createdAt: Date = Foundation.Date()
    var updatedAt: Date = Foundation.Date()
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        domainDay: String,
        consumedAt: Date = .now,
        presetID: UUID? = nil,
        nameSnapshot: String,
        caloriesPerBaseServing: Double,
        proteinPerBaseServing: Double,
        servingMultiplier: Double = 1,
        totalCalories: Double? = nil,
        totalProteinGrams: Double? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.domainDay = domainDay
        self.consumedAt = consumedAt
        self.presetID = presetID
        self.nameSnapshot = nameSnapshot
        self.caloriesPerBaseServing = caloriesPerBaseServing
        self.proteinPerBaseServing = proteinPerBaseServing
        self.servingMultiplier = servingMultiplier
        self.totalCalories = totalCalories ?? caloriesPerBaseServing * servingMultiplier
        self.totalProteinGrams = totalProteinGrams ?? proteinPerBaseServing * servingMultiplier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    func recomputeTotals() {
        totalCalories = caloriesPerBaseServing * servingMultiplier
        totalProteinGrams = proteinPerBaseServing * servingMultiplier
        updatedAt = .now
    }
}

@Model
final class NutritionDayRecord {
    var id: UUID = UUID()
    var domainDay: String = ""
    var finalizedAt: Date?
    var calorieDisplayTargetSnapshot: Int = 2400
    var calorieMinimumSnapshot: Int = 2300
    var calorieMaximumSnapshot: Int = 2500
    var proteinMinimumSnapshot: Int = 150
    var createdAt: Date = Foundation.Date()
    var updatedAt: Date = Foundation.Date()

    init(
        id: UUID = UUID(),
        domainDay: String,
        finalizedAt: Date? = nil,
        calorieDisplayTargetSnapshot: Int = 2400,
        calorieMinimumSnapshot: Int = 2300,
        calorieMaximumSnapshot: Int = 2500,
        proteinMinimumSnapshot: Int = 150,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.domainDay = domainDay
        self.finalizedAt = finalizedAt
        self.calorieDisplayTargetSnapshot = calorieDisplayTargetSnapshot
        self.calorieMinimumSnapshot = calorieMinimumSnapshot
        self.calorieMaximumSnapshot = calorieMaximumSnapshot
        self.proteinMinimumSnapshot = proteinMinimumSnapshot
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class ExerciseAlternativeRecord {
    var id: UUID = UUID()
    var prescriptionID: UUID = UUID()
    var displayName: String = ""
    var orderIndex: Int = 0
    var isPreferred: Bool = false
    var createdAt: Date = Foundation.Date()
    var updatedAt: Date = Foundation.Date()

    init(
        id: UUID = UUID(),
        prescriptionID: UUID,
        displayName: String,
        orderIndex: Int,
        isPreferred: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.prescriptionID = prescriptionID
        self.displayName = displayName
        self.orderIndex = orderIndex
        self.isPreferred = isPreferred
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class CareRoutineTemplateRecord {
    var id: UUID = UUID()
    var name: String = ""
    var routineRoleRaw: String = "custom"
    var categoryRaw: String = "personalCare"
    var recurrenceKindRaw: String = "weekdaySet"
    var recurrencePayload: String = ""
    var notificationMinutes: Int = 0
    var rollsForwardWhenMissed: Bool = false
    var isArchived: Bool = false
    var createdAt: Date = Foundation.Date()
    var updatedAt: Date = Foundation.Date()

    init(
        id: UUID = UUID(),
        name: String,
        routineRoleRaw: String = "custom",
        categoryRaw: String = "personalCare",
        recurrenceKindRaw: String = "weekdaySet",
        recurrencePayload: String,
        notificationMinutes: Int,
        rollsForwardWhenMissed: Bool = false,
        isArchived: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.routineRoleRaw = routineRoleRaw
        self.categoryRaw = categoryRaw
        self.recurrenceKindRaw = recurrenceKindRaw
        self.recurrencePayload = recurrencePayload
        self.notificationMinutes = notificationMinutes
        self.rollsForwardWhenMissed = rollsForwardWhenMissed
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class CareTaskTemplateRecord {
    var id: UUID = UUID()
    var routineTemplateID: UUID = UUID()
    var label: String = ""
    var genericProductRole: String?
    var activeIngredient: String?
    var instruction: String?
    var orderIndex: Int = 0
    var requirementKindRaw: String = "required"
    var conditionGroup: String?
    var isArchived: Bool = false
    var createdAt: Date = Foundation.Date()
    var updatedAt: Date = Foundation.Date()

    init(
        id: UUID = UUID(),
        routineTemplateID: UUID,
        label: String,
        genericProductRole: String? = nil,
        activeIngredient: String? = nil,
        instruction: String? = nil,
        orderIndex: Int,
        requirementKindRaw: String = "required",
        conditionGroup: String? = nil,
        isArchived: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.routineTemplateID = routineTemplateID
        self.label = label
        self.genericProductRole = genericProductRole
        self.activeIngredient = activeIngredient
        self.instruction = instruction
        self.orderIndex = orderIndex
        self.requirementKindRaw = requirementKindRaw
        self.conditionGroup = conditionGroup
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class CareOccurrenceRecord {
    var id: UUID = UUID()
    var routineTemplateID: UUID?
    var routineNameSnapshot: String = ""
    var routineRoleRaw: String = "custom"
    var sourceWorkoutSessionID: UUID?
    var dueDomainDay: String = ""
    var dueAt: Date = Foundation.Date()
    var statusRaw: String = "pending"
    var completedAt: Date?
    var skippedAt: Date?
    var rolledFromDomainDay: String?
    var recurrencePayloadBeforeCompletion: String?
    var createdAt: Date = Foundation.Date()
    var updatedAt: Date = Foundation.Date()

    init(
        id: UUID = UUID(),
        routineTemplateID: UUID? = nil,
        routineNameSnapshot: String,
        routineRoleRaw: String = "custom",
        sourceWorkoutSessionID: UUID? = nil,
        dueDomainDay: String,
        dueAt: Date,
        statusRaw: String = "pending",
        completedAt: Date? = nil,
        skippedAt: Date? = nil,
        rolledFromDomainDay: String? = nil,
        recurrencePayloadBeforeCompletion: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.routineTemplateID = routineTemplateID
        self.routineNameSnapshot = routineNameSnapshot
        self.routineRoleRaw = routineRoleRaw
        self.sourceWorkoutSessionID = sourceWorkoutSessionID
        self.dueDomainDay = dueDomainDay
        self.dueAt = dueAt
        self.statusRaw = statusRaw
        self.completedAt = completedAt
        self.skippedAt = skippedAt
        self.rolledFromDomainDay = rolledFromDomainDay
        self.recurrencePayloadBeforeCompletion = recurrencePayloadBeforeCompletion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class CareTaskCompletionRecord {
    var id: UUID = UUID()
    var occurrenceID: UUID = UUID()
    var taskTemplateID: UUID?
    var labelSnapshot: String = ""
    var instructionSnapshot: String?
    var statusRaw: String = "pending"
    var selectedVariant: String?
    var completedAt: Date?
    var createdAt: Date = Foundation.Date()
    var updatedAt: Date = Foundation.Date()

    init(
        id: UUID = UUID(),
        occurrenceID: UUID,
        taskTemplateID: UUID? = nil,
        labelSnapshot: String,
        instructionSnapshot: String? = nil,
        statusRaw: String = "pending",
        selectedVariant: String? = nil,
        completedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.occurrenceID = occurrenceID
        self.taskTemplateID = taskTemplateID
        self.labelSnapshot = labelSnapshot
        self.instructionSnapshot = instructionSnapshot
        self.statusRaw = statusRaw
        self.selectedVariant = selectedVariant
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class BodyMeasurementRecord {
    var id: UUID = UUID()
    var kindRaw: String = "weightKg"
    var value: Double = 0
    var measuredAt: Date = Foundation.Date()
    var domainDay: String = ""
    var sourceRaw: String = "manual"
    var createdAt: Date = Foundation.Date()
    var updatedAt: Date = Foundation.Date()
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        kindRaw: String,
        value: Double,
        measuredAt: Date = .now,
        domainDay: String,
        sourceRaw: String = "manual",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.value = value
        self.measuredAt = measuredAt
        self.domainDay = domainDay
        self.sourceRaw = sourceRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

@Model
final class MilestoneRecord {
    var id: UUID = UUID()
    var kindRaw: String = "unknown"
    var threshold: Double?
    var relatedEntityID: UUID?
    var earnedAt: Date = Foundation.Date()
    var acknowledgedAt: Date?
    var createdAt: Date = Foundation.Date()
    var updatedAt: Date = Foundation.Date()

    init(
        id: UUID = UUID(),
        kindRaw: String,
        threshold: Double? = nil,
        relatedEntityID: UUID? = nil,
        earnedAt: Date = .now,
        acknowledgedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.threshold = threshold
        self.relatedEntityID = relatedEntityID
        self.earnedAt = earnedAt
        self.acknowledgedAt = acknowledgedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
