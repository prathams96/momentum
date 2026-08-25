import Foundation
import MomentumCore
import SwiftData
import SwiftUI

/// Measurement domain types retained after the Progress measurement cut:
/// BodyMeasurementRecord stays in the schema and CSV export, and these
/// helpers remain available to tests and future surfaces.

enum MeasurementKind: String, CaseIterable, Identifiable {
    case weight = "weightKg"
    case waist = "waistCm"
    var id: String { rawValue }
    var title: String { self == .weight ? "Weight" : "Waist" }

    func displayValue(metricValue: Double, unitSystem: UnitSystemOption) -> Double {
        guard unitSystem == .imperial else { return metricValue }
        return self == .weight ? metricValue * 2.204_622_621_8 : metricValue * 0.393_700_787_4
    }

    func metricValue(displayValue: Double, unitSystem: UnitSystemOption) -> Double {
        guard unitSystem == .imperial else { return displayValue }
        return self == .weight ? displayValue / 2.204_622_621_8 : displayValue / 0.393_700_787_4
    }

    func unit(unitSystem: UnitSystemOption) -> String {
        if unitSystem == .metric { return self == .weight ? "kg" : "cm" }
        return self == .weight ? "lb" : "in"
    }

    func formatted(metricValue: Double, unitSystem: UnitSystemOption) -> String {
        "\(DecimalFormatter.onePlace(displayValue(metricValue: metricValue, unitSystem: unitSystem))) \(unit(unitSystem: unitSystem))"
    }
}

struct MeasurementPoint: Identifiable {
    let id: UUID
    let date: Date
    let value: Double
}

enum WeightTrendProjection {
    static func sevenDayAverages(
        observations: [MeasurementPoint],
        calendar: Calendar,
        minimumDistinctDays: Int = 2
    ) -> [MeasurementPoint] {
        let dailyPoints = Dictionary(grouping: observations) {
            calendar.startOfDay(for: $0.date)
        }.map { date, values in
            let value = values.map(\.value).reduce(0, +) / Double(values.count)
            let id = values.map(\.id).min { $0.uuidString < $1.uuidString } ?? UUID()
            return MeasurementPoint(id: id, date: date, value: value)
        }.sorted { $0.date < $1.date }

        return dailyPoints.compactMap { point in
            let start = calendar.date(byAdding: .day, value: -6, to: point.date) ?? point.date
            let window = dailyPoints.filter { $0.date >= start && $0.date <= point.date }
            guard window.count >= minimumDistinctDays else { return nil }
            let average = window.map(\.value).reduce(0, +) / Double(window.count)
            return MeasurementPoint(id: point.id, date: point.date, value: average)
        }
    }
}

@MainActor
enum MeasurementService {
    static func save(
        existing: BodyMeasurementRecord?,
        kind: MeasurementKind,
        metricValue: Double,
        measuredAt: Date,
        cutoffMinutes: Int,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        in context: ModelContext
    ) throws {
        let day = DomainDay.containing(measuredAt, calendar: calendar, cutoffMinutes: cutoffMinutes)
        let record = existing ?? BodyMeasurementRecord(
            kindRaw: kind.rawValue,
            value: metricValue,
            measuredAt: measuredAt,
            domainDay: PersistedDomainDay.encode(day)
        )
        if existing == nil { context.insert(record) }
        record.kindRaw = kind.rawValue
        record.value = metricValue
        record.measuredAt = measuredAt
        record.domainDay = PersistedDomainDay.encode(day)
        record.updatedAt = now
        record.deletedAt = nil
        try PlanEditingService.save(context)
    }

    static func delete(_ record: BodyMeasurementRecord, now: Date = .now, in context: ModelContext) throws {
        record.deletedAt = now
        record.updatedAt = now
        try PlanEditingService.save(context)
    }
}
