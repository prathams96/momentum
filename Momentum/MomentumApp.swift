import SwiftUI
import SwiftData

@main
@MainActor
struct MomentumApp: App {
    private let bootstrap: PersistenceBootstrap

    init() {
        bootstrap = PersistenceBootstrap()
    }

    var body: some Scene {
        WindowGroup {
            switch bootstrap {
            case .ready(let container):
                AppShell()
                    .modelContainer(container)
            case .failed:
                PersistenceUnavailableView()
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
        if isRunningTests || ProcessInfo.processInfo.arguments.contains("-usePreviewStore") {
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
    var body: some View {
        ContentUnavailableView(
            "Momentum is unavailable",
            systemImage: "externaldrive.badge.exclamationmark",
            description: Text("Try opening the app again. Your local data has not been replaced.")
        )
    }
}
