import Foundation
import MomentumCore
import SwiftData
import SwiftUI

/// Wraps the hydration domain behind the module contracts. Records, engines,
/// and services stay inside the module boundary; shared surfaces see only
/// this adapter.
@MainActor
final class HydrationModuleAdapter: MomentumModule {
    let metadata = ModuleMetadata(
        id: BuiltInModuleID.hydration,
        displayName: "Hydration",
        symbolName: "drop.fill",
        tint: MomentumTheme.dataCyan,
        todayRank: 40
    )

    init() {}
}

// MARK: - Module-internal vocabulary

enum HydrationFactKind {
    static let moduleIDRaw = "hydration"
    static let entryLogged = "entryLogged"
    static let targetReached = "targetReached"
    static let planEdited = "planEdited"
}

enum HydrationVolumeFormatting {
    /// "1.6 L" / "750 ml" metric, or whole fluid ounces ("17 fl oz") in
    /// imperial locales. Storage stays millilitre-canonical either way.
    static func volume(_ millilitres: Int, unitSystem: UnitSystemOption) -> String {
        guard unitSystem == .imperial else { return volume(millilitres) }
        return "\(HydrationEngine.fluidOunces(fromML: millilitres)) fl oz"
    }

    /// "1.6 L" for values of at least a litre, otherwise "750 ml".
    static func volume(_ millilitres: Int) -> String {
        guard millilitres >= 1000 else { return "\(millilitres) ml" }
        return "\(litres(millilitres)) L"
    }

    /// "1.6" — litre value with up to one decimal, no unit.
    static func litres(_ millilitres: Int) -> String {
        (Double(millilitres) / 1000).formatted(.number.precision(.fractionLength(0...1)))
    }

    static func percentage(of totalML: Int, targetML: Int) -> Int {
        guard targetML > 0 else { return 0 }
        return Int((Double(totalML) / Double(targetML) * 100).rounded())
    }
}

// MARK: - Shared record queries

@MainActor
enum HydrationRecords {
    static func activeEntries(for dayKey: String, in entries: [HydrationEntryRecord]) -> [HydrationEntryRecord] {
        entries
            .filter { $0.domainDay == dayKey && $0.deletedAt == nil }
            .sorted { ($0.consumedAt, $0.id.uuidString) < ($1.consumedAt, $1.id.uuidString) }
    }

    static func total(intake entries: [HydrationEntryRecord]) -> Int {
        entries.reduce(0) { $0 + $1.amountML }
    }

    /// Canonical per-day record; duplicates are resolved by earliest creation.
    static func dayRecord(for dayKey: String, in records: [HydrationDayRecord]) -> HydrationDayRecord? {
        records
            .filter { $0.domainDay == dayKey }
            .min { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }

    static func firedSlots(from raw: String) -> Set<Int> {
        Set(raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
    }

    static func encode(firedSlots: Set<Int>) -> String {
        firedSlots.sorted().map(String.init).joined(separator: ",")
    }

    @discardableResult
    static func ensureDayRecord(
        for dayKey: String,
        plan: HydrationPlanRecord,
        now: Date,
        in context: ModelContext
    ) -> HydrationDayRecord {
        let existing = dayRecord(
            for: dayKey,
            in: (try? context.fetch(FetchDescriptor<HydrationDayRecord>())) ?? []
        )
        if let existing { return existing }
        let record = HydrationDayRecord(domainDay: dayKey, targetMLSnapshot: plan.targetML)
        context.insert(record)
        return record
    }

    static func emitFact(
        kind: String,
        domainDay: String,
        subjectID: UUID? = nil,
        now: Date = .now,
        in context: ModelContext
    ) {
        context.insert(ModuleFactRecord(
            moduleIDRaw: HydrationFactKind.moduleIDRaw,
            kindRaw: kind,
            domainDay: domainDay,
            subjectID: subjectID,
            createdAt: now
        ))
    }

    static func hasFact(kind: String, domainDay: String, in context: ModelContext) -> Bool {
        let facts = (try? context.fetch(FetchDescriptor<ModuleFactRecord>())) ?? []
        return facts.contains {
            $0.moduleIDRaw == HydrationFactKind.moduleIDRaw
                && $0.kindRaw == kind
                && $0.domainDay == domainDay
        }
    }

    /// Insert-only semantics: the fact is emitted exactly once per day even
    /// after delete/re-log crossings of the frozen target.
    static func emitTargetReachedOnce(
        dayKey: String,
        dayRecord: HydrationDayRecord,
        now: Date,
        in context: ModelContext
    ) {
        let entries = activeEntries(
            for: dayKey,
            in: (try? context.fetch(FetchDescriptor<HydrationEntryRecord>())) ?? []
        )
        guard total(intake: entries) >= dayRecord.targetMLSnapshot else { return }
        guard !hasFact(kind: HydrationFactKind.targetReached, domainDay: dayKey, in: context) else { return }
        emitFact(kind: HydrationFactKind.targetReached, domainDay: dayKey, now: now, in: context)
    }
}
