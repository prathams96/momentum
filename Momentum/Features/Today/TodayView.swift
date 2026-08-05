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
    @State private var pendingDuplicateSessionID: UUID?

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
        let interval = MomentumDiagnostics.signposter.beginInterval("TodayAggregation")
        defer {
            MomentumDiagnostics.signposter.endInterval("TodayAggregation", interval)
        }
        return HistoryProjection.facts(
            sessions: sessions,
            workoutEvents: workoutEvents,
            nutritionDays: nutritionDays,
            careOccurrences: occurrences
        )
    }

    private var adherenceStreaks: HistoryStreakSummary {
        HistoryProjection.streaks(facts: adherenceFacts, calendar: calendar)
    }

    private var dailyThreadFocus: DailyThreadFocus {
        switch scheduleState {
        case .active, .due, .needsRepair:
            return .workout
        case .recovery:
            if nutritionDay?.finalizedAt == nil {
                return .food
            }
            if todayCareOccurrences.contains(where: { !["completed", "skipped"].contains($0.statusRaw) }) {
                return .care
            }
            return .reflect
        }
    }

    private var dailyThreadCallout: String {
        if case .needsRepair = scheduleState {
            return "Repair workout plan"
        }
        return "\(dailyThreadFocus.title) next"
    }

    var body: some View {
        repairConfirmationContent
    }

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MomentumSpacing.xl) {
                dateLine
                workoutSection
                nutritionSection
                activitySection
                consistencySection
            }
            .padding(.horizontal, MomentumSpacing.md)
            .padding(.top, MomentumSpacing.xs)
            .padding(.bottom, 96)
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

    private var repairConfirmationContent: some View {
        alertContent
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
        DailyThreadHeader(
            date: PersistedDomainDay.date(for: currentDomainDay, calendar: calendar)?.formatted(date: .complete, time: .omitted) ?? "Today",
            accessibilityDate: PersistedDomainDay.date(for: currentDomainDay, calendar: calendar)?.formatted(date: .abbreviated, time: .omitted) ?? "Today",
            focus: dailyThreadFocus,
            callout: dailyThreadCallout
        )
    }

    @ViewBuilder
    private var workoutSection: some View {
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
            refreshReconciledState()
        } catch {
            modelContext.rollback()
            pendingDuplicateSessionID = nil
            startError = "The duplicate sessions could not be resolved. No session was closed."
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.md) {
            Text("Care")
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
                Button("Log food", systemImage: "plus") { openFoodEntry(nil) }
                    .buttonStyle(.bordered)
                    .tint(MomentumTheme.pulse)
                    .frame(minHeight: 44)
            }

            VStack(alignment: .leading, spacing: MomentumSpacing.md) {
                NutritionGoalRow(
                    title: "Calories",
                    value: "\(DecimalFormatter.whole(nutritionTotals.calories)) kcal",
                    target: target.map { "\($0.calorieMinimum)–\($0.calorieMaximum) kcal" } ?? "Set a target in Plans",
                    visualization: .range(
                        current: NSDecimalNumber(decimal: nutritionTotals.calories).doubleValue,
                        minimum: Double(target?.calorieMinimum ?? 0),
                        maximum: Double(target?.calorieMaximum ?? 0)
                    ),
                    tint: MomentumTheme.success
                )

                NutritionGoalRow(
                    title: "Protein",
                    value: "\(DecimalFormatter.onePlace(nutritionTotals.proteinGrams)) g",
                    target: target.map { "\($0.proteinMinimumGrams) g minimum" } ?? "Set a target in Plans",
                    visualization: .threshold(
                        current: NSDecimalNumber(decimal: nutritionTotals.proteinGrams).doubleValue,
                        minimum: Double(target?.proteinMinimumGrams ?? 0)
                    ),
                    tint: MomentumTheme.dataCyan
                )

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

            Button(
                nutritionDay?.finalizedAt == nil ? "Finish logging today" : "Reopen nutrition",
                systemImage: nutritionDay?.finalizedAt == nil ? "checkmark" : "arrow.uturn.backward"
            ) {
                toggleNutritionFinalization()
            }
            .buttonStyle(.bordered)
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

    private var todayCareOccurrences: [CareOccurrenceRecord] {
        occurrences.filter {
            $0.dueDomainDay == PersistedDomainDay.encode(currentDomainDay)
        }
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

private enum DailyThreadFocus: Int, CaseIterable, Identifiable {
    case workout
    case food
    case care
    case reflect

    var id: Self { self }

    var title: String {
        switch self {
        case .workout: "Workout"
        case .food: "Food"
        case .care: "Care"
        case .reflect: "Reflect"
        }
    }

    var symbol: String {
        switch self {
        case .workout: "figure.strengthtraining.traditional"
        case .food: "fork.knife"
        case .care: "sparkles"
        case .reflect: "chart.xyaxis.line"
        }
    }
}

private struct DailyThreadHeader: View {
    let date: String
    let accessibilityDate: String
    let focus: DailyThreadFocus
    let callout: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var threadNodeSize = 28
    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.md) {
            VStack(alignment: .leading, spacing: MomentumSpacing.xxs) {
                Text(dynamicTypeSize.isAccessibilitySize ? accessibilityDate : date)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: MomentumSpacing.xs) {
                        promise
                        focusLabel
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: MomentumSpacing.sm) {
                        promise

                        Spacer(minLength: 0)

                        focusLabel
                    }
                }
            }

            if dynamicTypeSize.isAccessibilitySize {
                accessibilityThread
            } else {
                standardThread
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily thread")
        .accessibilityValue("\(accessibilityDate). One promise. Every day. \(callout). Workout, food, care, then reflect.")
        .onAppear {
            guard !isRevealed else { return }
            if reduceMotion {
                isRevealed = true
            } else {
                withAnimation(.easeOut(duration: 0.48)) {
                    isRevealed = true
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: focus)
    }

    private var focusedNodeSize: CGFloat {
        threadNodeSize + 4
    }

    private var standardThread: some View {
        ZStack(alignment: .top) {
            GeometryReader { proxy in
                Capsule()
                    .fill(Color.secondary.opacity(0.20))
                    .frame(width: max(proxy.size.width - 52, 0), height: 2)
                    .offset(x: 26, y: focusedNodeSize / 2)
                    .scaleEffect(x: isRevealed ? 1 : 0.02, anchor: .leading)
            }

            HStack(alignment: .top, spacing: 0) {
                ForEach(DailyThreadFocus.allCases) { stage in
                    DailyThreadStage(
                        stage: stage,
                        isFocused: stage == focus,
                        isRevealed: isRevealed,
                        nodeSize: threadNodeSize
                    )
                }
            }
        }
        .frame(height: max(focusedNodeSize + 24, 56))
    }

    private var accessibilityThread: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: MomentumSpacing.md
        ) {
            ForEach(DailyThreadFocus.allCases) { stage in
                DailyThreadStage(
                    stage: stage,
                    isFocused: stage == focus,
                    isRevealed: isRevealed,
                    nodeSize: min(threadNodeSize, 52)
                )
            }
        }
        .background {
            GeometryReader { proxy in
                Path { path in
                    let top = min(threadNodeSize, 52) / 2
                    let bottom = proxy.size.height - top - 34
                    path.move(to: CGPoint(x: proxy.size.width * 0.25, y: top))
                    path.addLine(to: CGPoint(x: proxy.size.width * 0.75, y: top))
                    path.addCurve(
                        to: CGPoint(x: proxy.size.width * 0.25, y: bottom),
                        control1: CGPoint(x: proxy.size.width * 0.88, y: proxy.size.height * 0.45),
                        control2: CGPoint(x: proxy.size.width * 0.12, y: proxy.size.height * 0.55)
                    )
                    path.addLine(to: CGPoint(x: proxy.size.width * 0.75, y: bottom))
                }
                .trim(from: 0, to: isRevealed ? 1 : 0.02)
                .stroke(Color.secondary.opacity(0.20), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
    }

    private var promise: some View {
        Text("One promise. Every day.")
            .font(.title2.bold())
            .fixedSize(horizontal: false, vertical: true)
    }

    private var focusLabel: some View {
        Label(callout, systemImage: "arrow.right")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(MomentumTheme.pulse)
            .labelStyle(.titleAndIcon)
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct DailyThreadStage: View {
    let stage: DailyThreadFocus
    let isFocused: Bool
    let isRevealed: Bool
    let nodeSize: CGFloat

    var body: some View {
        VStack(spacing: MomentumSpacing.xxs) {
            ZStack {
                Circle()
                    .fill(isFocused ? MomentumTheme.pulse : Color(uiColor: .secondarySystemBackground))
                    .frame(
                        width: isFocused ? nodeSize + 4 : nodeSize,
                        height: isFocused ? nodeSize + 4 : nodeSize
                    )

                Image(systemName: stage.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isFocused ? Color.white : Color.secondary)
            }
            .scaleEffect(isFocused && !isRevealed ? 0.78 : 1)

            Text(stage.title)
                .font(.caption.weight(isFocused ? .semibold : .regular))
                .foregroundStyle(isFocused ? MomentumTheme.pulse : Color.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

private enum NutritionGoalVisualization {
    case range(current: Double, minimum: Double, maximum: Double)
    case threshold(current: Double, minimum: Double)

    var current: Double {
        switch self {
        case let .range(current, _, _), let .threshold(current, _): current
        }
    }

    var scaleMaximum: Double {
        switch self {
        case let .range(current, _, maximum): max(current, maximum * 1.08, 1)
        case let .threshold(current, minimum): max(current, minimum * 1.25, 1)
        }
    }

    var highlightedRange: ClosedRange<Double> {
        switch self {
        case let .range(_, minimum, maximum): minimum...max(minimum, maximum)
        case let .threshold(_, minimum): 0...minimum
        }
    }
}

private struct NutritionGoalRow: View {
    let title: String
    let value: String
    let target: String
    let visualization: NutritionGoalVisualization
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: MomentumSpacing.md)
                Text(value)
                    .font(.headline.monospacedDigit())
            }

            NutritionGoalTrack(visualization: visualization, tint: tint)

            Text(target)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(value), target \(target)")
    }
}

private struct NutritionGoalTrack: View {
    let visualization: NutritionGoalVisualization
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let maximum = visualization.scaleMaximum
            let range = visualization.highlightedRange
            let start = min(max(range.lowerBound / maximum, 0), 1) * width
            let end = min(max(range.upperBound / maximum, 0), 1) * width
            let current = min(max(visualization.current / maximum, 0), 1) * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.16))
                    .frame(height: 6)

                Capsule()
                    .fill(tint)
                    .frame(width: max(end - start, 3), height: 6)
                    .offset(x: start)

                Circle()
                    .fill(Color.primary)
                    .frame(width: 10, height: 10)
                    .offset(x: min(max(current - 5, 0), max(width - 10, 0)))
            }
            .frame(height: 10)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.22),
                value: visualization.current
            )
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}
