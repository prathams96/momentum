import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettingsRecord]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: MomentumSpacing.lg) {
                Spacer()

                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(MomentumTheme.pulse)
                    .accessibilityHidden(true)

                Text("A clear next action.")
                    .font(.largeTitle.bold())

                Text("Momentum keeps your workout cycle, food log, and care routines private and local-first.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: MomentumSpacing.sm) {
                    Label("Upper A is next", systemImage: "figure.strengthtraining.traditional")
                    Label("Recovery follows the workout you finish", systemImage: "arrow.triangle.2.circlepath")
                    Label("Your data stays yours", systemImage: "lock.shield")
                }
                .font(.headline)

                Spacer()

                Button("Start with Upper A", action: completeOnboarding)
                    .buttonStyle(.borderedProminent)
                    .tint(MomentumTheme.pulse)
                    .frame(maxWidth: .infinity)
                    .controlSize(.large)
            }
            .padding(MomentumSpacing.lg)
            .navigationTitle("Welcome to Momentum")
        }
    }

    private func completeOnboarding() {
        guard let settings = settings.first else { return }
        settings.onboardingCompleted = true
        settings.updatedAt = .now
        try? modelContext.save()
    }
}
