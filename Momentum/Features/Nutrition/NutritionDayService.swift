import Foundation
import MomentumCore
import SwiftData

@MainActor
enum NutritionDayService {
    static func target(
        for day: DomainDay,
        targets: [NutritionTargetRecord]
    ) -> NutritionTargetRecord? {
        let value = PersistedDomainDay.encode(day)
        return targets
            .filter { target in
                target.effectiveFrom <= value &&
                (target.effectiveTo == nil || target.effectiveTo! >= value)
            }
            .sorted { ($0.effectiveFrom, $0.updatedAt, $0.id.uuidString) < ($1.effectiveFrom, $1.updatedAt, $1.id.uuidString) }
            .last
    }

    static func day(
        for domainDay: DomainDay,
        in days: [NutritionDayRecord]
    ) -> NutritionDayRecord? {
        let value = PersistedDomainDay.encode(domainDay)
        return days
            .filter { $0.domainDay == value }
            .max { ($0.updatedAt, $0.id.uuidString) < ($1.updatedAt, $1.id.uuidString) }
    }

    static func finalize(
        domainDay: DomainDay,
        target: NutritionTargetRecord?,
        existing: NutritionDayRecord?,
        context: ModelContext,
        now: Date = .now
    ) throws {
        let record = existing ?? NutritionDayRecord(domainDay: PersistedDomainDay.encode(domainDay))
        if existing == nil { context.insert(record) }
        if let target {
            record.calorieDisplayTargetSnapshot = target.calorieDisplayTarget
            record.calorieMinimumSnapshot = target.calorieMinimum
            record.calorieMaximumSnapshot = target.calorieMaximum
            record.proteinMinimumSnapshot = target.proteinMinimumGrams
        }
        record.finalizedAt = now
        record.updatedAt = now
        try context.save()
    }

    static func reopen(existing: NutritionDayRecord?, context: ModelContext, now: Date = .now) throws {
        guard let existing else { return }
        existing.finalizedAt = nil
        existing.updatedAt = now
        try context.save()
    }
}
