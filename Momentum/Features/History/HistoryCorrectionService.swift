import Foundation
import MomentumCore
import SwiftData

enum HistoryCorrectionError: Error, Equatable {
    case workoutNotFound
    case workoutNotCompleted
    case nutritionDayInFuture
    case careOccurrenceNotFound
    case careOccurrenceNotCompleted
}

@MainActor
enum HistoryCorrectionService {
    static func updateWorkoutCompletion(
        sessionID: UUID,
        finishedAt: Date,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) throws {
        try context.transaction {
            let sessions = try context.fetch(FetchDescriptor<WorkoutSessionRecord>())
            guard let session = sessions.first(where: { $0.id == sessionID && $0.deletedAt == nil }) else {
                throw HistoryCorrectionError.workoutNotFound
            }
            guard let priorFinishedAt = session.finishedAt else {
                throw HistoryCorrectionError.workoutNotCompleted
            }

            let settings = try context.fetch(FetchDescriptor<AppSettingsRecord>())
            let cutoff = AppSettingsRecord.canonical(in: settings)?.domainDayCutoffMinutes ?? 180
            let completionDay = DomainDay.containing(
                finishedAt,
                calendar: calendar,
                cutoffMinutes: cutoff
            )

            if finishedAt < session.startedAt {
                let priorDuration = max(0, priorFinishedAt.timeIntervalSince(session.startedAt))
                session.startedAt = finishedAt.addingTimeInterval(-priorDuration)
            }
            session.finishedAt = finishedAt
            session.completionDomainDay = PersistedDomainDay.encode(completionDay)
            session.updatedAt = now

            try DailyReconciler.reconcile(in: context, now: now, calendar: calendar)
        }
    }

    static func toggleNutritionFinalization(
        domainDay: DomainDay,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) throws {
        try context.transaction {
            let settings = try context.fetch(FetchDescriptor<AppSettingsRecord>())
            let cutoff = AppSettingsRecord.canonical(in: settings)?.domainDayCutoffMinutes ?? 180
            let currentDay = DomainDay.containing(now, calendar: calendar, cutoffMinutes: cutoff)
            guard domainDay <= currentDay else {
                throw HistoryCorrectionError.nutritionDayInFuture
            }

            let dayValue = PersistedDomainDay.encode(domainDay)
            let nutritionDays = try context.fetch(FetchDescriptor<NutritionDayRecord>())
            let record = nutritionDays
                .filter { $0.domainDay == dayValue }
                .max { ($0.updatedAt, $0.id.uuidString) < ($1.updatedAt, $1.id.uuidString) }

            if let record, record.finalizedAt != nil {
                record.finalizedAt = nil
                record.updatedAt = now
            } else {
                let finalized = record ?? NutritionDayRecord(domainDay: dayValue)
                if record == nil { context.insert(finalized) }
                let targets = try context.fetch(FetchDescriptor<NutritionTargetRecord>())
                if let target = NutritionDayService.target(for: domainDay, targets: targets) {
                    finalized.calorieDisplayTargetSnapshot = target.calorieDisplayTarget
                    finalized.calorieMinimumSnapshot = target.calorieMinimum
                    finalized.calorieMaximumSnapshot = target.calorieMaximum
                    finalized.proteinMinimumSnapshot = target.proteinMinimumGrams
                }
                finalized.finalizedAt = now
                finalized.updatedAt = now
            }

            try DailyReconciler.reconcile(in: context, now: now, calendar: calendar)
        }
    }

    static func undoCareCompletion(
        occurrenceID: UUID,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) throws {
        try context.transaction {
            let occurrences = try context.fetch(FetchDescriptor<CareOccurrenceRecord>())
            guard let occurrence = occurrences.first(where: { $0.id == occurrenceID }) else {
                throw HistoryCorrectionError.careOccurrenceNotFound
            }
            guard occurrence.statusRaw == "completed" else {
                throw HistoryCorrectionError.careOccurrenceNotCompleted
            }

            occurrence.statusRaw = "pending"
            occurrence.completedAt = nil
            occurrence.updatedAt = now

            let completions = try context.fetch(FetchDescriptor<CareTaskCompletionRecord>())
                .filter { $0.occurrenceID == occurrenceID }
            for completion in completions {
                completion.statusRaw = "pending"
                completion.completedAt = nil
                completion.selectedVariant = nil
                completion.updatedAt = now
            }

            if let routineID = occurrence.routineTemplateID,
               let previousPayload = occurrence.recurrencePayloadBeforeCompletion,
               let routine = try context.fetch(FetchDescriptor<CareRoutineTemplateRecord>())
                    .first(where: { $0.id == routineID }) {
                routine.recurrencePayload = previousPayload
                routine.updatedAt = now
                occurrence.recurrencePayloadBeforeCompletion = nil
            }

            try DailyReconciler.reconcile(in: context, now: now, calendar: calendar)
        }
    }
}
