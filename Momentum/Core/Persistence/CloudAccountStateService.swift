import CloudKit
import Foundation
import OSLog
import SwiftData

enum CloudAccountAvailability: Equatable {
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
}

enum CloudAccountStatePolicy {
    static func status(
        storeMode: PersistenceStoreMode,
        availability: CloudAccountAvailability?
    ) -> String {
        guard storeMode == .production else { return "localOnly" }

        switch availability {
        case .available:
            // Account availability is not proof that a SwiftData import/export completed.
            return "syncing"
        case .noAccount:
            return "noAccount"
        case .restricted:
            return "restricted"
        case .temporarilyUnavailable, .couldNotDetermine, .none:
            return "unavailable"
        }
    }
}

@MainActor
enum CloudAccountStateService {
    static func refresh(
        in context: ModelContext,
        storeMode: PersistenceStoreMode = .current(),
        now: Date = .now
    ) async throws {
        let interval = MomentumDiagnostics.signposter.beginInterval("CloudAccountStateProcessing")
        defer {
            MomentumDiagnostics.signposter.endInterval("CloudAccountStateProcessing", interval)
        }

        let availability: CloudAccountAvailability?
        if storeMode == .production {
            do {
                let status = try await CKContainer(
                    identifier: ModelContainerFactory.cloudContainerIdentifier
                ).accountStatus()
                availability = map(status)
            } catch {
                availability = .couldNotDetermine
            }
        } else {
            availability = nil
        }

        guard let settings = AppSettingsRecord.canonical(
            in: try context.fetch(FetchDescriptor<AppSettingsRecord>())
        ) else { return }

        settings.iCloudStatusRaw = CloudAccountStatePolicy.status(
            storeMode: storeMode,
            availability: availability
        )
        settings.iCloudStatusUpdatedAt = now
        // Deliberately do not write lastSuccessfulSyncAt. CK account availability
        // says nothing about whether SwiftData completed an import or export.
        try context.save()
    }

    private static func map(_ status: CKAccountStatus) -> CloudAccountAvailability {
        switch status {
        case .available: .available
        case .noAccount: .noAccount
        case .restricted: .restricted
        case .temporarilyUnavailable: .temporarilyUnavailable
        case .couldNotDetermine: .couldNotDetermine
        @unknown default: .couldNotDetermine
        }
    }
}
