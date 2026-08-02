import Foundation
import MomentumCore
import SwiftData

enum SeedData {
    static let currentVersion = 3

    static func install(
        in context: ModelContext,
        currentDomainDay: DomainDay = DomainDay.containing(
            Foundation.Date(),
            calendar: Calendar.autoupdatingCurrent,
            cutoffMinutes: 180
        )
    ) throws {
        let settings = try context.fetch(FetchDescriptor<AppSettingsRecord>())
            .sorted { $0.updatedAt > $1.updatedAt }
            .first

        let existingTargets = try context.fetch(FetchDescriptor<NutritionTargetRecord>())
        if existingTargets.isEmpty {
            context.insert(NutritionTargetRecord(effectiveFrom: encode(currentDomainDay)))
        }

        if let settings, settings.seedVersion >= currentVersion {
            try context.save()
            return
        }

        let settingsRecord = settings ?? AppSettingsRecord()
        if settings == nil {
            context.insert(settingsRecord)
        }

        if settingsRecord.seedVersion < 1 {
            let workouts = seedWorkouts()
            for workout in workouts {
                context.insert(workout.record)
                for exercise in workout.exercises {
                    context.insert(exercise.record(workoutID: workout.record.id))
                    for alternative in exercise.alternatives {
                        context.insert(alternative.record(prescriptionID: exercise.id))
                    }
                }
            }

            let upperA = workouts[0].record
            context.insert(CycleAnchorRecord(
                nextWorkoutTemplateID: upperA.id,
                firstDueDomainDay: encode(currentDomainDay)
            ))

            for routine in seedCareRoutines(currentDomainDay: currentDomainDay) {
                context.insert(routine.record)
                for task in routine.tasks {
                    context.insert(task.record(routineID: routine.record.id))
                }
            }
        }

        if settingsRecord.seedVersion < 3 {
            let routines = try context.fetch(FetchDescriptor<CareRoutineTemplateRecord>())
            for routine in routines where !routine.isArchived {
                routine.recurrencePayload = versionedPayload(
                    for: routine.name,
                    currentDomainDay: currentDomainDay
                )
                routine.updatedAt = .now
            }
        }

        settingsRecord.seedVersion = currentVersion
        settingsRecord.updatedAt = .now
        try context.save()
    }

    private static func encode(_ day: DomainDay) -> String {
        "\(day.year)-\(String(format: "%02d", day.month))-\(String(format: "%02d", day.day))"
    }

    private struct SeedWorkout {
        let record: WorkoutTemplateRecord
        let exercises: [SeedExercise]
    }

    private struct SeedExercise {
        let id: UUID
        let name: String
        let orderIndex: Int
        let sets: Int
        let minimum: Int
        let maximum: Int
        let unit: String
        let notes: String
        let increment: Double
        let optional: Bool
        let alternatives: [SeedAlternative]

        func record(workoutID: UUID) -> ExercisePrescriptionRecord {
            ExercisePrescriptionRecord(
                id: id,
                workoutTemplateID: workoutID,
                displayName: name,
                orderIndex: orderIndex,
                workingSetCount: sets,
                repMinimum: minimum,
                repMaximum: maximum,
                repUnitRaw: unit,
                notes: notes,
                loadIncrementKg: increment,
                isOptional: optional
            )
        }
    }

    private struct SeedAlternative {
        let name: String
        let preferred: Bool

        func record(prescriptionID: UUID) -> ExerciseAlternativeRecord {
            ExerciseAlternativeRecord(
                prescriptionID: prescriptionID,
                displayName: name,
                orderIndex: 0,
                isPreferred: preferred
            )
        }
    }

