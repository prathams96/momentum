import MomentumCore
import SwiftData
import SwiftUI

/// The hydration module's contribution to the Today surface: progress against
/// the day's frozen target snapshot, one-tap preset logging, a custom-amount
/// sheet, and undo of the latest entry.
struct HydrationTodaySection: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettingsRecord]
    @Query private var hydrationPlans: [HydrationPlanRecord]
    @Query private var hydrationEntries: [HydrationEntryRecord]
    @Query private var hydrationDays: [HydrationDayRecord]

    @State private var showsCustomAmount = false
    @State private var hydrationError: String?

    private let calendar = Calendar.autoupdatingCurrent

    private var cutoffMinutes: Int {
        AppSettingsRecord.canonical(in: settings)?.domainDayCutoffMinutes ?? 180
    }

    private var unitSystem: UnitSystemOption {
        UnitSystemOption(rawValue: AppSettingsRecord.canonical(in: settings)?.unitSystemRaw ?? "metric") ?? .metric
    }

    private var currentDayKey: String {
        PersistedDomainDay.encode(DomainDay.containing(.now, calendar: calendar, cutoffMinutes: cutoffMinutes))
    }

    private var plan: HydrationPlanRecord? {
        hydrationPlans.min { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }

    private var dayRecord: HydrationDayRecord? {
        HydrationRecords.dayRecord(for: currentDayKey, in: hydrationDays)
    }

    private var activeEntries: [HydrationEntryRecord] {
        HydrationRecords.activeEntries(for: currentDayKey, in: hydrationEntries)
    }

    private var consumedML: Int {
        HydrationRecords.total(intake: activeEntries)
    }

    /// The day's snapshot while it exists; before reconciliation has run the
    /// editable plan value is the best available projection.
    private var targetML: Int {
        dayRecord?.targetMLSnapshot ?? plan?.targetML ?? 2500
    }

    private var presetsML: [Int] {
        guard let plan else { return [250, 500, 750] }
        return [plan.firstPresetML, plan.secondPresetML, plan.thirdPresetML]
    }

    private var state: ContributionState {
        if activeEntries.isEmpty { return .optional }
        return consumedML >= targetML ? .completed : .ongoing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.md) {
            Text("Hydration")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: MomentumSpacing.xs) {
                Text("\(HydrationVolumeFormatting.volume(consumedML, unitSystem: unitSystem)) of \(HydrationVolumeFormatting.volume(targetML, unitSystem: unitSystem))")
                    .font(.headline.monospacedDigit())

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.16))
                        Capsule()
                            .fill(MomentumTheme.dataCyan)
                            .frame(width: fillWidth(in: proxy.size.width))
                    }
                }
                .frame(height: 10)
                .accessibilityHidden(true)

                Label(
                    statusText,
                    systemImage: state == .completed ? "checkmark.circle.fill" : "drop"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(state == .completed ? MomentumTheme.success : .secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilitySummary)

            HStack(spacing: MomentumSpacing.sm) {
                ForEach(Array(presetsML.enumerated()), id: \.offset) { _, amountML in
                    Button { logPreset(amountML) } label: {
                        Text("+\(presetLabel(amountML))")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(MomentumTheme.dataCyan)
                    .accessibilityLabel(presetAccessibilityLabel(amountML))
                }
            }

            HStack {
                Button("Custom…") { showsCustomAmount = true }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)

                Spacer()

                if !activeEntries.isEmpty {
                    HStack(spacing: MomentumSpacing.xxs) {
                        Text("latest entry:")
                            .foregroundStyle(.secondary)
                        Button("Undo") { undoLatest() }
                            .frame(minHeight: 44)
                    }
                }
            }
            .font(.subheadline)
        }
        .sheet(isPresented: $showsCustomAmount) {
            HydrationCustomAmountSheet(unitSystem: unitSystem)
        }
        .alert("Couldn’t update hydration", isPresented: Binding(
            get: { hydrationError != nil },
            set: { if !$0 { hydrationError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(hydrationError ?? "Your entries are still safe.")
        }
    }

    private var statusText: String {
        switch state {
        case .optional: "Nothing logged yet"
        case .ongoing: "In progress"
        case .completed: "Daily target reached"
        default: "In progress"
        }
    }

    private var accessibilitySummary: String {
        "Hydration. \(HydrationVolumeFormatting.volume(consumedML, unitSystem: unitSystem)) of \(HydrationVolumeFormatting.volume(targetML, unitSystem: unitSystem)) daily target. \(HydrationVolumeFormatting.percentage(of: consumedML, targetML: targetML)) percent."
    }

    private func presetLabel(_ amountML: Int) -> String {
        guard unitSystem == .imperial else { return "\(amountML) ml" }
        return "\(HydrationEngine.fluidOuncesDisplay(fromML: amountML)) fl oz"
    }

    private func presetAccessibilityLabel(_ amountML: Int) -> String {
        guard unitSystem == .imperial else { return "Add \(amountML) millilitres" }
        return "Add \(HydrationEngine.fluidOuncesDisplay(fromML: amountML)) fluid ounces"
    }

    private func fillWidth(in width: CGFloat) -> CGFloat {
        guard targetML > 0 else { return 0 }
        return min(max(CGFloat(consumedML) / CGFloat(targetML), 0), 1) * width
    }

    private func logPreset(_ amountML: Int) {
        do {
            try HydrationEntryService.log(
                amountML: amountML,
                cutoffMinutes: cutoffMinutes,
                in: modelContext
            )
            refreshReconciledState()
        } catch {
            hydrationError = "The entry was not saved. Try again."
        }
    }

    private func undoLatest() {
        do {
            try HydrationEntryService.undoLatest(cutoffMinutes: cutoffMinutes, in: modelContext)
            refreshReconciledState()
        } catch {
            hydrationError = "The entry was kept. Try again."
        }
    }

    private func refreshReconciledState() {
        Task {
            do { try await DailyReconciler.reconcileAndNotify(in: modelContext) }
            catch { hydrationError = "Today’s reminders could not be refreshed. Try again in a moment." }
        }
    }
}

/// Small amount sheet behind "Custom…": one decimal field rendered in the
/// global unit system; amounts are stored as millilitres either way.
struct HydrationCustomAmountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettingsRecord]

    @State private var amount = 0.0
    @State private var saveError: String?

    let unitSystem: UnitSystemOption

    private var cutoffMinutes: Int {
        AppSettingsRecord.canonical(in: settings)?.domainDayCutoffMinutes ?? 180
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        unitSystem == .imperial ? "Amount (fl oz)" : "Amount (ml)",
                        value: $amount,
                        format: .number.precision(.fractionLength(0...2))
                    )
                    .keyboardType(.decimalPad)
                } footer: {
                    Text(unitSystem == .imperial
                        ? "Entered in fluid ounces and stored as millilitres."
                        : "Entered in millilitres.")
                }
            }
            .navigationTitle("Custom amount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(amount <= 0)
                }
            }
            .alert("Couldn’t save entry", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) { Button("OK", role: .cancel) {} } message: {
                Text(saveError ?? "Try again.")
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let amountML: Int
        switch unitSystem {
        case .metric:
            amountML = Int(amount.rounded())
        case .imperial:
            amountML = HydrationEngine.millilitres(fromExactFluidOunces: amount)
        }
        guard amountML > 0 else {
            saveError = "Enter an amount greater than zero."
            return
        }
        do {
            try HydrationEntryService.log(
                amountML: amountML,
                cutoffMinutes: cutoffMinutes,
                in: modelContext
            )
            Task {
                try? await DailyReconciler.reconcileAndNotify(in: modelContext)
            }
            dismiss()
        } catch {
            saveError = "The entry was not saved. Try again."
        }
    }
}

