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
        do {
            let container = try Self.makeContainer(for: PersistenceStoreMode.current())
            try SeedData.install(in: container.mainContext)
            self = .ready(container)
        } catch {
            self = .failed
        }
    }

    private static func makeContainer(for mode: PersistenceStoreMode) throws -> ModelContainer {
        switch mode {
        case .production:
            try ModelContainerFactory.makeProduction()
        case .localDevelopment:
            try ModelContainerFactory.makeLocalDevelopment()
        case .preview:
            try ModelContainerFactory.makePreview()
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
