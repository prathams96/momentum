import Foundation
import SwiftUI

/// Presentation and ordering metadata for a module. Shared surfaces render
/// modules purely from this metadata plus the capabilities they implement.
struct ModuleMetadata: Sendable {
    let id: ModuleID
    let displayName: String
    let symbolName: String
    let tint: Color
    /// Lower ranks surface earlier on Today and win DailyThreadFocus ties.
    let todayRank: Int

    init(
        id: ModuleID,
        displayName: String,
        symbolName: String,
        tint: Color,
        todayRank: Int
    ) {
        self.id = id
        self.displayName = displayName
        self.symbolName = symbolName
        self.tint = tint
        self.todayRank = todayRank
    }
}