// MARK: - Today contribution

extension HydrationModuleAdapter: TodayContributing {
    func todayContribution(in context: ModuleContext) -> TodayContribution? {
        let modelContext = context.modelContext
        let entries = HydrationRecords.activeEntries(
            for: PersistedDomainDay.encode(context.currentDomainDay),
            in: (try? modelContext.fetch(FetchDescriptor<HydrationEntryRecord>())) ?? []
        )
        let dayRecord = HydrationRecords.dayRecord(
            for: PersistedDomainDay.encode(context.currentDomainDay),
            in: (try? modelContext.fetch(FetchDescriptor<HydrationDayRecord>())) ?? []
        )
        let plan = HydrationPlanService.plan(in: modelContext)

        let total = HydrationRecords.total(intake: entries)
        let targetML = dayRecord?.targetMLSnapshot ?? plan?.targetML ?? 2500
        let state: ContributionState
        if entries.isEmpty {
            state = .optional
        } else if total >= targetML {
            state = .completed
        } else {
            state = .ongoing
        }

        return TodayContribution(
            metadata: metadata,
            state: state,
            accessibilitySummary: {
            let unit = UnitSystemOption(rawValue: context.unitSystemRaw) ?? .metric
            return "Hydration. \(HydrationVolumeFormatting.volume(total, unitSystem: unit)) of \(HydrationVolumeFormatting.volume(targetML, unitSystem: unit)) daily target. \(HydrationVolumeFormatting.percentage(of: total, targetML: targetML)) percent."
        }()
        )
    }

    func todaySection(in context: ModuleContext) -> AnyView? {
        AnyView(HydrationTodaySection())
    }
}
