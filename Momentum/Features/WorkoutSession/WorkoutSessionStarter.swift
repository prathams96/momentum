import Foundation
import MomentumCore
import SwiftData

enum WorkoutSessionStartError: LocalizedError, Equatable {
    case openSessionExists(UUID)
    case noExercises
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .openSessionExists:
            "An unfinished workout is already open. Resume it before starting another."
        case .noExercises:
            "This workout has no active exercises yet. Repair the plan before starting it."
        case .saveFailed:
            "The workout could not be started. Your plan is still safe; try again."
        }
    }
}

@MainActor
enum WorkoutSessionStarter {
    static func start(
        workout: WorkoutTemplateRecord,
        exercises: [ExercisePrescriptionRecord],
        nextWorkoutTemplateID: UUID?,
        scheduledDomainDay: DomainDay,
        currentDomainDay: DomainDay,
        now: Date = .now,
        in context: ModelContext
    ) throws -> UUID {
        let openSessions = try context.fetch(
            FetchDescriptor<WorkoutSessionRecord>(
                predicate: #Predicate { $0.finishedAt == nil && $0.deletedAt == nil }
            )
        )
        if let openSession = openSessions.sorted(by: { $0.startedAt < $1.startedAt }).first {
            throw WorkoutSessionStartError.openSessionExists(openSession.id)
        }

        let activeExercises = exercises
            .filter { !$0.isArchived }
            .sorted { ($0.orderIndex, $0.id.uuidString) < ($1.orderIndex, $1.id.uuidString) }
        guard !activeExercises.isEmpty else {
            throw WorkoutSessionStartError.noExercises
        }

        let session = WorkoutSessionRecord(
            workoutTemplateID: workout.id,
            workoutNameSnapshot: workout.name,
            focusSnapshot: workout.focus,
            sequenceIndexSnapshot: workout.sequenceIndex,
            recoveryDaysAfterSnapshot: workout.recoveryDaysAfter,
            nextWorkoutTemplateIDSnapshot: nextWorkoutTemplateID,
            scheduledDomainDay: PersistedDomainDay.encode(scheduledDomainDay),
            startedAt: now,
            startedEarly: currentDomainDay < scheduledDomainDay
        )
        context.insert(session)

        var insertedExercises: [ExerciseLogRecord] = []
        var insertedSets: [SetLogRecord] = []
        for exercise in activeExercises {
            let log = ExerciseLogRecord(
                workoutSessionID: session.id,
                prescriptionID: exercise.id,
                exerciseNameSnapshot: exercise.displayName,
                orderIndex: exercise.orderIndex,
                setCountSnapshot: exercise.workingSetCount,
                repMinimumSnapshot: exercise.repMinimum,
                repMaximumSnapshot: exercise.repMaximum,
                repUnitSnapshot: exercise.repUnitRaw,
                notesSnapshot: exercise.notes
            )
            context.insert(log)
            insertedExercises.append(log)

            if exercise.workingSetCount > 0 {
                for setNumber in 1...exercise.workingSetCount {
                    let set = SetLogRecord(exerciseLogID: log.id, setNumber: setNumber)
                    context.insert(set)
                    insertedSets.append(set)
                }
            }
        }

        do {
            try context.save()
            return session.id
        } catch {
            for set in insertedSets { context.delete(set) }
            for exercise in insertedExercises { context.delete(exercise) }
            context.delete(session)
            throw WorkoutSessionStartError.saveFailed
        }
    }
}
