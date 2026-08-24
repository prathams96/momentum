import MomentumCore
import SwiftData
import SwiftUI

// MARK: - Notification route plumbing

private struct NotificationWorkoutRouteKey: EnvironmentKey {
    static let defaultValue: Binding<WorkoutNotificationRoute?> = .constant(nil)
}

extension EnvironmentValues {
    /// The pending deep-link route raised by a workout notification.
    var notificationWorkoutRoute: Binding<WorkoutNotificationRoute?> {
        get { self[NotificationWorkoutRouteKey.self] }
        set { self[NotificationWorkoutRouteKey.self] = newValue }
    }
}

private struct EarlyStartRequest: Identifiable {
    let workoutID: UUID
    let eligibleDay: DomainDay
    let daysRemaining: Int

    var id: UUID { workoutID }
}

/// The workout module's contribution to the Today surface: the next scheduled
/// session, early-start handling, and repair flows.
struct WorkoutTodaySection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.notificationWorkoutRoute) private var notificationWorkoutRoute
    @Query private var settings: [AppSettingsRecord]
    @Query private var anchors: [CycleAnchorRecord]
    @Query(sort: \WorkoutTemplateRecord.sequenceIndex) private var workouts: [WorkoutTemplateRecord]
    @Query private var exercises: [ExercisePrescriptionRecord]
    @Query private var sessions: [WorkoutSessionRecord]

    @State private var presentedSessionID: UUID?
    @State private var startError: String?
    @State private var pendingEarlyStart: EarlyStartRequest?
    @State private var pendingDuplicateSessionID: UUID?

    private let calendar = Calendar.autoupdatingCurrent

    private var currentDomainDay: DomainDay {
        ScheduleProjection.currentDomainDay(settings: settings, now: .now, calendar: calendar)
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
        ScheduleProjection.evaluate(
            workouts: workouts,
            anchors: anchors,
            sessions: sessions,
            settings: settings,
            now: .now,
            calendar: calendar
        )
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
        workoutContent
            .fullScreenCover(isPresented: Binding(
                get: { presentedSessionID != nil },
                set: { if !$0 { presentedSessionID = nil } }
            )) {
                if let sessionID = presentedSessionID {
                    WorkoutSessionView(
                        sessionID: sessionID,
                        domainDayCutoffMinutes: AppSettingsRecord.canonical(in: settings)?.domainDayCutoffMinutes ?? 180
                    )
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
            .alert(item: $pendingEarlyStart) { request in
                Alert(
                    title: Text("Start during recovery?"),
                    message: Text(earlyStartMessage(request)),
                    primaryButton: .default(Text("Start early")) {
                        handleEarlyStart(request)
                    },
                    secondaryButton: .cancel(Text("Keep recovering"))
                )
            }
            .confirmationDialog(
                "Keep this workout session?",
                isPresented: Binding(
                    get: { pendingDuplicateSessionID != nil },
                    set: { if !$0 { pendingDuplicateSessionID = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Keep and resume") { resolveDuplicateSessions() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The other unfinished sessions will be closed as deleted history. Their set logs will not be merged into the session you keep.")
            }
            .onChange(of: notificationWorkoutRoute.wrappedValue) { _, route in
                handleNotificationRoute(route)
            }
    }

    private var workoutContent: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.md) {
            Text("Next up")
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
                        detail: "Next eligible \(formatted(eligibleDay)). Start early only if recovery feels complete.",
                        buttonTitle: "Start early",
                        prominent: false,
                        action: {
                            pendingEarlyStart = EarlyStartRequest(
                                workoutID: workout.id,
                                eligibleDay: eligibleDay,
                                daysRemaining: daysRemaining
                            )
                        }
                    )
                } else {
                    repairCard
                }
            case let .needsRepair(reason):
                if reason == .duplicateActiveSessions {
                    duplicateSessionRepairCard
                } else {
                    ContentUnavailableView(
                        "Your cycle needs attention",
                        systemImage: "wrench.and.screwdriver",
                        description: Text(reason.repairDescription)
                    )
                }
            }
        }
    }

    private func workoutCard(
        workout: WorkoutTemplateRecord? = nil,
        title: String,
        detail: String,
        buttonTitle: String,
        prominent: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: MomentumSpacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: MomentumSpacing.sm) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if let workout {
                        Label("\(exerciseCount(for: workout)) exercises", systemImage: "list.number")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(alignment: .center, spacing: MomentumSpacing.md) {
                    Text(workout?.name ?? "Workout")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(MomentumTheme.pulse)
                        .frame(width: 44, height: 44)
                        .background(MomentumTheme.pulseWash)
                        .clipShape(Circle())
                }

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)

                HStack(spacing: MomentumSpacing.sm) {
                    Image(systemName: buttonTitle == "Resume workout" ? "play.fill" : "arrow.right")
                        .accessibilityHidden(true)
                    Text(buttonTitle)
                        .font(.headline)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(prominent ? Color.white : MomentumTheme.pulse)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                .padding(.horizontal, MomentumSpacing.md)
                .background(prominent ? MomentumTheme.pulse : MomentumTheme.pulseWash)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    if !prominent {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(MomentumTheme.pulse.opacity(0.35), lineWidth: 1)
                    }
                }
            }
            .padding(MomentumSpacing.md)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
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

    private var duplicateSessionRepairCard: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.md) {
            Label("Choose the workout to keep", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(MomentumTheme.warning)
            Text("More than one unfinished session was found. Choose one to resume; the others will be closed without merging their logs.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(openSessions.sorted { $0.startedAt > $1.startedAt }) { session in
                Button {
                    pendingDuplicateSessionID = session.id
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.workoutNameSnapshot)
                                .font(.headline)
                            Text("Started \(session.startedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Keep")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(MomentumSpacing.sm)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Keeps and resumes this session after confirmation")
            }
        }
        .padding(MomentumSpacing.md)
        .background(MomentumTheme.pulseWash)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func resolveDuplicateSessions() {
        guard let selectedID = pendingDuplicateSessionID,
              openSessions.contains(where: { $0.id == selectedID }) else {
            pendingDuplicateSessionID = nil
            return
        }
        do {
            try WorkoutSessionRepairService.resolveDuplicateOpenSessions(
                keeping: selectedID,
                sessions: openSessions,
                in: modelContext
            )
            pendingDuplicateSessionID = nil
            presentedSessionID = selectedID
        } catch {
            modelContext.rollback()
            pendingDuplicateSessionID = nil
            startError = "The duplicate sessions could not be resolved. No session was closed."
        }
    }

    private func handleEarlyStart(_ request: EarlyStartRequest) {
        guard let workout = workouts.first(where: { $0.id == request.workoutID }) else {
            startError = "That workout is no longer available in the current plan."
            return
        }
        start(workout: workout, scheduledDay: request.eligibleDay)
    }

    private func handleNotificationRoute(_ route: WorkoutNotificationRoute?) {
        guard let route else { return }
        notificationWorkoutRoute.wrappedValue = nil
        guard let workout = workouts.first(where: { $0.id == route.workoutID }) else {
            startError = "That workout is no longer available in the current plan."
            return
        }
        start(workout: workout, scheduledDay: route.domainDay)
    }

    private func earlyStartMessage(_ request: EarlyStartRequest) -> String {
        let noun = request.daysRemaining == 1 ? "day" : "days"
        return "Your plan has \(request.daysRemaining) recovery \(noun) remaining. Starting now is allowed, and future recovery will use the day you finish."
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

@MainActor
enum WorkoutSessionRepairService {
    static func resolveDuplicateOpenSessions(
        keeping selectedID: UUID,
        sessions: [WorkoutSessionRecord],
        in context: ModelContext,
        now: Date = .now
    ) throws {
        let open = sessions.filter { $0.finishedAt == nil && $0.deletedAt == nil }
        guard open.count > 1,
              open.contains(where: { $0.id == selectedID }) else {
            throw WorkoutSessionRepairError.invalidSelection
        }
        for session in open where session.id != selectedID {
            session.deletedAt = now
            session.updatedAt = now
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

enum WorkoutSessionRepairError: Error {
    case invalidSelection
}

extension ScheduleRepairReason {
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

// MARK: - Today contribution

extension WorkoutModuleAdapter: TodayContributing {
    func todayContribution(in context: ModuleContext) -> TodayContribution? {
        let modelContext = context.modelContext
        let workouts = (try? modelContext.fetch(FetchDescriptor<WorkoutTemplateRecord>())) ?? []
        let anchors = (try? modelContext.fetch(FetchDescriptor<CycleAnchorRecord>())) ?? []
        let sessions = (try? modelContext.fetch(FetchDescriptor<WorkoutSessionRecord>())) ?? []
        let settingsRecords = (try? modelContext.fetch(FetchDescriptor<AppSettingsRecord>())) ?? []

        switch ScheduleProjection.evaluate(
            workouts: workouts,
            anchors: anchors,
            sessions: sessions,
            settings: settingsRecords,
            now: context.now,
            calendar: context.calendar
        ) {
        case .needsRepair:
            return TodayContribution(
                metadata: metadata,
                state: .attention,
                accessibilitySummary: "Workout. Plan needs repair."
            )
        case let .due(_, _, overdueBy):
            return TodayContribution(
                metadata: metadata,
                state: .ongoing,
                accessibilitySummary: overdueBy > 0 ? "Workout. Overdue." : "Workout. Due today."
            )
        case .active:
            return TodayContribution(
                metadata: metadata,
                state: .ongoing,
                accessibilitySummary: "Workout. In progress."
            )
        case let .recovery(_, _, daysRemaining):
            let noun = daysRemaining == 1 ? "day" : "days"
            return TodayContribution(
                metadata: metadata,
                state: .optional,
                accessibilitySummary: "Workout. Recovery, \(daysRemaining) \(noun) remaining."
            )
        }
    }

    func todaySection(in context: ModuleContext) -> AnyView? {
        AnyView(WorkoutTodaySection())
    }
}
