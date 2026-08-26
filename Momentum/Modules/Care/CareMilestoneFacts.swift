import MomentumCore
import SwiftData

// MARK: - Milestone contribution

extension CareModuleAdapter: MilestoneContributing {
    func milestoneFacts(in context: ModuleContext) -> [MilestoneFact] {
        let occurrences = ((try? context.modelContext.fetch(FetchDescriptor<CareOccurrenceRecord>())) ?? [])
            .filter { $0.statusRaw != "repairedDuplicate" }

        return Dictionary(grouping: occurrences, by: \.dueDomainDay)
            .compactMap { dayValue, dayOccurrences -> MilestoneFact? in
                guard let day = PersistedDomainDay.decode(dayValue) else { return nil }
                return .personalCareDay(
                    day: day,
                    isFullyCompleted: dayOccurrences.allSatisfy { $0.statusRaw == "completed" },
                    lastActivityAt: dayOccurrences.compactMap(\.completedAt).max()
                        ?? dayOccurrences.map(\.updatedAt).max()
                        ?? .distantPast
                )
            }
    }
}
