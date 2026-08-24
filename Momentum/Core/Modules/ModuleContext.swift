import Foundation
import MomentumCore
import SwiftData

/// Everything a module may touch: one model context, the resolved day
/// boundary, and global preferences. Modules must not fetch settings
/// records themselves; preferences are projected here once.
@MainActor
struct ModuleContext {
    let modelContext: ModelContext
    let calendar: Calendar
    let now: Date
    let domainDayCutoffMinutes: Int
    let unitSystemRaw: String
    let currentDomainDay: DomainDay
    let previousDomainDay: DomainDay

    init(
        modelContext: ModelContext,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now,
        domainDayCutoffMinutes: Int = 180,
        unitSystemRaw: String = "metric"
    ) {
        self.modelContext = modelContext
        self.calendar = calendar
        self.now = now
        self.domainDayCutoffMinutes = domainDayCutoffMinutes
        self.unitSystemRaw = unitSystemRaw
        self.currentDomainDay = DomainDay.containing(
            now,
            calendar: calendar,
            cutoffMinutes: domainDayCutoffMinutes
        )
        self.previousDomainDay = DomainDay.containing(
            now,
            calendar: calendar,
            cutoffMinutes: domainDayCutoffMinutes
        ).adding(days: -1, calendar: calendar)
    }

    static func make(
        in modelContext: ModelContext,
        settings: AppSettingsRecord?,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> ModuleContext {
        ModuleContext(
            modelContext: modelContext,
            calendar: calendar,
            now: now,
            domainDayCutoffMinutes: settings?.domainDayCutoffMinutes ?? 180,
            unitSystemRaw: settings?.unitSystemRaw ?? "metric"
        )
    }
}
