import SwiftUI
import SwiftData

@main
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

private enum PersistenceBootstrap {
    case ready(ModelContainer)
    case failed

    init() {
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if isRunningTests || ProcessInfo.processInfo.arguments.contains("-usePreviewStore") {
            do {
                self = .ready(try ModelContainerFactory.makePreview())
            } catch {
                self = .failed
            }
            return
        }

        do {
            self = .ready(try ModelContainerFactory.makeProduction())
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