    private static func seedWorkouts() -> [SeedWorkout] {
        [
            workout("Upper A", focus: "Incline pressing, horizontal pulling, shoulders, and arms", recovery: 0, exercises: [
                exercise("Incline Dumbbell Press", sets: 3, reps: 6...10, notes: "Main chest press"),
                exercise("Cable Row", sets: 3, reps: 8...12, notes: "Keep torso stable", alternatives: ["Cable Archer Pull"]),
                exercise("Assisted Pull-Up", sets: 2, reps: 6...10, notes: "Controlled full range", alternatives: ["Lat Pulldown"]),
                exercise("Dumbbell Shoulder Press", sets: 2, reps: 6...10, notes: "Avoid excessive back arch"),
                exercise("Cable Lateral Raise", sets: 2, reps: 12...20, notes: "Controlled movement"),
                exercise("Cable Overhead Triceps Extension", sets: 2, reps: 10...15, notes: "Long-head triceps focus"),
                exercise("Face-Away Cable Curl", sets: 2, reps: 10...15, notes: "Keep upper arm fixed")
            ]),
            workout("Lower A", focus: "Quadriceps, hamstrings, calves, and core", recovery: 1, exercises: [
                exercise("Leg Press", sets: 3, reps: 8...12, notes: "Main lower-body movement"),
                exercise("Dumbbell Goblet Squat", sets: 3, reps: 8...12, notes: "Keep torso controlled"),
                exercise("Leg Extension", sets: 2, reps: 10...15, notes: "Pause near full extension"),
                exercise("Seated or Lying Leg Curl", sets: 3, reps: 8...15, notes: "Controlled eccentric"),
                exercise("Machine or Leg-Press Calf Raise", sets: 3, reps: 10...20, notes: "Full stretch and contraction"),
                exercise("Pallof Press or Dead Bug", sets: 3, reps: 8...15, notes: "Core stability", alternatives: ["Dead Bug"])
            ]),
            workout("Upper B", focus: "Vertical pulling, chest accessories, rear delts, and arms", recovery: 0, exercises: [
                exercise("Single-Arm Cable Lat Pulldown", sets: 3, reps: 8...12, notes: "Drive elbow toward hip"),
                exercise("Dips or Push-Ups", sets: 3, reps: 6...12, notes: "Choose one", alternatives: ["Push-Ups"]),
                exercise("Cable Row or Cable Archer Pull", sets: 3, reps: 8...15, notes: "Choose one", alternatives: ["Cable Archer Pull"]),
                exercise("Machine Pec Fly", sets: 2, reps: 10...15, notes: "Controlled chest contraction"),
                exercise("Reverse Cable Fly or Reverse Pec Deck", sets: 2, reps: 12...20, notes: "Rear-delt focus", alternatives: ["Reverse Pec Deck"]),
                exercise("Cable Triceps Pushdown", sets: 2, reps: 10...15, notes: "Keep elbows fixed"),
                exercise("Sideways Hammer Curl", sets: 2, reps: 8...15, notes: "Neutral grip"),
                exercise("Supinated Single-Arm Cable Wrist Curl", sets: 2, reps: 12...20, notes: "Optional finisher", optional: true),
                exercise("Pronated Single-Arm Cable Wrist Curl", sets: 2, reps: 12...20, notes: "Optional finisher", optional: true)
            ]),
            workout("Lower B", focus: "Glutes, hamstrings, unilateral leg work, calves, and core", recovery: 2, exercises: [
                exercise("Bulgarian Split Squat or Reverse Lunge", sets: 3, reps: 8...12, notes: "Per leg; choose one", alternatives: ["Reverse Lunge"]),
                exercise("Hip-Thrust Machine or Glute Bridge", sets: 3, reps: 8...15, notes: "Use only if comfortable for the back", alternatives: ["Glute Bridge"]),
                exercise("Leg Curl", sets: 3, reps: 8...15, notes: "Seated or lying"),
                exercise("Leg Extension or Leg Press", sets: 2, reps: 10...15, notes: "Choose one"),
                exercise("Calf Raise", sets: 3, reps: 10...20, notes: "Full range of motion"),
                exercise("Side Plank or Pallof Press", sets: 3, reps: 20...45, unit: "seconds", notes: "Side plank: hold for seconds. Pallof press: use reps.", alternatives: ["Pallof Press"])
            ])
        ]
    }

    private static func workout(
        _ name: String,
        focus: String,
        recovery: Int,
        exercises: [SeedExercise]
    ) -> SeedWorkout {
        SeedWorkout(
            record: WorkoutTemplateRecord(
                name: name,
                focus: focus,
                sequenceIndex: workoutIndex(for: name),
                recoveryDaysAfter: recovery
            ),
            exercises: exercises.enumerated().map { index, exercise in
                SeedExercise(
                    id: exercise.id,
                    name: exercise.name,
                    orderIndex: index,
                    sets: exercise.sets,
                    minimum: exercise.minimum,
                    maximum: exercise.maximum,
                    unit: exercise.unit,
                    notes: exercise.notes,
                    increment: exercise.increment,
                    optional: exercise.optional,
                    alternatives: exercise.alternatives
                )
            }
        )
    }

    private static func workoutIndex(for name: String) -> Int {
        ["Upper A", "Lower A", "Upper B", "Lower B"].firstIndex(of: name)!
    }

    private static func exercise(
        _ name: String,
        sets: Int,
        reps: ClosedRange<Int>,
        unit: String = "reps",
        notes: String,
        alternatives: [String] = [],
        optional: Bool = false
    ) -> SeedExercise {
        SeedExercise(
            id: UUID(),
            name: name,
            orderIndex: 0,
            sets: sets,
            minimum: reps.lowerBound,
            maximum: reps.upperBound,
            unit: unit,
            notes: notes,
            increment: 1,
            optional: optional,
            alternatives: alternatives.map { SeedAlternative(name: $0, preferred: false) }
        )
    }

    private struct SeedRoutine {
        let record: CareRoutineTemplateRecord
        let tasks: [SeedTask]
    }

    private struct SeedTask {
        let label: String
        let orderIndex: Int
        let role: String?
        let active: String?
        let instruction: String?
        let requirement: String
        let condition: String?

