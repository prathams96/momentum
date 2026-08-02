import Foundation
import MomentumCore
import SwiftData
import SwiftUI

private enum FoodEntryDestination: Identifiable {
    case new
    case edit(UUID)

    var id: String {
        switch self {
        case .new: "new"
        case let .edit(id): "edit-\(id.uuidString)"
        }
    }

    var existingEntryID: UUID? {
        if case let .edit(id) = self { return id }
        return nil
    }
}

private struct EarlyStartRequest: Identifiable {
    let workoutID: UUID
    let eligibleDay: DomainDay
    let daysRemaining: Int

    var id: UUID { workoutID }
}

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettingsRecord]
    @Query private var anchors: [CycleAnchorRecord]
    @Query(sort: \WorkoutTemplateRecord.sequenceIndex) private var workouts: [WorkoutTemplateRecord]
    @Query private var exercises: [ExercisePrescriptionRecord]
    @Query private var sessions: [WorkoutSessionRecord]
    @Query private var workoutEvents: [WorkoutDayEventRecord]
    @Query private var occurrences: [CareOccurrenceRecord]
    @Query private var foodEntries: [FoodEntryRecord]
    @Query private var nutritionDays: [NutritionDayRecord]
    @Query private var nutritionTargets: [NutritionTargetRecord]

    @State private var presentedSessionID: UUID?
    @State private var foodDestination: FoodEntryDestination?
    @State private var presentedCareOccurrenceID: UUID?
    @State private var startError: String?
    @State private var reconciliationError: String?
    @State private var nutritionError: String?
    @State private var pendingEarlyStart: EarlyStartRequest?

    private let calendar = Calendar.autoupdatingCurrent
    @Binding private var notificationWorkoutRoute: WorkoutNotificationRoute?

    init(notificationWorkoutRoute: Binding<WorkoutNotificationRoute?> = .constant(nil)) {
        _notificationWorkoutRoute = notificationWorkoutRoute
    }

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

    private var adherenceFacts: [HistoryAdherenceFact] {
        HistoryProjection.facts(
            sessions: sessions,
            workoutEvents: workoutEvents,
            nutritionDays: nutritionDays,
            careOccurrences: occurrences
        )
    }

    private var adherenceStreaks: HistoryStreakSummary {
        HistoryProjection.streaks(facts: adherenceFacts, calendar: calendar)
    }

    var body: some View {
        alertContent
    }

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MomentumSpacing.xxl) {
                dateLine
                workoutSection
                nutritionSection
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
                try await DailyReconciler.reconcileAndNotify(in: modelContext)
            } catch {
                reconciliationError = "Today’s reminders could not be refreshed. Try again in a moment."
            }
        }
        .onChange(of: notificationWorkoutRoute) { _, route in
            handleNotificationRoute(route)
        }
    }

    private var presentationContent: some View {
        mainContent
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
        .sheet(item: $foodDestination) { destination in
            FoodEntrySheet(
                domainDay: PersistedDomainDay.encode(currentDomainDay),
                existingEntryID: destination.existingEntryID
            )
        }
        .sheet(isPresented: Binding(
            get: { presentedCareOccurrenceID != nil },
            set: { if !$0 { presentedCareOccurrenceID = nil } }
        )) {
            if let occurrenceID = presentedCareOccurrenceID {
                CareRoutineSheet(occurrenceID: occurrenceID)
            }
        }
    }

    private var alertContent: some View {
        presentationContent
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
        .alert("Couldn’t update nutrition", isPresented: Binding(
            get: { nutritionError != nil },
            set: { if !$0 { nutritionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(nutritionError ?? "Your food entries are still safe.")
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
        notificationWorkoutRoute = nil
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
                careButton(for: morningOccurrence, fallbackTitle: "Morning care", symbol: "sun.max", detail: "Daily routine")
                Divider().padding(.leading, 52)
                careButton(for: nightOccurrence, fallbackTitle: "Night care", symbol: "moon", detail: "Current weekday routine")
                Divider().padding(.leading, 52)
                careButton(for: hairOccurrence, fallbackTitle: "Hair care", symbol: "drop", detail: "Alternating routine")
                ForEach(postWorkoutOccurrences) { occurrence in
                    Divider().padding(.leading, 52)
                    careButton(
                        for: occurrence,
                        fallbackTitle: "Post-workout care",
                        symbol: "figure.cooldown",
                        detail: "Added after today’s workout"
                    )
                }
            }
        }
    }

    private var nutritionSection: some View {
        let target = nutritionTarget
        let evaluation = target.flatMap { target in
            try? NutritionCalculator().evaluate(
                totals: nutritionTotals,
                against: NutritionTargetRange(
                    calorieMinimum: Decimal(target.calorieMinimum),
                    calorieMaximum: Decimal(target.calorieMaximum),
                    proteinMinimum: Decimal(target.proteinMinimumGrams)
                )
            )
        }

        return VStack(alignment: .leading, spacing: MomentumSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Nutrition")
                    .font(.title3.bold())
                Spacer()
                Text(nutritionDay?.finalizedAt == nil ? "Open" : "Finalized")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(nutritionDay?.finalizedAt == nil ? .secondary : MomentumTheme.success)
            }

            VStack(alignment: .leading, spacing: MomentumSpacing.sm) {
                HStack {
                    nutritionMetric(
                        title: "Calories",
                        value: "\(DecimalFormatter.whole(nutritionTotals.calories)) kcal",
                        detail: target.map { "Range \($0.calorieMinimum)–\($0.calorieMaximum)" } ?? "Set a target in Plans"
                    )
                    Spacer()
                    nutritionMetric(
                        title: "Protein",
                        value: "\(DecimalFormatter.onePlace(nutritionTotals.proteinGrams)) g",
                        detail: target.map { "Minimum \($0.proteinMinimumGrams) g" } ?? "Set a target in Plans"
                    )
                }

                if let evaluation {
                    Label(
                        evaluation.meetsTarget ? "Inside today’s targets" : "Keep logging to see the full picture",
                        systemImage: evaluation.meetsTarget ? "checkmark.circle.fill" : "circle.dashed"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(evaluation.meetsTarget ? MomentumTheme.success : .secondary)
                }
            }
            .padding(MomentumSpacing.md)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if activeFoodEntries.isEmpty {
                Text("Nothing logged yet. Start with the food you actually ate.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(activeFoodEntries) { entry in
                    HStack {
                        Button { openFoodEntry(entry.id) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.nameSnapshot).font(.headline)
                                Text("\(DecimalFormatter.whole(entry.totalCalories)) kcal · \(DecimalFormatter.onePlace(entry.totalProteinGrams)) g protein")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(entry.servingMultiplier.formatted(.number.precision(.fractionLength(0...2))))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button("Edit", systemImage: "pencil") { openFoodEntry(entry.id) }
                            Button("Duplicate", systemImage: "plus.square.on.square") { duplicateFoodEntry(entry) }
                            Button("Delete", systemImage: "trash", role: .destructive) { deleteFoodEntry(entry) }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Actions for \(entry.nameSnapshot)")
                    }
                }
            }

            HStack {
                Button("Log food", systemImage: "plus") { openFoodEntry(nil) }
                    .buttonStyle(.bordered)
                    .tint(MomentumTheme.pulse)
                Spacer()
                Button(
                    nutritionDay?.finalizedAt == nil ? "Finish logging today" : "Reopen",
                    systemImage: nutritionDay?.finalizedAt == nil ? "checkmark" : "arrow.uturn.backward"
                ) {
                    toggleNutritionFinalization()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func nutritionMetric(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit().weight(.bold))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var activeFoodEntries: [FoodEntryRecord] {
        let day = PersistedDomainDay.encode(currentDomainDay)
        return foodEntries
            .filter { $0.domainDay == day && $0.deletedAt == nil }
            .sorted { ($0.consumedAt, $0.id.uuidString) < ($1.consumedAt, $1.id.uuidString) }
    }

    private var nutritionDay: NutritionDayRecord? {
        NutritionDayService.day(for: currentDomainDay, in: nutritionDays)
    }

    private var nutritionTarget: NutritionTargetRecord? {
        NutritionDayService.target(for: currentDomainDay, targets: nutritionTargets)
    }

    private var nutritionTotals: NutritionTotals {
        NutritionCalculator().dayTotals(entries: activeFoodEntries.map {
            NutritionTotals(calories: Decimal(string: String($0.totalCalories)) ?? 0, proteinGrams: Decimal(string: String($0.totalProteinGrams)) ?? 0)
        })
    }

    private func openFoodEntry(_ id: UUID?) {
        foodDestination = id.map(FoodEntryDestination.edit) ?? .new
    }

    private func duplicateFoodEntry(_ entry: FoodEntryRecord) {
        let duplicate = FoodEntryRecord(
            domainDay: entry.domainDay,
            consumedAt: .now,
            presetID: entry.presetID,
            nameSnapshot: entry.nameSnapshot,
            caloriesPerBaseServing: entry.caloriesPerBaseServing,
            proteinPerBaseServing: entry.proteinPerBaseServing,
            servingMultiplier: entry.servingMultiplier,
            totalCalories: entry.totalCalories,
            totalProteinGrams: entry.totalProteinGrams
        )
        modelContext.insert(duplicate)
        do {
            try modelContext.save()
            refreshReconciledState()
        }
        catch { nutritionError = "The duplicate was not saved. Try again." }
    }

    private func deleteFoodEntry(_ entry: FoodEntryRecord) {
        entry.deletedAt = .now
        entry.updatedAt = .now
        do {
            try modelContext.save()
            refreshReconciledState()
        }
        catch { nutritionError = "The food entry was kept. Try again." }
    }

    private func toggleNutritionFinalization() {
        do {
            if nutritionDay?.finalizedAt == nil {
                try NutritionDayService.finalize(
                    domainDay: currentDomainDay,
                    target: nutritionTarget,
                    existing: nutritionDay,
                    context: modelContext
                )
            } else {
                try NutritionDayService.reopen(existing: nutritionDay, context: modelContext)
            }
            refreshReconciledState()
        } catch {
            nutritionError = "Your nutrition status was not changed. Try again."
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
                detail: occurrence.map(careStatusDetail) ?? detail,
                tint: occurrence?.statusRaw == "completed" ? MomentumTheme.success : MomentumTheme.pulse
            )
        }
        .disabled(occurrence == nil)
    }

    private var morningOccurrence: CareOccurrenceRecord? {
        occurrence { $0.routineRoleRaw == "morning" || $0.routineNameSnapshot == "Morning care" }
    }

    private var nightOccurrence: CareOccurrenceRecord? {
        occurrence { $0.routineRoleRaw == "night" || $0.routineNameSnapshot.hasPrefix("Night care") }
    }

    private var hairOccurrence: CareOccurrenceRecord? {
        occurrence { $0.routineRoleRaw == "hair" || $0.routineNameSnapshot == "Hair care" }
    }

    private var postWorkoutOccurrences: [CareOccurrenceRecord] {
        occurrences
            .filter {
                $0.dueDomainDay == PersistedDomainDay.encode(currentDomainDay) &&
                $0.routineRoleRaw == "postWorkout"
            }
            .sorted { $0.dueAt < $1.dueAt }
    }

    private func occurrence(where predicate: (CareOccurrenceRecord) -> Bool) -> CareOccurrenceRecord? {
        occurrences
            .filter { $0.dueDomainDay == PersistedDomainDay.encode(currentDomainDay) && predicate($0) }
            .sorted { $0.dueAt < $1.dueAt }
            .first
    }

    private func careStatusDetail(_ occurrence: CareOccurrenceRecord) -> String {
        switch occurrence.statusRaw {
        case "completed":
            return "Completed at \(occurrence.completedAt?.formatted(date: .omitted, time: .shortened) ?? "today")"
        case "skipped":
            return "Skipped today"
        case "missed":
            return "Missed"
        default:
            return "Due at \(occurrence.dueAt.formatted(date: .omitted, time: .shortened))"
        }
    }

    private func refreshReconciledState() {
        Task {
            do { try await DailyReconciler.reconcileAndNotify(in: modelContext) }
            catch { reconciliationError = "Today’s reminders could not be refreshed. Try again in a moment." }
        }
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

            CompactHistoryHeatmapView(currentDay: currentDomainDay, calendar: calendar) { day in
                HistoryProjection.adherenceScore(on: day, facts: adherenceFacts, category: .all)
            }

            HistoryStreakSummaryView(summary: adherenceStreaks, category: .all)
        }
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
