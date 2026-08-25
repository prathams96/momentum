import Foundation
import SwiftUI

/// One node in the Today daily-thread header.
struct DailyThreadStageModel: Identifiable, Equatable {
    let title: String
    let symbol: String
    let tint: Color?
    var isFocused: Bool

    var id: String { title }
}

/// CONTEXT.md · Daily Focus: focus = the first due, incomplete activity in
/// the day's ordered contributions across enabled modules. There is no
/// terminal "reflect" stage; when nothing is incomplete the day presents as
/// complete. This is a named, tested Core rule — surfaces never re-derive it.
@MainActor
enum DailyThreadFocus {
    /// States that carry an obligation not yet satisfied.
    static func isIncomplete(_ state: ContributionState) -> Bool {
        switch state {
        case .ongoing, .attention: true
        case .completed, .optional: false
        }
    }

    static func stages(from contributions: [TodayContribution]) -> [DailyThreadStageModel] {
        var stages = contributions.map { contribution in
            DailyThreadStageModel(
                title: contribution.title,
                symbol: contribution.symbolName,
                tint: contribution.tint,
                isFocused: false
            )
        }
        if let focusIndex = contributions.firstIndex(where: { isIncomplete($0.state) }) {
            stages[focusIndex].isFocused = true
        }
        return stages
    }

    static func callout(
        contributions: [TodayContribution],
        stages: [DailyThreadStageModel]
    ) -> String {
        if let attention = contributions.first(where: { $0.state == .attention }) {
            return "\(attention.title) needs attention"
        }
        if let focused = stages.first(where: \.isFocused) {
            return "\(focused.title) next"
        }
        return "All done for today"
    }
}