        func record(routineID: UUID) -> CareTaskTemplateRecord {
            CareTaskTemplateRecord(
                routineTemplateID: routineID,
                label: label,
                genericProductRole: role,
                activeIngredient: active,
                instruction: instruction,
                orderIndex: orderIndex,
                requirementKindRaw: requirement,
                conditionGroup: condition
            )
        }
    }

    private static func seedCareRoutines(currentDomainDay: DomainDay) -> [SeedRoutine] {
        [
            routine("Morning care", payload: weekdayPayload(Set(1...7)), minutes: 540, tasks: [
                task("Choose oily cleanse path", active: "salicylic acid", requirement: "conditionalChoice", condition: "morning-cleanse"),
                task("Choose normal/dry cleanse path", role: "water rinse", requirement: "conditionalChoice", condition: "morning-cleanse"),
                task("Apply moisturizer", role: "moisturizer", instruction: "Thin layer. Wait 30–60 seconds before sunscreen."),
                task("Apply SPF 50 sunscreen", role: "sunscreen")
            ]),
            routine("Night care — adapalene", payload: weekdayPayload([2, 5]), minutes: 1320, tasks: [
                task("Cleanse face", active: "salicylic acid"),
                task("Pat dry", instruction: "Wait 10–20 minutes."),
                task("Apply adapalene 0.1%", active: "adapalene 0.1%", instruction: "Pea-sized amount over the face. Wait 2–5 minutes."),
                task("Apply moisturizer", role: "moisturizer")
            ]),
            routine("Night care — azelaic acid", payload: weekdayPayload([4, 7]), minutes: 1320, tasks: [
                task("Cleanse face", active: "salicylic acid"),
                task("Apply azelaic acid", active: "azelaic acid", instruction: "Pea-sized amount. Wait 1–2 minutes."),
                task("Apply moisturizer", role: "moisturizer")
            ]),
            routine("Night care", payload: weekdayPayload([1, 3, 6]), minutes: 1320, tasks: [
                task("Cleanse face", active: "salicylic acid"),
                task("Apply moisturizer", role: "moisturizer")
            ]),
            routine("Hair care", kind: "alternatingInterval", payload: alternatingPayload(anchor: nextHairCareDay(after: currentDomainDay)), minutes: 480, rolls: true, tasks: [
                task("Wash scalp", active: "salicylic acid", instruction: "Massage gently for 1–2 minutes, then rinse thoroughly."),
                task("Apply conditioner to hair lengths", role: "conditioner", instruction: "Avoid the scalp. Rinse after 2–3 minutes.")
            ])
        ]
    }

    private static func routine(
        _ name: String,
        kind: String = "weekdaySet",
        payload: String,
        minutes: Int,
        rolls: Bool = false,
        tasks: [SeedTask]
    ) -> SeedRoutine {
        SeedRoutine(
            record: CareRoutineTemplateRecord(
                name: name,
                recurrenceKindRaw: kind,
                recurrencePayload: payload,
                notificationMinutes: minutes,
                rollsForwardWhenMissed: rolls
            ),
            tasks: tasks.enumerated().map { index, task in
                SeedTask(
                    label: task.label,
                    orderIndex: index,
                    role: task.role,
                    active: task.active,
                    instruction: task.instruction,
                    requirement: task.requirement,
                    condition: task.condition
                )
            }
        )
    }

    private static func weekdayPayload(_ weekdays: Set<Int>) -> String {
        encode(CareRecurrencePayload(rule: .weekdays(weekdays)))
    }

    private static func alternatingPayload(anchor: DomainDay) -> String {
        encode(CareRecurrencePayload(rule: .alternating(
            anchorDueDay: anchor,
            intervals: [3, 4],
            intervalAfterAnchorIndex: 0
        )))
    }

    private static func versionedPayload(for name: String, currentDomainDay: DomainDay) -> String {
        switch name {
        case "Morning care": return weekdayPayload(Set(1...7))
        case "Night care — adapalene": return weekdayPayload([2, 5])
        case "Night care — azelaic acid": return weekdayPayload([4, 7])
        case "Night care": return weekdayPayload([1, 3, 6])
        case "Hair care": return alternatingPayload(anchor: nextHairCareDay(after: currentDomainDay))
        default: return weekdayPayload([])
        }
    }

    private static func encode(_ payload: CareRecurrencePayload) -> String {
        let data = try? JSONEncoder().encode(payload)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private static func nextHairCareDay(after day: DomainDay) -> DomainDay {
        let calendar = Calendar.autoupdatingCurrent
        for offset in 0...6 {
            let candidate = day.adding(days: offset, calendar: calendar)
            guard let date = PersistedDomainDay.date(for: candidate, calendar: calendar) else { continue }
            if [4, 7].contains(calendar.component(.weekday, from: date)) {
                return candidate
            }
        }
        return day
    }

    private static func task(
        _ label: String,
        role: String? = nil,
        active: String? = nil,
        instruction: String? = nil,
        requirement: String = "required",
        condition: String? = nil
    ) -> SeedTask {
        SeedTask(label: label, orderIndex: 0, role: role, active: active, instruction: instruction, requirement: requirement, condition: condition)
    }
}
