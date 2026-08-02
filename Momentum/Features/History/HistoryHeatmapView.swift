import MomentumCore
import SwiftUI

struct CompactHistoryHeatmapView: View {
    let currentDay: DomainDay
    let calendar: Calendar
    let score: (DomainDay) -> DailyAdherenceScore

    private var days: [DomainDay] {
        HistoryProjection.heatmapDays(endingOn: currentDay, calendar: calendar)
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHGrid(
                rows: Array(repeating: GridItem(.fixed(14), spacing: 3), count: 7),
                spacing: 3
            ) {
                ForEach(days, id: \.self) { day in
                    let value = score(day)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color(for: value))
                        .frame(width: 14, height: 14)
                        .overlay {
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                        }
                        .accessibilityLabel(accessibilityLabel(for: day, score: value))
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
    }

    private func color(for score: DailyAdherenceScore) -> Color {
        switch score {
        case .noObligation: Color.secondary.opacity(0.12)
        case let .score(_, _, percentage):
            switch percentage {
            case ...25: MomentumTheme.pulse.opacity(0.2)
            case ...50: MomentumTheme.pulse.opacity(0.4)
            case ...75: MomentumTheme.pulse.opacity(0.65)
            default: MomentumTheme.pulse
            }
        }
    }

    private func accessibilityLabel(for day: DomainDay, score: DailyAdherenceScore) -> String {
        let date = day.historyDate?.formatted(date: .complete, time: .omitted)
            ?? PersistedDomainDay.encode(day)
        switch score {
        case .noObligation:
            return "\(date), no recorded obligation"
        case let .score(completed, due, percentage):
            return "\(date), \(percentage.formatted(.number.precision(.fractionLength(0)))) percent, \(completed) of \(due) completed"
        }
    }
}

struct HistoryHeatmapView: View {
    let currentDay: DomainDay
    @Binding var page: Int
    let calendar: Calendar
    let score: (DomainDay) -> DailyAdherenceScore

