import Foundation
import MomentumCore
import SwiftData

@MainActor
enum MilestoneService {
    static let workoutCountKind = "workoutCount"
    static let workoutStreakKind = "categoryStreak.workout"
    static let nutritionLoggingStreakKind = "categoryStreak.nutritionLogging"
    static let careStreakKind = "categoryStreak.care"
    static let exerciseWeightBestKind = "exerciseBest.weight"
    static let exerciseRepetitionBestKind = "exerciseBest.repetitions"
    static let nutritionRangeStreakKind = "nutritionRangeStreak"

    private static let managedKinds: Set<String> = [
        workoutCountKind,
        workoutStreakKind,
        nutritionLoggingStreakKind,
        careStreakKind,
        exerciseWeightBestKind,
        exerciseRepetitionBestKind,
        nutritionRangeStreakKind
    ]

    static func reconcile(
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) throws {
        let candidates = makeCandidates(
            sessions: try context.fetch(FetchDescriptor<WorkoutSessionRecord>()),
            exerciseLogs: try context.fetch(FetchDescriptor<ExerciseLogRecord>()),
            setLogs: try context.fetch(FetchDescriptor<SetLogRecord>()),
            workoutEvents: try context.fetch(FetchDescriptor<WorkoutDayEventRecord>()),
            nutritionDays: try context.fetch(FetchDescriptor<NutritionDayRecord>()),
            foodEntries: try context.fetch(FetchDescriptor<FoodEntryRecord>()),
            careOccurrences: try context.fetch(FetchDescriptor<CareOccurrenceRecord>()),
            calendar: calendar
        )
        let candidateKeys = Set(candidates.map(\.key))
        let existing = try context.fetch(FetchDescriptor<MilestoneRecord>())
        var existingByKey = Dictionary(grouping: existing, by: MilestoneKey.init)

        for candidate in candidates {
            let matches = (existingByKey[candidate.key] ?? []).sorted {
                ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
            }
            if let canonical = matches.first {
                if canonical.earnedAt != candidate.earnedAt {
                    canonical.earnedAt = candidate.earnedAt
                    canonical.updatedAt = now
                }
                for duplicate in matches.dropFirst() { context.delete(duplicate) }
            } else {
                context.insert(MilestoneRecord(
                    kindRaw: candidate.kind,
                    threshold: candidate.threshold,
                    relatedEntityID: candidate.relatedEntityID,
                    earnedAt: candidate.earnedAt,
                    createdAt: now,
                    updatedAt: now
                ))
            }
            existingByKey[candidate.key] = nil
        }

        for record in existing where managedKinds.contains(record.kindRaw) && !candidateKeys.contains(MilestoneKey(record)) {
            context.delete(record)
        }

        do { try context.save() }
        catch { context.rollback(); throw error }
    }

    static func nextUnacknowledged(in milestones: [MilestoneRecord]) -> MilestoneRecord? {
        milestones
            .filter { managedKinds.contains($0.kindRaw) && $0.acknowledgedAt == nil }
            .min {
                ($0.earnedAt, $0.createdAt, $0.id.uuidString) <
                    ($1.earnedAt, $1.createdAt, $1.id.uuidString)
            }
    }

    static func acknowledge(
        _ milestone: MilestoneRecord,
        now: Date = .now,
        in context: ModelContext
    ) throws {
        guard milestone.acknowledgedAt == nil else { return }
        milestone.acknowledgedAt = now
        milestone.updatedAt = now
        do { try context.save() }
        catch { context.rollback(); throw error }
    }

    static func presentation(
        for milestone: MilestoneRecord,
        prescriptions: [ExercisePrescriptionRecord]
    ) -> MilestonePresentation {
        let count = Int(milestone.threshold ?? 0)
        let exerciseName = milestone.relatedEntityID.flatMap { id in
            prescriptions.first { $0.id == id }?.displayName
        } ?? "An exercise"
        switch milestone.kindRaw {
        case workoutCountKind:
            return MilestonePresentation(
                title: "A steady marker",
                message: "You’ve completed \(count) workouts. The continuous cycle is taking shape.",
                symbol: "figure.strengthtraining.traditional"
            )
        case workoutStreakKind:
            return MilestonePresentation(
                title: "Workout consistency",
                message: "A new record: \(count) due workout opportunities completed in a row.",
                symbol: "figure.strengthtraining.traditional"
            )
        case nutritionLoggingStreakKind:
            return MilestonePresentation(
                title: "Logging consistency",
                message: "You finalized nutrition logging for \(count) consecutive Domain Days.",
                symbol: "fork.knife"
            )
        case careStreakKind:
            return MilestonePresentation(
                title: "Care consistency",
                message: "All due care was completed for a record \(count) consecutive Domain Days.",
                symbol: "sparkles"
            )
        case exerciseWeightBestKind:
            return MilestonePresentation(
                title: "Exercise best",
                message: "\(exerciseName) reached a new completed-weight best of \(DecimalFormatter.onePlace(milestone.threshold ?? 0)) kg.",
                symbol: "arrow.up.right"
            )
        case exerciseRepetitionBestKind:
            return MilestonePresentation(
                title: "Exercise best",
                message: "\(exerciseName) reached a new completed-set best of \(count) repetitions.",
                symbol: "arrow.up.right"
            )
        case nutritionRangeStreakKind:
            return MilestonePresentation(
                title: "Nutrition target range",
                message: "You finished \(count) consecutive days inside the calorie and protein targets.",
                symbol: "checkmark.circle"
            )
        default:
            return MilestonePresentation(title: "A steady marker", message: "Your consistency has a new marker.", symbol: "checkmark.circle")
        }
    }

