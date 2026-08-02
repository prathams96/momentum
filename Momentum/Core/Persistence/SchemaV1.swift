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
        self.seedVersion = seedVersion
        self.calorieTarget = calorieTarget
        self.calorieMinimum = calorieMinimum
        self.calorieMaximum = calorieMaximum
        self.proteinMinimum = proteinMinimum
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
    var notes: String = ""
    var loadIncrementKg: Double = 1
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
        notes: String = "",
        loadIncrementKg: Double = 1,
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
        self.notes = notes
        self.loadIncrementKg = loadIncrementKg
        self.isOptional = isOptional
        self.isArchived = isArchived
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
