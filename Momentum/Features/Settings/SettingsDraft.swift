import Foundation
import SwiftUI

struct SettingsDraft: Equatable {
    var domainDayCutoffMinutes: Int
    var unitSystemRaw: String
    var selectedAppearanceRaw: String
    var workoutNotificationMinutes: Int
    var nutritionReminderMinutes: Int
    var routineReminders: [RoutineReminderDraft]

    @MainActor
    init(settings: AppSettingsRecord, routines: [CareRoutineTemplateRecord]) {
        domainDayCutoffMinutes = min(max(settings.domainDayCutoffMinutes, 0), 12 * 60)
        unitSystemRaw = UnitSystemOption(rawValue: settings.unitSystemRaw)?.rawValue ?? UnitSystemOption.metric.rawValue
        selectedAppearanceRaw = AppearanceOption(rawValue: settings.selectedAppearanceRaw)?.rawValue ?? AppearanceOption.system.rawValue
        workoutNotificationMinutes = Self.validMinutes(settings.workoutNotificationMinutes)
        nutritionReminderMinutes = Self.validMinutes(settings.nutritionReminderMinutes)
        routineReminders = routines
            .filter { !$0.isArchived }
            .map { RoutineReminderDraft(id: $0.id, name: $0.name, minutes: Self.validMinutes($0.notificationMinutes)) }
            .sorted { ($0.minutes, $0.name, $0.id.uuidString) < ($1.minutes, $1.name, $1.id.uuidString) }
    }

    static let fallback = SettingsDraft(
        domainDayCutoffMinutes: 180,
        unitSystemRaw: "metric",
        selectedAppearanceRaw: "system",
        workoutNotificationMinutes: 18 * 60 + 30,
        nutritionReminderMinutes: 22 * 60,
        routineReminders: []
    )

    init(
        domainDayCutoffMinutes: Int,
        unitSystemRaw: String,
        selectedAppearanceRaw: String,
        workoutNotificationMinutes: Int,
        nutritionReminderMinutes: Int,
        routineReminders: [RoutineReminderDraft]
    ) {
        self.domainDayCutoffMinutes = domainDayCutoffMinutes
        self.unitSystemRaw = unitSystemRaw
        self.selectedAppearanceRaw = selectedAppearanceRaw
        self.workoutNotificationMinutes = workoutNotificationMinutes
        self.nutritionReminderMinutes = nutritionReminderMinutes
        self.routineReminders = routineReminders
    }

    @MainActor
    func apply(to settings: AppSettingsRecord, routines: [CareRoutineTemplateRecord], now: Date = .now) {
        settings.domainDayCutoffMinutes = domainDayCutoffMinutes
        settings.unitSystemRaw = unitSystemRaw
        settings.selectedAppearanceRaw = selectedAppearanceRaw
        settings.workoutNotificationMinutes = workoutNotificationMinutes
        settings.nutritionReminderMinutes = nutritionReminderMinutes
        settings.updatedAt = now

        let minutesByID = Dictionary(uniqueKeysWithValues: routineReminders.map { ($0.id, $0.minutes) })
        for routine in routines {
            guard let minutes = minutesByID[routine.id] else { continue }
            routine.notificationMinutes = minutes
            routine.updatedAt = now

            switch routine.name {
            case "Hair care": settings.hairCareNotificationMinutes = minutes
            case "Morning care": settings.morningCareNotificationMinutes = minutes
            case let name where name.hasPrefix("Night care"):
                settings.eveningCareNotificationMinutes = minutes
            default: break
            }
        }
    }

    private static func validMinutes(_ minutes: Int) -> Int {
        min(max(minutes, 0), 23 * 60 + 59)
    }
}

struct RoutineReminderDraft: Identifiable, Equatable {
    let id: UUID
    let name: String
    var minutes: Int
}

enum UnitSystemOption: String, CaseIterable, Identifiable {
    case metric
    case imperial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metric: "Kilograms and centimetres"
        case .imperial: "Pounds and inches"
        }
    }
}

enum AppearanceOption: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

enum AppearanceResolver {
    static func colorScheme(for rawValue: String) -> ColorScheme? {
        switch AppearanceOption(rawValue: rawValue) ?? .system {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