    private static func makeCandidates(
        sessions: [WorkoutSessionRecord],
        exerciseLogs: [ExerciseLogRecord],
        setLogs: [SetLogRecord],
        workoutEvents: [WorkoutDayEventRecord],
        nutritionDays: [NutritionDayRecord],
        foodEntries: [FoodEntryRecord],
        careOccurrences: [CareOccurrenceRecord],
        calendar: Calendar
    ) -> [MilestoneCandidate] {
        let completedSessions = sessions.filter { $0.finishedAt != nil && $0.deletedAt == nil }.sorted {
            (($0.finishedAt ?? .distantPast), $0.id.uuidString) < (($1.finishedAt ?? .distantPast), $1.id.uuidString)
        }
        var result = [MilestoneCandidate]()

        for threshold in [10, 25, 50] where completedSessions.count >= threshold {
            result.append(MilestoneCandidate(
                kind: workoutCountKind,
                threshold: Double(threshold),
                relatedEntityID: nil,
                earnedAt: completedSessions[threshold - 1].finishedAt ?? completedSessions[threshold - 1].startedAt
            ))
        }

        let workoutRecord = longestWorkoutStreak(sessions: completedSessions, events: workoutEvents)
        if workoutRecord.count >= 2 {
            result.append(MilestoneCandidate(
                kind: workoutStreakKind,
                threshold: Double(workoutRecord.count),
                relatedEntityID: nil,
                earnedAt: workoutRecord.earnedAt
            ))
        }

        let nutritionLoggingRecord = longestConsecutiveDays(
            nutritionDays.filter { $0.finalizedAt != nil }.compactMap { record in
                PersistedDomainDay.decode(record.domainDay).map { day in
                    StreakFact(day: day, completed: true, earnedAt: record.finalizedAt ?? record.updatedAt)
                }
            },
            calendar: calendar
        )
        if nutritionLoggingRecord.count >= 2 {
            result.append(MilestoneCandidate(
                kind: nutritionLoggingStreakKind,
                threshold: Double(nutritionLoggingRecord.count),
                relatedEntityID: nil,
                earnedAt: nutritionLoggingRecord.earnedAt
            ))
        }

        let careFacts = Dictionary(
            grouping: careOccurrences.filter { $0.statusRaw != "repairedDuplicate" },
            by: \.dueDomainDay
        ).compactMap { dayValue, occurrences -> StreakFact? in
            guard let day = PersistedDomainDay.decode(dayValue) else { return nil }
            return StreakFact(
                day: day,
                completed: occurrences.allSatisfy { $0.statusRaw == "completed" },
                earnedAt: occurrences.compactMap(\.completedAt).max() ?? occurrences.map(\.updatedAt).max() ?? .distantPast
            )
        }
        let careRecord = longestConsecutiveDays(careFacts, calendar: calendar)
        if careRecord.count >= 2 {
            result.append(MilestoneCandidate(
                kind: careStreakKind,
                threshold: Double(careRecord.count),
                relatedEntityID: nil,
                earnedAt: careRecord.earnedAt
            ))
        }

        result.append(contentsOf: exerciseCandidates(
            sessions: completedSessions,
            exerciseLogs: exerciseLogs,
            setLogs: setLogs
        ))

        let nutritionRangeRecord = longestConsecutiveDays(
            nutritionRangeFacts(
                days: nutritionDays,
                entries: foodEntries
            ),
            calendar: calendar
        )
        if nutritionRangeRecord.count >= 2 {
            result.append(MilestoneCandidate(
                kind: nutritionRangeStreakKind,
                threshold: Double(nutritionRangeRecord.count),
                relatedEntityID: nil,
                earnedAt: nutritionRangeRecord.earnedAt
            ))
        }

        return result
    }

    private static func longestWorkoutStreak(
        sessions: [WorkoutSessionRecord],
        events: [WorkoutDayEventRecord]
    ) -> (count: Int, earnedAt: Date) {
        let facts: [(date: Date, completed: Bool)] = sessions.map {
            ($0.finishedAt ?? $0.startedAt, true)
        } + events.filter { $0.deletedAt == nil }.map {
            ($0.createdAt, false)
        }
        var current = 0
        var record = 0
        var earnedAt = Date.distantPast
        for fact in facts.sorted(by: { ($0.date, $0.completed ? 1 : 0) < ($1.date, $1.completed ? 1 : 0) }) {
            current = fact.completed ? current + 1 : 0
            if current > record { record = current; earnedAt = fact.date }
        }
        return (record, earnedAt)
    }

