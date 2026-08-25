import Foundation
import MomentumCore
import SwiftData

// MARK: - Milestone contribution

extension WorkoutModuleAdapter: MilestoneContributing {
    func milestoneFacts(in context: ModuleContext) -> [MilestoneFact] {
        let modelContext = context.modelContext
        let sessions = ((try? modelContext.fetch(FetchDescriptor<WorkoutSessionRecord>())) ?? [])
            .filter { $0.deletedAt == nil }
        let events = ((try? modelContext.fetch(FetchDescriptor<WorkoutDayEventRecord>())) ?? [])
            .filter { $0.deletedAt == nil }
        let logsBySession = Dictionary(grouping:
            ((try? modelContext.fetch(FetchDescriptor<ExerciseLogRecord>())) ?? [])
                .filter { $0.prescriptionID != nil && $0.statusRaw == "completed" },
            by: \.workoutSessionID
        )
        let completedSetsByLog = Dictionary(grouping:
            ((try? modelContext.fetch(FetchDescriptor<SetLogRecord>())) ?? [])
                .filter { $0.statusRaw == "completed" },
            by: \.exerciseLogID
        )

        var facts: [MilestoneFact] = []
        for session in sessions.filter({ $0.finishedAt != nil }) {
            facts.append(.workoutCompleted(at: session.finishedAt ?? session.startedAt))
            for log in logsBySession[session.id] ?? [] {
                for set in completedSetsByLog[log.id] ?? [] {
                    facts.append(.exercisePerformance(
                        prescriptionID: log.prescriptionID ?? UUID(),
                        weightKg: set.weightKg,
                        repetitions: set.repetitions,
                        at: session.finishedAt ?? session.startedAt
                    ))
                }
            }
        }
        for event in events {
            facts.append(.workoutOpportunityMissed(at: event.createdAt))
        }
        return facts
    }
}
