import CloudKit
import MomentumCore
import SwiftData
import SwiftUI
import UserNotifications

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettingsRecord]
    @Query private var nutritionTargets: [NutritionTargetRecord]
    @Query(sort: \WorkoutTemplateRecord.sequenceIndex) private var workouts: [WorkoutTemplateRecord]
    @Query private var anchors: [CycleAnchorRecord]
    @Query(sort: \CareRoutineTemplateRecord.notificationMinutes) private var routines: [CareRoutineTemplateRecord]

    @State private var step = 0
    @State private var planChoice: PlanChoice?
    @State private var trackNutrition = true
    @State private var isInstallingExamplePlan = false
    @State private var selectedWorkoutID: UUID?
    @State private var dueToday = true
    @State private var calorieTarget = "2400"
    @State private var calorieMinimum = "2300"
    @State private var calorieMaximum = "2500"
    @State private var proteinMinimum = "150"
    @State private var hairCareMinutes = 480
    @State private var morningCareMinutes = 540
    @State private var nightCareMinutes = 1_320
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var iCloudState: ICloudState = .checking
    @State private var isFinishing = false
    @State private var presentedAlert: OnboardingAlert?
    @State private var hasPreparedDrafts = false

    private let stepCount = 3
    private let notificationScheduler = NotificationScheduler()

    var body: some View {
        NavigationStack {
            VStack(spacing: MomentumSpacing.md) {
                progressHeader

                ScrollView {
                    VStack(alignment: .leading, spacing: MomentumSpacing.xl) {
                        stepContent
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, MomentumSpacing.md)
                    .padding(.top, MomentumSpacing.lg)
                    .padding(.bottom, MomentumSpacing.md)
                }

                footer
                    .padding(.horizontal, MomentumSpacing.md)
                    .padding(.bottom, MomentumSpacing.xs)
            }
            .navigationTitle("Welcome to Momentum")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") {
                            withAnimation(.easeOut(duration: 0.2)) {
                                step -= 1
                            }
                        }
                    }
                }
            }
            .task(id: "\(workouts.count)-\(routines.count)") {
                prepareDraftsIfNeeded()
                await refreshNotificationStatus()
                await refreshICloudState()
            }
            .alert(item: $presentedAlert) { alert in
                switch alert {
                case .saveFailed:
                    Alert(
                        title: Text("Setup could not be saved"),
                        message: Text("Your choices are still here. Try saving them again."),
                        primaryButton: .default(Text("Try again")) {
                            Task { await completeOnboarding() }
                        },
                        secondaryButton: .cancel(Text("Not now"))
                    )
                case .notificationsUnavailable:
                    Alert(
                        title: Text("Notifications are unavailable"),
                        message: Text("Momentum will keep working without reminders. You can try again later."),
                        dismissButton: .default(Text("Continue"))
                    )
                }
            }
        }
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.xs) {
            ProgressView(value: Double(step + 1), total: Double(stepCount))
                .tint(MomentumTheme.pulse)
                .accessibilityValue("Step \(step + 1) of \(stepCount)")

            Text(stepLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, MomentumSpacing.md)
        .padding(.top, MomentumSpacing.xs)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            welcomeStep
        case 1:
            planChoiceStep
        default:
            settingsStep
        }
    }

    private enum PlanChoice {
        case examplePlan
        case buildOwn
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.lg) {
            ThreadEmblem()

            VStack(alignment: .leading, spacing: MomentumSpacing.sm) {
                Text("One promise. Every day.")
                    .font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)

                Text("Momentum turns today’s obligations into a small, concrete sequence—workout, food, and personal care in one private place.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: MomentumSpacing.md) {
                OnboardingBenefit(
                    symbol: "arrow.triangle.2.circlepath",
                    title: "Follow the cycle",
                    detail: "Your next workout follows recovery, not weekdays."
                )
                OnboardingBenefit(
                    symbol: "lock.shield",
                    title: "Keep it private",
                    detail: "Your routine starts on this device, with no account to create."
                )
            }
        }
    }

    @ViewBuilder
    private var planChoiceStep: some View {
        switch planChoice {
        case .examplePlan:
            cycleStep
        case .buildOwn:
            buildOwnConfirmation
        case nil:
            planChoiceCards
        }
    }

    private var planChoiceCards: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.lg) {
            VStack(alignment: .leading, spacing: MomentumSpacing.sm) {
                Text("How do you want to start?")
                    .font(.title.bold())

                Text("Start from a complete example, or keep everything empty and build your own plans later in Plans.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Button {
                chooseExamplePlan()
            } label: {
                OnboardingChoiceCard(
                    symbol: "sparkles",
                    title: "Start from the example plan",
                    detail: "Upper/Lower workout templates and personal care routines, ready to edit.",
                    isSelected: false
                )
            }
            .buttonStyle(.plain)
            .disabled(isInstallingExamplePlan)

            if isInstallingExamplePlan {
                ProgressView()
                    .accessibilityLabel("Installing example plan")
            }

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    planChoice = .buildOwn
                }
            } label: {
                OnboardingChoiceCard(
                    symbol: "square.and.pencil",
                    title: "Build my own",
                    detail: "Nothing is installed. Add your own plans whenever you are ready.",
                    isSelected: false
                )
            }
            .buttonStyle(.plain)
            .disabled(isInstallingExamplePlan)
        }
    }

    private var buildOwnConfirmation: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.lg) {
            VStack(alignment: .leading, spacing: MomentumSpacing.sm) {
                Text("Starting empty")
                    .font(.title.bold())

                Text("Your plans stay empty for now. You can add workouts and personal care routines any time in Plans, or install the example plan later from Settings.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            OnboardingBenefit(
                symbol: "checkmark.circle",
                title: "Hydration stays on",
                detail: "Water tracking works out of the box; every other module can be enabled in Settings."
            )
        }
    }

    private var cycleStep: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.lg) {
            VStack(alignment: .leading, spacing: MomentumSpacing.sm) {
                Text("Your cycle, in sequence")
                    .font(.title.bold())

                Text("Choose the workout that comes next. The cycle then moves forward one completion at a time, with recovery in between.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(workouts.enumerated()), id: \.element.id) { index, workout in
                    Button {
                        selectedWorkoutID = workout.id
                    } label: {
                        HStack(spacing: MomentumSpacing.md) {
                            Text("\(index + 1)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(selectedWorkoutID == workout.id ? MomentumTheme.pulse : .secondary)
                                .frame(width: 28, height: 28)
                                .background(selectedWorkoutID == workout.id ? MomentumTheme.pulseWash : Color.secondary.opacity(0.10))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(workout.focus)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: selectedWorkoutID == workout.id ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selectedWorkoutID == workout.id ? MomentumTheme.pulse : .secondary)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Make \(workout.name) the next workout")
                    .padding(.vertical, MomentumSpacing.md)

                    if index < workouts.count - 1 {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
            .padding(.horizontal, MomentumSpacing.md)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: MomentumSpacing.md) {
                Text("Your personal care plan")
                    .font(.title3.bold())

                CarePreviewRow(
                    symbol: "sun.max",
                    title: "Morning care",
                    detail: "A daily cleanse choice, moisturizer, and SPF 50 sunscreen"
                )
                CarePreviewRow(
                    symbol: "moon",
                    title: "Night care",
                    detail: "A routine that changes by day and never progresses automatically"
                )
                CarePreviewRow(
                    symbol: "drop",
                    title: "Hair care",
                    detail: "An alternating 3/4-day routine that rolls forward when missed"
                )
            }
        }
    }

    private var settingsStep: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.lg) {
            VStack(alignment: .leading, spacing: MomentumSpacing.sm) {
                Text("Make the first day yours")
                    .font(.title.bold())

                Text("These are starting points, not rules. You can edit them later in Plans.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if planChoice == .examplePlan {
                VStack(alignment: .leading, spacing: MomentumSpacing.sm) {
                    Toggle(isOn: $dueToday) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(selectedWorkoutName) is due today")
                                .font(.headline)
                            Text("Turn this off to start your first day tomorrow.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(MomentumTheme.pulse)
                }
                .padding(MomentumSpacing.md)
                .background(MomentumTheme.pulseWash)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            VStack(alignment: .leading, spacing: MomentumSpacing.sm) {
                Toggle(isOn: $trackNutrition) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Track nutrition")
                            .font(.headline)
                        Text("Turn off to skip food logging for now. You can enable it later in Settings.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(MomentumTheme.pulse)

                if trackNutrition {
                    NutritionField(label: "Daily calories", value: $calorieTarget, suffix: "kcal")
                    HStack(spacing: MomentumSpacing.sm) {
                        NutritionField(label: "Range from", value: $calorieMinimum, suffix: "kcal")
                        NutritionField(label: "Range to", value: $calorieMaximum, suffix: "kcal")
                    }
                    NutritionField(label: "Protein minimum", value: $proteinMinimum, suffix: "g")

                    if !nutritionValidationMessages.isEmpty {
                        VStack(alignment: .leading, spacing: MomentumSpacing.xs) {
                            ForEach(nutritionValidationMessages, id: \.self) { message in
                                Label(message, systemImage: "exclamationmark.circle")
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            if planChoice == .examplePlan {
                VStack(alignment: .leading, spacing: MomentumSpacing.md) {
                    VStack(alignment: .leading, spacing: MomentumSpacing.xs) {
                        Text("Personal care reminders")
                            .font(.headline)
                        Text("Choose times that fit your day. These reminders can be changed later.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    ReminderTimeField(
                        label: "Hair care",
                        detail: "When the alternating routine is due",
                        minutes: $hairCareMinutes
                    )
                    ReminderTimeField(
                        label: "Morning care",
                        detail: "Daily",
                        minutes: $morningCareMinutes
                    )
                    ReminderTimeField(
                        label: "Night care",
                        detail: "Daily routine for the current weekday",
                        minutes: $nightCareMinutes
                    )
                }
            }

            notificationPermissionSection
            iCloudSection
        }
    }

    private var notificationPermissionSection: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.md) {
            Label("Reminders, only when useful", systemImage: "bell.badge")
                .font(.headline)

            Text("Momentum uses local reminders for personal care and a due workout. Denying permission never blocks the app.")
                .font(.body)
                .foregroundStyle(.secondary)

            switch notificationStatus {
            case .notDetermined:
                Button("Allow notifications") {
                    Task { await requestNotificationPermission() }
                }
                .buttonStyle(.bordered)
            case .denied:
                Label("Notifications are off. You can enable them later in Settings.", systemImage: "bell.slash")
                    .font(.body)
                    .foregroundStyle(.secondary)
            case .authorized, .provisional, .ephemeral:
                Label("Notifications are ready", systemImage: "checkmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(MomentumTheme.success)
            @unknown default:
                Text("Notification status is unavailable. Momentum will continue without reminders.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(MomentumSpacing.md)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var iCloudSection: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.md) {
            Label(iCloudState.title, systemImage: iCloudState.symbol)
                .font(.headline)

            Text(iCloudState.detail)
                .font(.body)
                .foregroundStyle(.secondary)

            if iCloudState != .available {
                Text("You can continue locally now. Momentum will use your private iCloud storage when it becomes available.")
                    .font(.body)
            }
        }
        .padding(MomentumSpacing.md)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var footer: some View {
        Button(action: advance) {
            Group {
                if isFinishing {
                    ProgressView()
                        .accessibilityLabel("Saving setup")
                } else {
                    Text(buttonTitle)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(MomentumTheme.pulse)
        .controlSize(.large)
        .disabled(
            isFinishing ||
            isInstallingExamplePlan ||
            (step == 1 && !planChoiceIsComplete) ||
            (step == stepCount - 1 && trackNutrition && !nutritionValidationMessages.isEmpty)
        )
        .accessibilityHint(step == stepCount - 1 ? "Completes onboarding" : "Moves to the next setup step")
    }

    private var planChoiceIsComplete: Bool {
        switch planChoice {
        case .buildOwn: true
        case .examplePlan: selectedWorkoutID != nil
        case nil: false
        }
    }

    private var stepLabel: String {
        switch step {
        case 0: "A private system for the things you keep"
        case 1: "Your starting point"
        default: "Your starting points"
        }
    }

    private var buttonTitle: String {
        switch step {
        case 0: "Get started"
        case 1:
            switch planChoice {
            case .examplePlan: "Keep \(selectedWorkoutName) next"
            default: "Continue"
            }
        default:
            planChoice == .examplePlan ? "Start with \(selectedWorkoutName)" : "Start with Momentum"
        }
    }

    private func chooseExamplePlan() {
        guard !isInstallingExamplePlan else { return }
        isInstallingExamplePlan = true
        Task {
            defer { isInstallingExamplePlan = false }
            do {
                try SeedData.install(in: modelContext)
                hasPreparedDrafts = false
                prepareDraftsIfNeeded()
                selectedWorkoutID = workouts.first?.id
                withAnimation(.easeOut(duration: 0.2)) {
                    planChoice = .examplePlan
                }
            } catch {
                presentedAlert = .saveFailed
            }
        }
    }

    private func advance() {
        guard step < stepCount - 1 else {
            Task { await completeOnboarding() }
            return
        }

        withAnimation(.easeOut(duration: 0.2)) {
            step += 1
        }
    }

    private var selectedWorkoutName: String {
        workouts.first { $0.id == selectedWorkoutID }?.name ?? "Upper A"
    }

    private var nutritionValidationMessages: [String] {
        var messages: [String] = []
        guard
            let target = Int(calorieTarget),
            let minimum = Int(calorieMinimum),
            let maximum = Int(calorieMaximum),
            let protein = Int(proteinMinimum)
        else {
            return ["Enter whole numbers for each nutrition starting point."]
        }

        if target <= 0 || minimum <= 0 || maximum <= 0 || protein <= 0 {
            messages.append("Calories and protein must be greater than zero.")
        }
        if minimum > maximum {
            messages.append("The calorie range must start below its upper limit.")
        } else if !(minimum...maximum).contains(target) {
            messages.append("The daily calorie target must sit inside the calorie range.")
        }
        return messages
    }

    private func prepareDraftsIfNeeded() {
        guard !hasPreparedDrafts else { return }
        hasPreparedDrafts = true

        if let target = nutritionTargets.max(by: { $0.effectiveFrom < $1.effectiveFrom }) {
            calorieTarget = String(target.calorieDisplayTarget)
            calorieMinimum = String(target.calorieMinimum)
            calorieMaximum = String(target.calorieMaximum)
            proteinMinimum = String(target.proteinMinimumGrams)
        }

        let anchor = anchors.max(by: { $0.updatedAt < $1.updatedAt })
        selectedWorkoutID = workouts.first(where: { $0.id == anchor?.nextWorkoutTemplateID })?.id
            ?? workouts.first?.id

        if let hairCare = routines.first(where: { $0.name == "Hair care" }) {
            hairCareMinutes = hairCare.notificationMinutes
        }
        if let morningCare = routines.first(where: { $0.name == "Morning care" }) {
            morningCareMinutes = morningCare.notificationMinutes
        }
        if let nightCare = routines.first(where: { $0.name.hasPrefix("Night care") }) {
            nightCareMinutes = nightCare.notificationMinutes
        }
    }

    private func refreshNotificationStatus() async {
        if isUsingPreviewStore {
            notificationStatus = .authorized
            return
        }
        NotificationScheduler.registerCategories()
        notificationStatus = await notificationScheduler.authorizationStatus()
    }

    private func requestNotificationPermission(showError: Bool = true) async {
        if isUsingPreviewStore {
            notificationStatus = .authorized
            return
        }

        do {
            _ = try await notificationScheduler.requestAuthorization()
            notificationStatus = await notificationScheduler.authorizationStatus()
        } catch {
            notificationStatus = await notificationScheduler.authorizationStatus()
            if showError {
                presentedAlert = .notificationsUnavailable
            }
        }
    }

    private func refreshICloudState() async {
        if isUsingPreviewStore {
            iCloudState = .available
            return
        }

        #if targetEnvironment(simulator)
        iCloudState = .unavailable
        return
        #else

        do {
            switch try await CKContainer(identifier: "iCloud.com.pratham.momentum").accountStatus() {
            case .available:
                iCloudState = .available
            case .noAccount:
                iCloudState = .noAccount
            case .restricted:
                iCloudState = .restricted
            case .couldNotDetermine, .temporarilyUnavailable:
                iCloudState = .unavailable
            @unknown default:
                iCloudState = .unavailable
            }
        } catch {
            iCloudState = .unavailable
        }
        #endif
    }

    private func completeOnboarding() async {
        guard
            let settings = AppSettingsRecord.canonical(in: settings),
            !(trackNutrition && !nutritionValidationMessages.isEmpty)
        else { return }
        let selectedWorkoutID = planChoice == .examplePlan ? self.selectedWorkoutID : nil
        let calorieTarget = Int(self.calorieTarget) ?? 0
        let calorieMinimum = Int(self.calorieMinimum) ?? 0
        let calorieMaximum = Int(self.calorieMaximum) ?? 0
        let proteinMinimum = Int(self.proteinMinimum) ?? 0

        isFinishing = true
        defer { isFinishing = false }

        if notificationStatus == .notDetermined {
            await requestNotificationPermission(showError: false)
        }

        let originalSettings = (
            onboardingCompleted: settings.onboardingCompleted,
            updatedAt: settings.updatedAt,
            enabledModulesRaw: settings.enabledModulesRaw
        )
        let anchor = anchors.max(by: { $0.updatedAt < $1.updatedAt })
        let originalAnchor = anchor.map {
            (nextWorkoutTemplateID: $0.nextWorkoutTemplateID, firstDueDomainDay: $0.firstDueDomainDay, updatedAt: $0.updatedAt)
        }
        let originalRoutines = routines.map {
            (record: $0, notificationMinutes: $0.notificationMinutes, updatedAt: $0.updatedAt)
        }
        let calendar = Calendar.autoupdatingCurrent
        let currentDay = DomainDay.containing(
            .now,
            calendar: calendar,
            cutoffMinutes: settings.domainDayCutoffMinutes
        )
        let effectiveFrom = PersistedDomainDay.encode(currentDay)
        let existingTarget = trackNutrition
            ? nutritionTargets.first { $0.effectiveFrom == effectiveFrom }
            : nil
        let priorOpenTarget = trackNutrition
            ? nutritionTargets
                .filter { $0.id != existingTarget?.id && $0.effectiveTo == nil && $0.effectiveFrom < effectiveFrom }
                .max { $0.effectiveFrom < $1.effectiveFrom }
            : nil
        let originalPriorTargetEnd = priorOpenTarget?.effectiveTo
        let target = existingTarget ?? NutritionTargetRecord(effectiveFrom: effectiveFrom)
        if trackNutrition, existingTarget == nil {
            modelContext.insert(target)
        }
        if let priorOpenTarget {
            priorOpenTarget.effectiveTo = PersistedDomainDay.encode(currentDay.adding(days: -1, calendar: calendar))
            priorOpenTarget.updatedAt = .now
        }

        settings.onboardingCompleted = true
        settings.updatedAt = .now

        // CONTEXT.md module inference (pre-launch spec §4): hydration is
        // always on; workout follows a confirmed cycle starting point;
        // nutrition follows an accepted target; care follows the example
        // plan or kept care reminder times (e.g. synced routines). Skipped
        // steps mean the module ships disabled.
        var enabledIDs: Set<ModuleID> = [BuiltInModuleID.hydration]
        if selectedWorkoutID != nil { enabledIDs.insert(BuiltInModuleID.workout) }
        if trackNutrition { enabledIDs.insert(BuiltInModuleID.nutrition) }
        if planChoice == .examplePlan || !routines.isEmpty {
            enabledIDs.insert(BuiltInModuleID.care)
        }
        ModuleEnablementStore.apply(enabledIDs, to: settings)

        if trackNutrition {
            target.calorieDisplayTarget = calorieTarget
            target.calorieMinimum = calorieMinimum
            target.calorieMaximum = calorieMaximum
            target.proteinMinimumGrams = proteinMinimum
            target.updatedAt = .now
        }

        if let selectedWorkoutID, let anchor {
            let dueDay = dueToday ? currentDay : currentDay.adding(days: 1, calendar: calendar)
            anchor.nextWorkoutTemplateID = selectedWorkoutID
            anchor.firstDueDomainDay = encode(dueDay)
            anchor.updatedAt = .now
        }

        if planChoice == .examplePlan {
            for routine in routines {
                switch routine.name {
                case "Hair care":
                    routine.notificationMinutes = hairCareMinutes
                case "Morning care":
                    routine.notificationMinutes = morningCareMinutes
                case let name where name.hasPrefix("Night care"):
                    routine.notificationMinutes = nightCareMinutes
                default:
                    continue
                }
                routine.updatedAt = .now
            }
        }

        do {
            try modelContext.save()
        } catch {
            settings.onboardingCompleted = originalSettings.onboardingCompleted
            settings.updatedAt = originalSettings.updatedAt
            settings.enabledModulesRaw = originalSettings.enabledModulesRaw
            if trackNutrition, existingTarget == nil {
                modelContext.delete(target)
            }
            priorOpenTarget?.effectiveTo = originalPriorTargetEnd
            if let anchor, let originalAnchor {
                anchor.nextWorkoutTemplateID = originalAnchor.nextWorkoutTemplateID
                anchor.firstDueDomainDay = originalAnchor.firstDueDomainDay
                anchor.updatedAt = originalAnchor.updatedAt
            }
            for original in originalRoutines {
                original.record.notificationMinutes = original.notificationMinutes
                original.record.updatedAt = original.updatedAt
            }
            presentedAlert = .saveFailed
        }
    }

    private var isUsingPreviewStore: Bool {
        ProcessInfo.processInfo.arguments.contains("-usePreviewStore")
    }

    private func encode(_ day: DomainDay) -> String {
        "\(day.year)-\(String(format: "%02d", day.month))-\(String(format: "%02d", day.day))"
    }
}

private enum OnboardingAlert: String, Identifiable {
    case saveFailed
    case notificationsUnavailable

    var id: String { rawValue }
}

private enum ICloudState: Equatable {
    case checking
    case available
    case noAccount
    case restricted
    case unavailable

    var title: LocalizedStringKey {
        switch self {
        case .checking: "Checking iCloud"
        case .available: "Private iCloud sync is ready"
        case .noAccount: "iCloud is not signed in"
        case .restricted: "iCloud access is restricted"
        case .unavailable: "iCloud is temporarily unavailable"
        }
    }

    var symbol: String {
        switch self {
        case .checking: "icloud"
        case .available: "icloud.fill"
        case .noAccount, .restricted, .unavailable: "icloud.slash"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .checking:
            "Momentum is checking whether private sync is available."
        case .available:
            "Your routine stays available on this iPhone and can sync through your private iCloud storage."
        case .noAccount:
            "Sign in to iCloud in the Settings app whenever you want private sync."
        case .restricted:
            "This device does not currently allow iCloud access for Momentum."
        case .unavailable:
            "Your routine remains available on this iPhone while iCloud is unavailable."
        }
    }
}

private struct CarePreviewRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: MomentumSpacing.md) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(MomentumTheme.pulse)
                .frame(width: 32, height: 32)
                .background(MomentumTheme.pulseWash)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ReminderTimeField: View {
    let label: String
    let detail: String
    @Binding var minutes: Int

    var body: some View {
        DatePicker(selection: timeBinding, displayedComponents: .hourAndMinute) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .datePickerStyle(.compact)
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.autoupdatingCurrent.date(
                    from: DateComponents(hour: minutes / 60, minute: minutes % 60)
                ) ?? .now
            },
            set: { date in
                let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
                minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }
}

private struct OnboardingBenefit: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: MomentumSpacing.md) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(MomentumTheme.pulse)
                .frame(width: 28, height: 28)
                .background(MomentumTheme.pulseWash)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct NutritionField: View {
    let label: String
    @Binding var value: String
    let suffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.xs) {
            Text(label)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: MomentumSpacing.xs) {
                TextField(label, text: $value)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)

                Text(suffix)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OnboardingChoiceCard: View {
    let symbol: String
    let title: String
    let detail: String
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: MomentumSpacing.md) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(MomentumTheme.pulse)
                .frame(width: 32, height: 32)
                .background(MomentumTheme.pulseWash)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(MomentumSpacing.md)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

private struct ThreadEmblem: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(MomentumTheme.pulse, lineWidth: 2)
                .frame(width: 76, height: 76)

            OnboardingThreadShape()
                .stroke(MomentumTheme.pulse, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 106, height: 34)
                .rotationEffect(.degrees(-18))
        }
        .frame(width: 106, height: 76)
        .accessibilityHidden(true)
    }
}

private struct OnboardingThreadShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.midY),
            control1: CGPoint(x: rect.width * 0.20, y: rect.minY),
            control2: CGPoint(x: rect.width * 0.30, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control1: CGPoint(x: rect.width * 0.70, y: rect.minY),
            control2: CGPoint(x: rect.width * 0.80, y: rect.maxY)
        )
        return path
    }
}
