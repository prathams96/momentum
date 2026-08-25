import Foundation
import MomentumCore
import SwiftData

extension NutritionModuleAdapter: ReminderCandidateProviding {
    func reminderCandidates(in context: ModuleContext) -> [ScheduledReminder] {
        let nutritionDays = (try? context.modelContext.fetch(FetchDescriptor<NutritionDayRecord>())) ?? []
        let domainDay = PersistedDomainDay.encode(context.currentDomainDay)
        let todayRecord = nutritionDays.first { $0.domainDay == domainDay }
        guard todayRecord?.finalizedAt == nil,
              let date = Self.reminderDate(
                for: context.currentDomainDay,
                minutes: context.nutritionReminderMinutes,
                now: context.now,
                calendar: context.calendar
              ) else {
            return []
        }
        return [ScheduledReminder(
            identifier: "nutrition.checkin.\(domainDay)",
            title: "Evening check-in",
            body: "Finish logging today’s food.",
            categoryIdentifier: MomentumNotificationCategory.eveningCheckIn,
            dateComponents: context.calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: date
            ),
            userInfo: [
                "kind": "eveningCheckIn",
                "domainDay": domainDay
            ]
        )]
    }

    private static func reminderDate(
        for day: DomainDay,
        minutes: Int,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let candidate = PersistedDomainDay.date(
            for: day,
            calendar: calendar,
            hour: minutes / 60,
            minute: minutes % 60
        )
        return candidate.flatMap { $0 > now ? $0 : nil }
    }
}
