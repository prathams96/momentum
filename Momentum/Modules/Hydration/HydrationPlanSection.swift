import MomentumCore
import SwiftData
import SwiftUI

// MARK: - Plan contribution

extension HydrationModuleAdapter: PlanContributing {
    func planSection(in context: ModuleContext) -> AnyView? {
        AnyView(HydrationPlanSection())
    }
}

/// The hydration module's contribution to the Plans surface: the daily
/// target, three quick-add preset amounts, and reminder checkpoints.
/// Amounts are edited in the global unit system and stored as millilitres.
struct HydrationPlanSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettingsRecord]
    @Query private var hydrationPlans: [HydrationPlanRecord]

    @State private var targetML = 2500
    @State private var firstPresetML = 250
    @State private var secondPresetML = 500
    @State private var thirdPresetML = 750
    @State private var remindersEnabled = false
    @State private var firstCheckpointMinutes = 11 * 60
    @State private var secondCheckpointMinutes = 15 * 60
    @State private var thirdCheckpointMinutes = 19 * 60
    @State private var didLoad = false
    @State private var saveError: String?

    private var unitSystem: UnitSystemOption {
        UnitSystemOption(rawValue: AppSettingsRecord.canonical(in: settings)?.unitSystemRaw ?? "metric") ?? .metric
    }

    private var currentDomainDay: DomainDay {
        ScheduleProjection.currentDomainDay(settings: settings, now: .now, calendar: .autoupdatingCurrent)
    }

    private var plan: HydrationPlanRecord? {
        hydrationPlans.min { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }

    var body: some View {
        Section {
            if unitSystem == .metric {
                Stepper("Daily target: \(targetML) ml", value: $targetML, in: 500...10_000, step: 100)
                Stepper("First preset: \(firstPresetML) ml", value: $firstPresetML, in: 50...2_000, step: 50)
                Stepper("Second preset: \(secondPresetML) ml", value: $secondPresetML, in: 50...2_000, step: 50)
                Stepper("Third preset: \(thirdPresetML) ml", value: $thirdPresetML, in: 50...2_000, step: 50)
            } else {
                Stepper("Daily target: \(HydrationEngine.fluidOunces(fromML: targetML)) fl oz", value: targetOunces, in: 17...338, step: 1)
                Stepper("First preset: \(HydrationEngine.fluidOunces(fromML: firstPresetML)) fl oz", value: firstPresetOunces, in: 2...68, step: 1)
                Stepper("Second preset: \(HydrationEngine.fluidOunces(fromML: secondPresetML)) fl oz", value: secondPresetOunces, in: 2...68, step: 1)
                Stepper("Third preset: \(HydrationEngine.fluidOunces(fromML: thirdPresetML)) fl oz", value: thirdPresetOunces, in: 2...68, step: 1)
            }

            Toggle("Reminders", isOn: $remindersEnabled)
            if remindersEnabled {
                DatePicker("First checkpoint", selection: checkpointBinding($firstCheckpointMinutes), displayedComponents: .hourAndMinute)
                DatePicker("Second checkpoint", selection: checkpointBinding($secondCheckpointMinutes), displayedComponents: .hourAndMinute)
                DatePicker("Third checkpoint", selection: checkpointBinding($thirdCheckpointMinutes), displayedComponents: .hourAndMinute)
                Text("Checkpoints only fire while you are behind your water pace, between 09:00 and 21:00, at most three per day.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button("Save plan") { savePlan() }
                .buttonStyle(.borderedProminent)
        } header: {
            Text("Hydration")
        } footer: {
            Text("Days already logged keep their own target snapshot; edits apply from now on.")
        }
        .onAppear(perform: load)
        .alert("Couldn’t save plan", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "Your existing plan is unchanged.")
        }
    }

    private func load() {
        guard !didLoad else { return }
        if let plan {
            targetML = plan.targetML
            firstPresetML = plan.firstPresetML
            secondPresetML = plan.secondPresetML
            thirdPresetML = plan.thirdPresetML
            remindersEnabled = plan.remindersEnabled
            firstCheckpointMinutes = plan.firstCheckpointMinutes
            secondCheckpointMinutes = plan.secondCheckpointMinutes
            thirdCheckpointMinutes = plan.thirdCheckpointMinutes
        }
        didLoad = true
    }

    private var targetOunces: Binding<Int> {
        ouncesBinding(ml: $targetML, minimum: HydrationEngine.millilitres(fromFluidOunces: 17))
    }
    private var firstPresetOunces: Binding<Int> {
        ouncesBinding(ml: $firstPresetML)
    }
    private var secondPresetOunces: Binding<Int> {
        ouncesBinding(ml: $secondPresetML)
    }
    private var thirdPresetOunces: Binding<Int> {
        ouncesBinding(ml: $thirdPresetML)
    }

    private func ouncesBinding(ml: Binding<Int>, minimum: Int = 50) -> Binding<Int> {
        Binding(
            get: { HydrationEngine.fluidOunces(fromML: ml.wrappedValue) },
            set: { ml.wrappedValue = max(HydrationEngine.millilitres(fromFluidOunces: $0), minimum) }
        )
    }

    private func checkpointBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    from: DateComponents(hour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60)
                ) ?? .now
            },
            set: {
                let components = Calendar.current.dateComponents([.hour, .minute], from: $0)
                minutes.wrappedValue = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }

    private func savePlan() {
        do {
            try HydrationPlanService.savePlan(
                domainDay: currentDomainDay,
                in: modelContext
            ) { plan in
                plan.targetML = targetML
                plan.firstPresetML = firstPresetML
                plan.secondPresetML = secondPresetML
                plan.thirdPresetML = thirdPresetML
                plan.remindersEnabled = remindersEnabled
                plan.firstCheckpointMinutes = firstCheckpointMinutes
                plan.secondCheckpointMinutes = secondCheckpointMinutes
                plan.thirdCheckpointMinutes = thirdCheckpointMinutes
            }
        } catch {
            saveError = "The hydration plan was not saved."
        }
    }
}
