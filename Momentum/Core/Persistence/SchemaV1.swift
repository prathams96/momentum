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

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        onboardingCompleted: Bool = false,
        domainDayCutoffMinutes: Int = 180,
        unitSystemRaw: String = "metric"
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.onboardingCompleted = onboardingCompleted
        self.domainDayCutoffMinutes = domainDayCutoffMinutes
        self.unitSystemRaw = unitSystemRaw
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
