import MomentumCore
import SwiftData
import SwiftUI

/// The hydration module's contribution to one recorded history day: the
/// day total against its own target snapshot plus an entry list with
/// amount/time editing and soft deletion.
struct HydrationHistoryDaySection: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettingsRecord]
    @Query private var hydrationPlans: [HydrationPlanRecord]
    @Query private var hydrationEntries: [HydrationEntryRecord]
    @Query private var hydrationDays: [HydrationDayRecord]

    @State private var editingEntry: HydrationEntryRecord?
    @State private var correctionError: String?

    let day: DomainDay

    private var unitSystem: UnitSystemOption {
        UnitSystemOption(rawValue: AppSettingsRecord.canonical(in: settings)?.unitSystemRaw ?? "metric") ?? .metric
    }

    private var dayKey: String { PersistedDomainDay.encode(day) }

    private var dayEntries: [HydrationEntryRecord] {
        HydrationRecords.activeEntries(for: dayKey, in: hydrationEntries)
    }

    private var dayRecord: HydrationDayRecord? {
        HydrationRecords.dayRecord(for: dayKey, in: hydrationDays)
    }

    private var targetML: Int {
        dayRecord?.targetMLSnapshot
            ?? hydrationPlans.min { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }?.targetML
            ?? 0
    }

    private var totalML: Int {
        HydrationRecords.total(intake: dayEntries)
    }

    var body: some View {
        Section("Hydration") {
            LabeledContent(
                "Day total",
                value: "\(HydrationVolumeFormatting.volume(totalML)) of \(HydrationVolumeFormatting.volume(targetML))"
            )
            Label(
                totalML >= targetML ? "Target reached" : "Target not reached",
                systemImage: totalML >= targetML ? "checkmark.circle.fill" : "circle.dashed"
            )
            .foregroundStyle(totalML >= targetML ? MomentumTheme.success : .secondary)

            if dayEntries.isEmpty {
                Text("No water logged")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dayEntries) { entry in
                    HStack {
                        Text(entry.consumedAt.formatted(date: .omitted, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(HydrationVolumeFormatting.volume(entry.amountML))
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .swipeActions(edge: .leading) {
                        Button("Edit") { editingEntry = entry }
                            .tint(MomentumTheme.dataCyan)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) { delete(entry) }
                    }
                    .contextMenu {
                        Button("Edit entry") { editingEntry = entry }
                        Button("Delete entry", role: .destructive) { delete(entry) }
                    }
                }
            }
        }
        .sheet(item: $editingEntry) { entry in
            HydrationHistoryEditSheet(
                entry: entry,
                unitSystem: unitSystem
            )
        }
        .alert("History couldn’t be refreshed", isPresented: Binding(
            get: { correctionError != nil },
            set: { if !$0 { correctionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(correctionError ?? "The correction was saved. Try refreshing again.")
        }
    }

    private func delete(_ entry: HydrationEntryRecord) {
        do {
            try HydrationEntryService.delete(entry, in: modelContext)
            reconcile()
        } catch {
            correctionError = "The entry is still visible because the deletion could not be saved."
        }
    }

    private func reconcile() {
        Task { @MainActor in
            do {
                try await DailyReconciler.reconcileAndNotify(in: modelContext)
            } catch {
                correctionError = "The correction was saved, but reminders could not be refreshed."
            }
        }
    }
}

private struct HydrationHistoryEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var amount: Double = 0
    @State private var consumedAt: Date = .now
    @State private var saveError: String?

    let entry: HydrationEntryRecord
    let unitSystem: UnitSystemOption

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
                    DatePicker(
                        "Time",
                        selection: $consumedAt,
                        in: dayBounds,
                        displayedComponents: .hourAndMinute
                    )
                } footer: {
                    Text("Time stays within this day; entries never move between days.")
                }
            }
            .navigationTitle("Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(amount <= 0)
                }
            }
            .onAppear(perform: load)
            .alert("Couldn’t save entry", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) { Button("OK", role: .cancel) {} } message: {
                Text(saveError ?? "Try again.")
            }
        }
        .presentationDetents([.medium])
    }

    private var dayBounds: ClosedRange<Date> {
        let calendar = Calendar.current
        let start = PersistedDomainDay.date(for: PersistedDomainDay.decode(entry.domainDay) ?? DomainDay(year: 2000, month: 1, day: 1), calendar: calendar, hour: 0, minute: 0) ?? .distantPast
        let end = calendar.date(byAdding: DateComponents(day: 1, minute: -1), to: start) ?? .now
        return start...end
    }

    private func load() {
        amount = Double(entry.amountML)
        consumedAt = entry.consumedAt
    }

    private func save() {
        let amountML: Int
        switch unitSystem {
        case .metric:
            amountML = Int(amount.rounded())
        case .imperial:
            amountML = HydrationEngine.millilitres(fromFluidOunces: Int(amount.rounded()))
        }
        guard amountML > 0 else {
            saveError = "Enter an amount greater than zero."
            return
        }
        do {
            try HydrationEntryService.edit(
                entry,
                amountML: amountML,
                consumedAt: consumedAt,
                in: modelContext
            )
            Task { try? await DailyReconciler.reconcileAndNotify(in: modelContext) }
            dismiss()
        } catch {
            saveError = "The entry was not changed."
        }
    }
}

