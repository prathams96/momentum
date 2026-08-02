import Foundation
import MomentumCore
import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettingsRecord]
    @Query private var anchors: [CycleAnchorRecord]
    @Query(sort: \WorkoutTemplateRecord.sequenceIndex) private var workouts: [WorkoutTemplateRecord]
    @Query private var exercises: [ExercisePrescriptionRecord]
    @Query private var sessions: [WorkoutSessionRecord]
    @Query private var occurrences: [CareOccurrenceRecord]

    @State private var presentedSessionID: UUID?
    @State private var showFoodEntry = false
    @State private var presentedCareOccurrenceID: UUID?
    @State private var startError: String?
    @State private var reconciliationError: String?

    private let calendar = Calendar.autoupdatingCurrent

    private var currentDomainDay: DomainDay {
        DomainDay.containing(
            .now,
            calendar: calendar,
            cutoffMinutes: settings.first?.domainDayCutoffMinutes ?? 180
        )
    }

    private var activeSession: WorkoutSessionRecord? {
        sessions
            .filter { $0.finishedAt == nil && $0.deletedAt == nil }
            .sorted { $0.startedAt > $1.startedAt }
            .first
    }

    private var openSessions: [WorkoutSessionRecord] {
        sessions.filter { $0.finishedAt == nil && $0.deletedAt == nil }
    }

    private var scheduleState: WorkoutScheduleState {
        if openSessions.count > 1 {
            return .needsRepair(reason: .duplicateActiveSessions)
        }
        guard let anchor = anchors.max(by: { $0.updatedAt < $1.updatedAt }),
              let firstDueDay = PersistedDomainDay.decode(anchor.firstDueDomainDay) else {
            return .needsRepair(reason: .missingAnchorWorkout)
        }

        let templates = workouts
            .filter { !$0.isArchived }
            .map {
                WorkoutTemplate(
                    id: $0.id,
                    name: $0.name,
                    sequenceIndex: $0.sequenceIndex,
                    recoveryDaysAfter: $0.recoveryDaysAfter
                )
            }
        let completed = sessions.filter { $0.deletedAt == nil }.compactMap { session -> CompletedWorkoutSession? in
            guard let finishedAt = session.finishedAt,
                  let workoutID = session.workoutTemplateID,
                  let completionValue = session.completionDomainDay,
                  let completionDay = PersistedDomainDay.decode(completionValue) else {
                return nil
            }
            return CompletedWorkoutSession(
                id: session.id,
                workoutTemplateID: workoutID,
                completionDomainDay: completionDay,
                finishedAt: finishedAt,
                sequenceIndexSnapshot: session.sequenceIndexSnapshot,
                recoveryDaysAfterSnapshot: session.recoveryDaysAfterSnapshot,
                nextWorkoutTemplateIDSnapshot: session.nextWorkoutTemplateIDSnapshot
            )
        }

        return ScheduleEngine().evaluate(
            ScheduleInput(
                activeWorkoutTemplates: templates,
                cycleAnchor: CycleAnchor(nextWorkoutID: anchor.nextWorkoutTemplateID, firstDueDomainDay: firstDueDay),
                completedSessions: completed,
                currentDomainDay: currentDomainDay,
                calendar: calendar,
                activeSessionID: activeSession?.id
            )
        )
    }

    private var scheduledDay: DomainDay {
        switch scheduleState {
        case let .due(_, dueDay, _): return dueDay
        case let .recovery(_, eligibleDay, _): return eligibleDay
        case .active, .needsRepair: return currentDomainDay
        }
    }

    private var scheduledWorkout: WorkoutTemplateRecord? {
        let id: UUID?
        switch scheduleState {
        case let .due(workoutID, _, _), let .recovery(workoutID, _, _): id = workoutID
        case .active, .needsRepair: id = nil
        }
        return id.flatMap { workoutID in workouts.first { $0.id == workoutID } }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MomentumSpacing.xxl) {
                dateLine
                workoutSection
                activitySection
                consistencySection
            }
            .padding(.horizontal, MomentumSpacing.md)
            .padding(.top, MomentumSpacing.xs)
            .padding(.bottom, MomentumSpacing.xl)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .task(id: PersistedDomainDay.encode(currentDomainDay)) {
            do {
                try DailyReconciler.reconcile(in: modelContext)
            } catch {
                reconciliationError = "Today’s reminders could not be refreshed. Try again in a moment."
            }
        }
        .sheet(isPresented: Binding(
            get: { presentedSessionID != nil },
            set: { if !$0 { presentedSessionID = nil } }
        )) {
            if let sessionID = presentedSessionID {
                WorkoutSessionView(
                    sessionID: sessionID,
                    domainDayCutoffMinutes: settings.first?.domainDayCutoffMinutes ?? 180
                )
            }
        }
        .sheet(isPresented: $showFoodEntry) {
            FoodEntrySheet(domainDay: PersistedDomainDay.encode(currentDomainDay))
        }
        .sheet(isPresented: Binding(
            get: { presentedCareOccurrenceID != nil },
            set: { if !$0 { presentedCareOccurrenceID = nil } }
        )) {
            if let occurrenceID = presentedCareOccurrenceID {
                CareRoutineSheet(occurrenceID: occurrenceID)
            }
        }
        .alert("Couldn’t start workout", isPresented: Binding(
            get: { startError != nil },
            set: { if !$0 { startError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(startError ?? "Your plan is still safe.")
        }
        .alert("Couldn’t refresh today", isPresented: Binding(
            get: { reconciliationError != nil },
            set: { if !$0 { reconciliationError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reconciliationError ?? "Try again in a moment.")
        }
    }

    private var dateLine: some View {
        Text(PersistedDomainDay.date(for: currentDomainDay, calendar: calendar)?.formatted(date: .complete, time: .omitted) ?? "Today")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var workoutSection: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.md) {
            Text("Next")
                .font(.title3.bold())

            switch scheduleState {
            case let .active(sessionID):
                workoutCard(
                    title: "In progress",
                    detail: "Your unfinished workout is waiting for you.",
                    buttonTitle: "Resume workout",
                    action: { presentedSessionID = sessionID }
                )
            case let .due(_, dueDay, overdueBy):
                if let workout = scheduledWorkout {
                    workoutCard(
                        workout: workout,
                        title: overdueBy > 0 ? "Due since \(formatted(dueDay))" : "Due today",
                        detail: overdueBy > 0 ? "The cycle is ready when you are." : workout.focus,
                        buttonTitle: "Start workout",
                        action: { start(workout: workout, scheduledDay: dueDay) }
                    )
                } else {
                    repairCard
                }
            case let .recovery(workoutID, eligibleDay, daysRemaining):
                if let workout = workouts.first(where: { $0.id == workoutID }) {
                    workoutCard(
                        workout: workout,
                        title: "Recovery · \(daysRemaining) day\(daysRemaining == 1 ? "" : "s") left",
                        detail: "You can start early if today feels right.",
                        buttonTitle: "Start early",
                        action: { start(workout: workout, scheduledDay: eligibleDay) }
                    )
                } else {
                    repairCard
                }
            case let .needsRepair(reason):
                ContentUnavailableView(
                    "Your cycle needs attention",
                    systemImage: "wrench.and.screwdriver",
                    description: Text(reason.repairDescription)
                )
            }
        }
    }

    private func workoutCard(
        workout: WorkoutTemplateRecord? = nil,
        title: String,
        detail: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: MomentumSpacing.md) {
                HStack(alignment: .top, spacing: MomentumSpacing.md) {
                    VStack(alignment: .leading, spacing: MomentumSpacing.xs) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(MomentumTheme.pulse)
                        Text(workout?.name ?? "Workout")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.primary)
                            .minimumScaleFactor(0.85)
                        ThreadUnderline()
                            .stroke(MomentumTheme.pulse, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 112, height: 12)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title2)
                        .foregroundStyle(MomentumTheme.pulse)
                        .frame(width: 48, height: 48)
                        .background(Color(uiColor: .systemBackground).opacity(0.70))
                        .clipShape(Circle())
                }

                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    if let workout {
                        Label("\(exerciseCount(for: workout)) exercises", systemImage: "list.number")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(buttonTitle)
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .padding(.vertical, MomentumSpacing.sm)
                .padding(.horizontal, MomentumSpacing.md)
                .background(MomentumTheme.pulse)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(MomentumSpacing.md)
            .background(MomentumTheme.pulseWash)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityHint("\(buttonTitle)\(workout.map { " \($0.name)" } ?? "")")
    }

    private var repairCard: some View {
        ContentUnavailableView(
            "Your next workout is not set",
            systemImage: "figure.strengthtraining.traditional",
            description: Text("Open Plans to choose the next workout in your cycle.")
        )
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.md) {
            Text("Keep the day moving")
                .font(.title3.bold())

            VStack(spacing: 0) {
                Button { showFoodEntry = true } label: {
                    ActivityRow(symbol: "fork.knife", title: "Nutrition", detail: "Log food when you eat", tint: .secondary)
                }
                Divider().padding(.leading, 52)
                careButton(for: morningOccurrence, fallbackTitle: "Morning care", symbol: "sun.max", detail: "Daily routine")
                Divider().padding(.leading, 52)
                careButton(for: nightOccurrence, fallbackTitle: "Night care", symbol: "moon", detail: "Current weekday routine")
                Divider().padding(.leading, 52)
                careButton(for: hairOccurrence, fallbackTitle: "Hair care", symbol: "drop", detail: "Alternating routine")
            }
        }
    }

    private func careButton(
        for occurrence: CareOccurrenceRecord?,
        fallbackTitle: String,
        symbol: String,
        detail: String
    ) -> some View {
        Button {
            if let occurrence { presentedCareOccurrenceID = occurrence.id }
        } label: {
            ActivityRow(
                symbol: symbol,
                title: fallbackTitle,
                detail: occurrence.map { $0.statusRaw == "completed" ? "Completed at \($0.completedAt?.formatted(date: .omitted, time: .shortened) ?? "today")" : "Due at \($0.dueAt.formatted(date: .omitted, time: .shortened))" } ?? detail,
                tint: occurrence?.statusRaw == "completed" ? MomentumTheme.success : MomentumTheme.pulse
            )
        }
        .disabled(occurrence == nil)
    }

    private var morningOccurrence: CareOccurrenceRecord? {
        occurrence { $0.routineNameSnapshot == "Morning care" }
    }

    private var nightOccurrence: CareOccurrenceRecord? {
        occurrence { $0.routineNameSnapshot.hasPrefix("Night care") }
    }

    private var hairOccurrence: CareOccurrenceRecord? {
        occurrence { $0.routineNameSnapshot == "Hair care" }
    }

    private func occurrence(where predicate: (CareOccurrenceRecord) -> Bool) -> CareOccurrenceRecord? {
        occurrences
            .filter { $0.dueDomainDay == PersistedDomainDay.encode(currentDomainDay) && predicate($0) }
            .sorted { $0.dueAt < $1.dueAt }
            .first
    }

    private var consistencySection: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Consistency")
                    .font(.title3.bold())
                Spacer()
                Text("Last 16 weeks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 5) {
                ForEach(0..<16, id: \.self) { offset in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(consistencyColor(offset: offset))
                        .frame(height: 18)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Consistency history")
            .accessibilityValue("Workout history will appear here as you finish sessions")

            Text("Finish a workout and log your day to build the thread.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func consistencyColor(offset: Int) -> Color {
        let day = currentDomainDay.adding(days: -(15 - offset), calendar: calendar)
        let finished = sessions.contains { $0.completionDomainDay == PersistedDomainDay.encode(day) && $0.finishedAt != nil }
        return finished ? MomentumTheme.pulse : Color.secondary.opacity(0.14)
    }

    private func start(workout: WorkoutTemplateRecord, scheduledDay: DomainDay) {
        let ordered = workouts.filter { !$0.isArchived }.sorted { $0.sequenceIndex < $1.sequenceIndex }
        let successor = ordered.firstIndex(where: { $0.id == workout.id }).map { ordered[($0 + 1) % ordered.count].id }
        let workoutExercises = exercises.filter { $0.workoutTemplateID == workout.id }

        do {
            let sessionID = try WorkoutSessionStarter.start(
                workout: workout,
                exercises: workoutExercises,
                nextWorkoutTemplateID: successor,
                scheduledDomainDay: scheduledDay,
                currentDomainDay: currentDomainDay,
                in: modelContext
            )
            presentedSessionID = sessionID
        } catch {
            startError = (error as? LocalizedError)?.errorDescription ?? "The workout could not be started."
        }
    }

    private func exerciseCount(for workout: WorkoutTemplateRecord) -> Int {
        exercises.count { $0.workoutTemplateID == workout.id && !$0.isArchived }
    }

    private func formatted(_ day: DomainDay) -> String {
        PersistedDomainDay.date(for: day, calendar: calendar)?.formatted(.dateTime.month(.abbreviated).day()) ?? "that day"
    }
}

private extension ScheduleRepairReason {
    var repairDescription: String {
        switch self {
        case .noActiveWorkoutTemplates: "Add at least one active workout to continue the cycle."
        case .missingAnchorWorkout: "Choose the next workout in Plans."
        case .invalidSequenceIndices: "The workout order needs repair before the cycle can continue."
        case .invalidRecoveryDays: "One workout has an invalid recovery requirement."
        case .completedSessionReferencesMissingWorkout: "A completed workout references an unavailable plan."
        case .duplicateActiveSessions: "More than one unfinished workout exists. Resume or close one before continuing."
        }
    }
}

private struct ActivityRow: View {
    let symbol: String
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(spacing: MomentumSpacing.md) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.body).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, MomentumSpacing.sm)
        .accessibilityElement(children: .combine)
    }
}

private struct ThreadUnderline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control1: CGPoint(x: rect.width * 0.30, y: rect.minY),
            control2: CGPoint(x: rect.width * 0.70, y: rect.maxY)
        )
        return path
    }
}
