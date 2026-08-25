import Foundation
import MomentumCore
import SwiftData

/// Milestones are a Core projection over module-emitted facts
/// (`MilestoneContributing`): Core owns thresholds, keys, and lifecycle but
/// never reaches into module schema.
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
        calendar: Calendar = .autoupdatingCurrent,
        registry: ModuleRegistry = .standard
    ) throws {
        let settings = AppSettingsRecord.canonical(
            in: try context.fetch(FetchDescriptor<AppSettingsRecord>())
        )
        let moduleContext = ModuleContext.make(
            in: context,
            settings: settings,
            now: now,
            calendar: calendar
        )
        let contributors = registry
            .enabledModules(ModuleEnablementStore.enabledIDs(from: settings))
            .compactMap { $0 as? any MilestoneContributing }

        let candidates = makeCandidates(
            facts: contributors.flatMap { $0.milestoneFacts(in: moduleContext) },
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
                title: "Personal care consistency",
                message: "All due personal care was completed for a record \(count) consecutive Domain Days.",
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

    // MARK: - Candidate projection over emitted facts

    private static func makeCandidates(
        facts: [MilestoneFact],
        calendar: Calendar
    ) -> [MilestoneCandidate] {
        var result = [MilestoneCandidate]()

        let completions = facts.compactMap { fact -> Date? in
            if case let .workoutCompleted(at) = fact { return at }
            return nil
        }.sorted()
        for threshold in [10, 25, 50] where completions.count >= threshold {
            result.append(MilestoneCandidate(
                kind: workoutCountKind,
                threshold: Double(threshold),
                relatedEntityID: nil,
                earnedAt: completions[threshold - 1]
            ))
        }

        let timeline: [(date: Date, completed: Bool)] =
            completions.map { ($0, true) } +
            facts.compactMap { fact -> (Date, Bool)? in
                if case let .workoutOpportunityMissed(at) = fact { return (at, false) }
                return nil
            }
        var current = 0
        var record = 0
        var recordEarnedAt = Date.distantPast
        for fact in timeline.sorted(by: { ($0.date, $0.completed ? 1 : 0) < ($1.date, $1.completed ? 1 : 0) }) {
            current = fact.completed ? current + 1 : 0
            if current > record { record = current; recordEarnedAt = fact.date }
        }
        if record >= 2 {
            result.append(MilestoneCandidate(
                kind: workoutStreakKind,
                threshold: Double(record),
                relatedEntityID: nil,
                earnedAt: recordEarnedAt
            ))
        }

        result.append(contentsOf: streakCandidates(
            loggingDays: facts.compactMap { fact -> StreakFact? in
                if case let .nutritionDayFinalized(day, finalizedAt, _, _, _, _, _) = fact {
                    return StreakFact(day: day, completed: true, earnedAt: finalizedAt)
                }
                return nil
            },
            kind: nutritionLoggingStreakKind,
            calendar: calendar
        ))

        result.append(contentsOf: streakCandidates(
            loggingDays: facts.compactMap { fact -> StreakFact? in
                if case let .personalCareDay(day, isFullyCompleted, lastActivityAt) = fact {
                    return StreakFact(day: day, completed: isFullyCompleted, earnedAt: lastActivityAt)
                }
                return nil
            },
            kind: careStreakKind,
            calendar: calendar
        ))

        result.append(contentsOf: exerciseCandidates(performanceFacts: facts))

        result.append(contentsOf: streakCandidates(
            loggingDays: facts.compactMap { fact -> StreakFact? in
                if case let .nutritionDayFinalized(day, finalizedAt, calorieMinimum, calorieMaximum, proteinMinimum, calories, protein) = fact {
                    return StreakFact(
                        day: day,
                        completed: calories >= Double(calorieMinimum)
                            && calories <= Double(calorieMaximum)
                            && protein >= Double(proteinMinimum),
                        earnedAt: finalizedAt
                    )
                }
                return nil
            },
            kind: nutritionRangeStreakKind,
            calendar: calendar
        ))

        return result
    }

    private static func streakCandidates(
        loggingDays days: [StreakFact],
        kind: String,
        calendar: Calendar
    ) -> [MilestoneCandidate] {
        let dayRecord = longestConsecutiveDays(days, calendar: calendar)
        guard dayRecord.count >= 2 else { return [] }
        return [MilestoneCandidate(
            kind: kind,
            threshold: Double(dayRecord.count),
            relatedEntityID: nil,
            earnedAt: dayRecord.earnedAt
        )]
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
        performanceFacts facts: [MilestoneFact]
    ) -> [MilestoneCandidate] {
        struct Performance {
            let prescriptionID: UUID
            let weightKg: Double
            let repetitions: Int
            let at: Date
        }

        var candidates = [MilestoneCandidate]()
        for (prescriptionID, performances) in Dictionary(
            grouping: facts.compactMap { fact -> Performance? in
                if case let .exercisePerformance(id, weightKg, repetitions, at) = fact {
                    return Performance(
                        prescriptionID: id,
                        weightKg: weightKg,
                        repetitions: repetitions,
                        at: at
                    )
                }
                return nil
            },
            by: \.prescriptionID
        ) {
            if let weightBest = performances.max(by: {
                ($0.weightKg, $0.repetitions, $0.at) < ($1.weightKg, $1.repetitions, $1.at)
            }), weightBest.weightKg > 0 {
                candidates.append(MilestoneCandidate(
                    kind: exerciseWeightBestKind,
                    threshold: weightBest.weightKg,
                    relatedEntityID: prescriptionID,
                    earnedAt: weightBest.at
                ))
            }
            if let repetitionBest = performances.max(by: {
                ($0.repetitions, $0.weightKg, $0.at) < ($1.repetitions, $1.weightKg, $1.at)
            }), repetitionBest.repetitions > 0 {
                candidates.append(MilestoneCandidate(
                    kind: exerciseRepetitionBestKind,
                    threshold: Double(repetitionBest.repetitions),
                    relatedEntityID: prescriptionID,
                    earnedAt: repetitionBest.at
                ))
            }
        }
        return candidates
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

struct MilestoneKey: Hashable {
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