// MARK: - History contribution

extension HydrationModuleAdapter: HistoryContributing {
    /// One fact per day that has a day record or entries, judged against that
    /// day's own frozen snapshot.
    func historyFacts(in context: ModuleContext) -> [HistoryAdherenceFact] {
        let modelContext = context.modelContext
        let dayRecords = (try? modelContext.fetch(FetchDescriptor<HydrationDayRecord>())) ?? []
        let entries = (try? modelContext.fetch(FetchDescriptor<HydrationEntryRecord>())) ?? []
        let plan = HydrationPlanService.plan(in: modelContext)

        var days = Set(dayRecords.map(\.domainDay))
        days.formUnion(entries.filter { $0.deletedAt == nil }.map(\.domainDay))

        let recordByDay = Dictionary(
            dayRecords.map { ($0.domainDay, $0) },
            uniquingKeysWith: { lhs, rhs in lhs.createdAt <= rhs.createdAt ? lhs : rhs }
        )

        return days.compactMap { dayKey -> HistoryAdherenceFact? in
            guard let domainDay = PersistedDomainDay.decode(dayKey) else { return nil }
            guard let snapshot = recordByDay[dayKey]?.targetMLSnapshot ?? plan?.targetML else { return nil }
            let total = HydrationRecords.total(intake: HydrationRecords.activeEntries(for: dayKey, in: entries))
            return HistoryAdherenceFact(
                day: domainDay,
                category: .hydration,
                isCompleted: total >= snapshot
            )
        }
        .sorted { $0.day < $1.day }
    }

    func historyDaySections(for day: DomainDay, in context: ModuleContext) -> [AnyView] {
        [AnyView(HydrationHistoryDaySection(day: day))]
    }

    func categoryStreak(asOf day: DomainDay, in context: ModuleContext) -> Int? {
        let facts = historyFacts(in: context).filter { $0.day <= day }
        let pausedDays = ModuleEnablementLedger.pausedDays(
            for: metadata.id,
            through: day,
            calendar: context.calendar,
            in: context.modelContext
        )
        let recordedDays = Set(facts.map(\.day))
        let engine = AdherenceEngine()
        let adherenceDays = facts.map {
            HydrationAdherenceDay(day: $0.day, isTargetReached: $0.isCompleted)
        } + pausedDays
            .filter { !recordedDays.contains($0) }
            .map { HydrationAdherenceDay(day: $0, isTargetReached: false, isPaused: true) }
        return engine.hydrationStreak(days: adherenceDays, calendar: context.calendar)
    }

    func adherenceActivities(on day: DomainDay, facts: [HistoryAdherenceFact]) -> [DueAdherenceActivity] {
        let matching = facts.filter { $0.day == day && $0.category == .hydration }
        guard !matching.isEmpty else { return [] }
        return [DueAdherenceActivity(
            kind: .hydration,
            isCompleted: matching.contains(where: \.isCompleted)
        )]
    }
}
