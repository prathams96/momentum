import MomentumCore
import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettingsRecord]
    @Query(sort: \WorkoutTemplateRecord.sequenceIndex) private var workouts: [WorkoutTemplateRecord]
    @Query private var anchors: [CycleAnchorRecord]

    @State private var step = 0
    @State private var dueToday = true
    @State private var calorieTarget = "2400"
    @State private var calorieMinimum = "2300"
    @State private var calorieMaximum = "2500"
    @State private var proteinMinimum = "150"

    private let stepCount = 3

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
            cycleStep
        default:
            settingsStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.lg) {
            ThreadEmblem()

            VStack(alignment: .leading, spacing: MomentumSpacing.sm) {
                Text("One promise. Every day.")
                    .font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)

                Text("Momentum turns today’s obligations into a small, concrete sequence—workout, food, and care in one private place.")
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

    private var cycleStep: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.lg) {
            VStack(alignment: .leading, spacing: MomentumSpacing.sm) {
                Text("Your cycle, in sequence")
                    .font(.title.bold())

                Text("Four workouts move forward one completion at a time. Recovery days never reset the order.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(workouts.enumerated()), id: \.element.id) { index, workout in
                    HStack(spacing: MomentumSpacing.md) {
                        Text("\(index + 1)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(index == 0 ? MomentumTheme.pulse : .secondary)
                            .frame(width: 28, height: 28)
                            .background(index == 0 ? MomentumTheme.pulseWash : Color.secondary.opacity(0.10))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(workout.name)
                                .font(.headline)
                            Text(workout.focus)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 0)

                        if index == 0 {
                            Text("Next")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MomentumTheme.pulseDeep)
                        }
                    }
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

            VStack(alignment: .leading, spacing: MomentumSpacing.sm) {
                Toggle(isOn: $dueToday) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upper A is due today")
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

            VStack(alignment: .leading, spacing: MomentumSpacing.md) {
                Text("Nutrition starting points")
                    .font(.headline)

                NutritionField(label: "Daily calories", value: $calorieTarget, suffix: "kcal")
                HStack(spacing: MomentumSpacing.sm) {
                    NutritionField(label: "Range from", value: $calorieMinimum, suffix: "kcal")
                    NutritionField(label: "Range to", value: $calorieMaximum, suffix: "kcal")
                }
                NutritionField(label: "Protein minimum", value: $proteinMinimum, suffix: "g")
            }
        }
    }

    private var footer: some View {
        Button(action: advance) {
            Text(buttonTitle)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(MomentumTheme.pulse)
        .controlSize(.large)
        .accessibilityHint(step == stepCount - 1 ? "Completes onboarding" : "Moves to the next setup step")
    }

    private var stepLabel: String {
        switch step {
        case 0: "A private system for the things you keep"
        case 1: "The workout cycle"
        default: "Your starting points"
        }
    }

    private var buttonTitle: String {
        switch step {
        case 0: "See the plan"
        case 1: "Keep Upper A next"
        default: "Start with Upper A"
        }
    }

    private func advance() {
        guard step < stepCount - 1 else {
            completeOnboarding()
            return
        }

        withAnimation(.easeOut(duration: 0.2)) {
            step += 1
        }
    }

    private func completeOnboarding() {
        guard let settings = settings.first else { return }

        settings.onboardingCompleted = true
        settings.calorieTarget = Int(calorieTarget) ?? 2400
        settings.calorieMinimum = Int(calorieMinimum) ?? 2300
        settings.calorieMaximum = Int(calorieMaximum) ?? 2500
        settings.proteinMinimum = Int(proteinMinimum) ?? 150
        settings.updatedAt = .now

        if let anchor = anchors.first {
            let calendar = Calendar.autoupdatingCurrent
            let currentDay = DomainDay.containing(
                .now,
                calendar: calendar,
                cutoffMinutes: settings.domainDayCutoffMinutes
            )
            let dueDay = dueToday ? currentDay : currentDay.adding(days: 1, calendar: calendar)
            anchor.firstDueDomainDay = encode(dueDay)
            anchor.updatedAt = .now
        }

        try? modelContext.save()
    }

    private func encode(_ day: DomainDay) -> String {
        "\(day.year)-\(String(format: "%02d", day.month))-\(String(format: "%02d", day.day))"
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