    private static func longestConsecutiveDays(
        _ facts: [StreakFact],
        calendar: Calendar
    ) -> (count: Int, earnedAt: Date) {
        let canonical = Dictionary(grouping: facts, by: \.day).compactMap { _, values in
            values.max { ($0.earnedAt, $0.completed ? 1 : 0) < ($1.earnedAt, $1.completed ? 1 : 0) }
        }.sorted { $0.day < $1.day }
        var current = 0
        var record = 0
        var previous: DomainDay?
        var earnedAt = Date.distantPast
        for fact in canonical {
            if let previous, fact.day != previous.adding(days: 1, calendar: calendar) { current = 0 }
            current = fact.completed ? current + 1 : 0
            if current > record { record = current; earnedAt = fact.earnedAt }
            previous = fact.day
        }
        return (record, earnedAt)
    }

    private static func exerciseCandidates(
        sessions: [WorkoutSessionRecord],
        exerciseLogs: [ExerciseLogRecord],
        setLogs: [SetLogRecord]
    ) -> [MilestoneCandidate] {
        let sessionsByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let setsByLog = Dictionary(grouping: setLogs.filter { $0.statusRaw == "completed" }, by: \.exerciseLogID)
        var candidates = [MilestoneCandidate]()
        for (prescriptionID, logs) in Dictionary(
            grouping: exerciseLogs.filter { $0.prescriptionID != nil && $0.statusRaw == "completed" },
            by: { $0.prescriptionID! }
        ) {
            let performances = logs.flatMap { log -> [(SetLogRecord, Date)] in
                guard let session = sessionsByID[log.workoutSessionID] else { return [] }
                return (setsByLog[log.id] ?? []).map { ($0, session.finishedAt ?? session.startedAt) }
            }
            guard !performances.isEmpty else { continue }

            if let weightBest = performances.max(by: {
                ($0.0.weightKg, $0.0.repetitions, $0.1) < ($1.0.weightKg, $1.0.repetitions, $1.1)
            }), weightBest.0.weightKg > 0 {
                candidates.append(MilestoneCandidate(
                    kind: exerciseWeightBestKind,
                    threshold: weightBest.0.weightKg,
                    relatedEntityID: prescriptionID,
                    earnedAt: weightBest.1
                ))
            }
            if let repetitionBest = performances.max(by: {
                ($0.0.repetitions, $0.0.weightKg, $0.1) < ($1.0.repetitions, $1.0.weightKg, $1.1)
            }), repetitionBest.0.repetitions > 0 {
                candidates.append(MilestoneCandidate(
                    kind: exerciseRepetitionBestKind,
                    threshold: Double(repetitionBest.0.repetitions),
                    relatedEntityID: prescriptionID,
                    earnedAt: repetitionBest.1
                ))
            }
        }
        return candidates
    }

    private static func nutritionRangeFacts(
        days: [NutritionDayRecord],
        entries: [FoodEntryRecord]
    ) -> [StreakFact] {
        let entriesByDay = Dictionary(grouping: entries.filter { $0.deletedAt == nil }, by: \.domainDay)
        return days.compactMap { record in
            guard let finalizedAt = record.finalizedAt,
                  let day = PersistedDomainDay.decode(record.domainDay) else { return nil }
            let minimum = record.calorieMinimumSnapshot
            let maximum = record.calorieMaximumSnapshot
            let proteinMinimum = record.proteinMinimumSnapshot
            let totals = (entriesByDay[record.domainDay] ?? []).reduce(into: (calories: 0.0, protein: 0.0)) {
                $0.calories += $1.totalCalories
                $0.protein += $1.totalProteinGrams
            }
            return StreakFact(
                day: day,
                completed: totals.calories >= Double(minimum) &&
                    totals.calories <= Double(maximum) &&
                    totals.protein >= Double(proteinMinimum),
                earnedAt: finalizedAt
            )
        }
    }
}

struct MilestonePresentation: Equatable {
    let title: String
    let message: String
    let symbol: String
}

private struct MilestoneCandidate {
    let kind: String
    let threshold: Double
    let relatedEntityID: UUID?
    let earnedAt: Date
    var key: MilestoneKey { MilestoneKey(kind: kind, threshold: threshold, relatedEntityID: relatedEntityID) }
}

private struct MilestoneKey: Hashable {
    let kind: String
    let threshold: Double?
    let relatedEntityID: UUID?

    init(kind: String, threshold: Double?, relatedEntityID: UUID?) {
        self.kind = kind
        self.threshold = threshold
        self.relatedEntityID = relatedEntityID
    }

    init(_ record: MilestoneRecord) {
        self.init(kind: record.kindRaw, threshold: record.threshold, relatedEntityID: record.relatedEntityID)
    }
}

private struct StreakFact {
    let day: DomainDay
    let completed: Bool
    let earnedAt: Date
}