    private var days: [DomainDay] {
        HistoryProjection.heatmapDays(
            endingOn: currentDay.adding(days: page * 16 * 7, calendar: calendar),
            calendar: calendar
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.sm) {
            HStack {
                Button {
                    page -= 1
                } label: {
                    Label("Older 16 weeks", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }

                Spacer()
                Text(rangeLabel)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()

                Button {
                    page = min(0, page + 1)
                } label: {
                    Label("Newer 16 weeks", systemImage: "chevron.right")
                        .labelStyle(.iconOnly)
                }
                .disabled(page == 0)
            }

            HStack(alignment: .top, spacing: MomentumSpacing.xs) {
                VStack(spacing: 3) {
                    ForEach(weekdayLabels, id: \.self) { label in
                        Text(label)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                            .accessibilityHidden(true)
                    }
                }

                ScrollView(.horizontal) {
                    LazyHGrid(
                        rows: Array(repeating: GridItem(.fixed(16), spacing: 3), count: 7),
                        spacing: 3
                    ) {
                        ForEach(days, id: \.self) { day in
                            let value = score(day)
                            NavigationLink(value: day) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(color(for: value))
                                    .frame(width: 16, height: 16)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 3)
                                            .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(accessibilityLabel(for: day, score: value))
                            .accessibilityHint("Opens history for this day")
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.hidden)
            }

            HStack(spacing: MomentumSpacing.xs) {
                Text("No obligation")
                ForEach([0.2, 0.4, 0.6, 0.8, 1.0], id: \.self) { opacity in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(MomentumTheme.pulse.opacity(opacity))
                        .frame(width: 13, height: 13)
                        .accessibilityHidden(true)
                }
                Text("Complete")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
    }

    private var rangeLabel: String {
        guard let first = days.first?.historyDate,
              let last = days.last?.historyDate else { return "16 weeks" }
        return "\(first.formatted(.dateTime.month(.abbreviated).day()))–\(last.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    private var weekdayLabels: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        return Array(symbols.dropFirst()) + Array(symbols.prefix(1))
    }

    private func color(for score: DailyAdherenceScore) -> Color {
        switch score {
        case .noObligation:
            return Color.secondary.opacity(0.12)
        case let .score(_, _, percentage):
            switch percentage {
            case ...25: return MomentumTheme.pulse.opacity(0.2)
            case ...50: return MomentumTheme.pulse.opacity(0.4)
            case ...75: return MomentumTheme.pulse.opacity(0.65)
            default: return MomentumTheme.pulse
            }
        }
    }

    private func accessibilityLabel(
        for day: DomainDay,
        score: DailyAdherenceScore
    ) -> String {
        let date = day.historyDate?.formatted(date: .complete, time: .omitted)
            ?? PersistedDomainDay.encode(day)
        switch score {
        case .noObligation:
            return "\(date), no recorded obligation"
        case let .score(completed, due, percentage):
            return "\(date), \(percentage.formatted(.number.precision(.fractionLength(0)))) percent, \(completed) of \(due) completed"
        }
    }
}

struct HistoryStreakSummaryView: View {
    let summary: HistoryStreakSummary
    let category: HistoryCategory

    var body: some View {
        Group {
            switch category {
            case .all:
                HStack(spacing: MomentumSpacing.md) {
                    streak("Workout", value: summary.workout, symbol: "figure.strengthtraining.traditional")
                    streak("Nutrition", value: summary.nutrition, symbol: "fork.knife")
                    streak("Care", value: summary.care, symbol: "sparkles")
                }
            case .workouts:
                streak("Workout opportunity streak", value: summary.workout, symbol: "figure.strengthtraining.traditional")
            case .nutrition:
                streak("Nutrition logging streak", value: summary.nutrition, symbol: "fork.knife")
            case .care:
                streak("Care streak", value: summary.care, symbol: "sparkles")
            case .measurements:
                Label("Measurements are facts, not adherence obligations.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func streak(_ title: String, value: Int, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(value == 1 ? "opportunity/day" : "opportunities/days")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct HistoryDayRow: View {
    let day: DomainDay
    let category: HistoryCategory
    let sessions: [WorkoutSessionRecord]
    let workoutEvents: [WorkoutDayEventRecord]
    let nutritionDays: [NutritionDayRecord]
    let foodEntries: [FoodEntryRecord]
    let careOccurrences: [CareOccurrenceRecord]
    let measurements: [BodyMeasurementRecord]

    private var dayKey: String { PersistedDomainDay.encode(day) }

    private var labels: [String] {
        var values: [String] = []
        if category == .all || category == .workouts {
            if sessions.contains(where: {
                $0.deletedAt == nil && $0.completionDomainDay == dayKey
            }) {
                values.append("Workout finished")
            } else if let event = workoutEvents.first(where: {
                $0.deletedAt == nil && $0.domainDay == dayKey
            }) {
                values.append("Workout \(event.kindRaw)")
            }
        }
        if category == .all || category == .nutrition {
            let foods = foodEntries.count {
                $0.deletedAt == nil && $0.domainDay == dayKey
            }
            if foods > 0 { values.append("\(foods) food \(foods == 1 ? "entry" : "entries")") }
            if nutritionDays.contains(where: { $0.domainDay == dayKey && $0.finalizedAt != nil }) {
                values.append("Nutrition finalized")
            }
        }
        if category == .all || category == .care {
            let care = careOccurrences.count { $0.dueDomainDay == dayKey }
            if care > 0 { values.append("\(care) care \(care == 1 ? "routine" : "routines")") }
        }
        if category == .all || category == .measurements {
            let count = measurements.count { $0.deletedAt == nil && $0.domainDay == dayKey }
            if count > 0 { values.append("\(count) \(count == 1 ? "measurement" : "measurements")") }
        }
        return values
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MomentumSpacing.xs) {
            Text(day.historyDate?.formatted(date: .abbreviated, time: .omitted) ?? dayKey)
                .font(.headline)
            Text(labels.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, MomentumSpacing.xs)
        .accessibilityElement(children: .combine)
    }
}

extension DomainDay {
    var historyDate: Date? {
        PersistedDomainDay.date(for: self, calendar: .autoupdatingCurrent)
    }
}
