import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case today
    case history
    case plans
    case progress

    var title: String {
        switch self {
        case .today: "Today"
        case .history: "History"
        case .plans: "Plans"
        case .progress: "Progress"
        }
    }

    var symbol: String {
        switch self {
        case .today: "checklist"
        case .history: "calendar"
        case .plans: "slider.horizontal.3"
        case .progress: "chart.xyaxis.line"
        }
    }
}
