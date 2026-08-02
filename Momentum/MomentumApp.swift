import SwiftUI
import SwiftData

@main
@MainActor
struct MomentumApp: App {
    @State private var bootstrap = PersistenceBootstrap()

    var body: some Scene {
        WindowGroup {
            switch bootstrap {
            case .ready(let container):
                AppShell()
                    .modelContainer(container)
            case .failed:
                PersistenceUnavailableView {
                    bootstrap = PersistenceBootstrap()
                }
            }
        }
    }
}

@MainActor
private enum PersistenceBootstrap {
    case ready(ModelContainer)
    case failed

    init() {
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        #if targetEnvironment(simulator)
        let isRunningInSimulator = true
        #else
        let isRunningInSimulator = false
        #endif

        if isRunningTests || isRunningInSimulator || ProcessInfo.processInfo.arguments.contains("-usePreviewStore") {
            do {
                let container = try ModelContainerFactory.makePreview()
                try SeedData.install(in: container.mainContext)
                self = .ready(container)
            } catch {
                self = .failed
            }
            return
        }

        do {
            let container = try ModelContainerFactory.makeProduction()
            try SeedData.install(in: container.mainContext)
            self = .ready(container)
        } catch {
            self = .failed
        }
    }
}

private struct PersistenceUnavailableView: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ContentUnavailableView(
                "Momentum is unavailable",
                systemImage: "externaldrive.badge.exclamationmark",
                description: Text("Your local data has not been replaced. Try opening it again.")
            )

            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
