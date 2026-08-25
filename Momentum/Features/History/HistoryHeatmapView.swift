import MomentumCore
import SwiftUI

/// One visual language for every rhythm cell — strip, drill-down heatmap,
/// and VoiceOver alike (pre-launch spec §3).
///
/// - complete / partial / missed: five tonal steps of Momentum Pulse.
/// - recovery / no obligation: outline only, never confused with missed.
/// - paused (module-disabled interval): dimmed fill plus distinct outline;
///   VoiceOver says "paused, not broken".
enum RhythmCellPresentation: Equatable {
    case scored(percentage: Double)
    case noObligation
    case paused

    init(score: DailyAdherenceScore, isPaused: Bool) {
        if isPaused {
            self = .paused
        } else {
            switch score {
            case .noObligation: self = .noObligation
            case let .score(_, _, percentage): self = .scored(percentage: percentage)
            }
        }
    }

    /// Five-step tonal position for scored cells; nil for outlined states.
    var tonalStep: Int? {
        guard case let .scored(percentage) = self else { return nil }
        switch percentage {
        case ...0: return 0
        case ...25: return 1
        case ...50: return 2
        case ...75: return 3
        default: return 4
        }
    }

    private static let tonalOpacities: [Double] = [0.18, 0.35, 0.55, 0.75, 1.0]

    var fill: Color {
        switch self {
        case .paused:
            return Color.secondary.opacity(0.10)
        case .noObligation:
            return .clear
        case let .scored:
            return MomentumTheme.pulse.opacity(Self.tonalOpacities[tonalStep ?? 0])
        }
    }

    var stroke: Color {
        switch self {
        case .paused: Color.secondary.opacity(0.45)
        case .noObligation: Color.secondary.opacity(0.30)
        case .scored: .clear
        }
    }

    func accessibilityLabel(for day: DomainDay) -> String {
        let date = day.historyDate?.formatted(date: .complete, time: .omitted)
            ?? PersistedDomainDay.encode(day)
        switch self {
        case .paused:
            return "\(date), streak paused, not broken"
        case .noObligation:
            return "\(date), no obligation"
        case let .scored(percentage):
            if percentage >= 99.5 {
                return "\(date), complete"
            }
            return "\(date), \(percentage.formatted(.number.precision(.fractionLength(0)))) percent"
        }
    }
}

/// A rhythm cell drawn from the shared presentation language.
struct RhythmDayCell: View {
    let presentation: RhythmCellPresentation
    var cornerRadius: CGFloat = 3

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(presentation.fill)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(presentation.stroke, lineWidth: 1)
            }
    }
}

struct HistoryHeatmapView: View {
    let currentDay: DomainDay
    @Binding var page: Int
    let calendar: Calendar
    var pausedDays: Set<DomainDay> = []
    let score: (DomainDay) -> DailyAdherenceScore

    private var days: [DomainDay] {
        HistoryProjection.heatmapDays(
            endingOn: currentDay.adding(days: page * 16 * 7, calendar: calendar),
            calendar: calendar
        )
    }

    private func presentation(for day: DomainDay) -> RhythmCellPresentation {
        RhythmCellPresentation(score: score(day), isPaused: pausedDays.contains(day))
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
                            let presentation = presentation(for: day)
                            NavigationLink(value: day) {
                                RhythmDayCell(presentation: presentation)
                                    .frame(width: 16, height: 16)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(presentation.accessibilityLabel(for: day))
                            .accessibilityHint("Opens history for this day")
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.hidden)
            }

            legend
        }
        .accessibilityElement(children: .contain)
    }

    private var legend: some View {
        HStack(spacing: MomentumSpacing.xs) {
            RhythmDayCell(presentation: .noObligation).frame(width: 13, height: 13)
            Text("No obligation")
            RhythmDayCell(presentation: .paused).frame(width: 13, height: 13)
            Text("Paused")
            ForEach([0.35, 0.55, 0.75, 1.0], id: \.self) { opacity in
                RoundedRectangle(cornerRadius: 2)
                    .fill(MomentumTheme.pulse.opacity(opacity))
                    .frame(width: 13, height: 13)
                    .accessibilityHidden(true)
            }
            Text("Complete")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
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
}

struct HistoryDayRow: View {
    let day: DomainDay
    let sessions: [WorkoutSessionRecord]
    let workoutEvents: [WorkoutDayEventRecord]
    let nutritionDays: [NutritionDayRecord]
    let foodEntries: [FoodEntryRecord]
    let careOccurrences: [CareOccurrenceRecord]

    private var dayKey: String { PersistedDomainDay.encode(day) }

    private var labels: [String] {
        var values: [String] = []
        if sessions.contains(where: {
            $0.deletedAt == nil && $0.completionDomainDay == dayKey
        }) {
            values.append("Workout finished")
        } else if let event = workoutEvents.first(where: {
            $0.deletedAt == nil && $0.domainDay == dayKey
        }) {
            values.append("Workout \(event.kindRaw)")
        }
        let foods = foodEntries.count {
            $0.deletedAt == nil && $0.domainDay == dayKey
        }
        if foods > 0 { values.append("\(foods) food \(foods == 1 ? "entry" : "entries")") }
        if nutritionDays.contains(where: { $0.domainDay == dayKey && $0.finalizedAt != nil }) {
            values.append("Nutrition finalized")
        }
        let care = careOccurrences.count { $0.dueDomainDay == dayKey }
        if care > 0 { values.append("\(care) personal care \(care == 1 ? "routine" : "routines")") }
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
