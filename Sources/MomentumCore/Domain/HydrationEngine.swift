import Foundation

/// Pure hydration pacing and unit math. Deterministic; no clock or calendar
/// access beyond injected values, so checkpoint behavior is fully testable.
public enum HydrationEngine {
    /// Quiet hours: nothing fires outside 09:00–21:00 regardless of the
    /// configured checkpoint times (hydration v1 spec).
    public static let quietWindowStartMinutes = 9 * 60
    public static let quietWindowEndMinutes = 21 * 60
    /// Hard cap of reminder firings per day.
    public static let maxFiredPerDay = 3
    /// A checkpoint may still be emitted up to this many minutes after its
    /// time; older unfired slots never retro-fire.
    public static let retroEmissionGraceMinutes = 30
    /// Lookahead so a reconciliation run shortly before a checkpoint already
    /// schedules it. Pace stays evaluated at the slot itself.
    public static let scheduleAheadLookaheadMinutes = 5
    /// Minutes in a day used for linear pace.
    private static let minutesPerDay = 24 * 60

    /// True when intake is behind the linear pace toward `targetML` at the
    /// given minute-of-day. Exactly on pace is not behind.
    public static func isBehindPace(
        targetML: Int,
        consumedML: Int,
        checkpointMinuteOfDay: Int
    ) -> Bool {
        guard targetML > 0 else { return false }
        let fraction = Double(min(max(checkpointMinuteOfDay, 0), minutesPerDay)) / Double(minutesPerDay)
        let expected = Double(targetML) * fraction
        return Double(consumedML) < expected
    }

    /// Returns the checkpoint slots (minute-of-day) that should fire now:
    /// future-or-now within quiet hours, behind pace, target not reached,
    /// not already fired today, and respecting the hard daily cap.
    /// Slots in the past never retro-fire.
    public static func dueCheckpoints(
        now: Date,
        calendar: Calendar,
        checkpointsEnabled: Bool,
        checkpointMinutes: [Int],
        targetML: Int,
        consumedML: Int,
        targetReached: Bool,
        alreadyFiredSlots: Set<Int>
    ) -> [Int] {
        guard checkpointsEnabled, !targetReached else { return [] }
        guard alreadyFiredSlots.count < maxFiredPerDay else { return [] }

        let components = calendar.dateComponents([.hour, .minute], from: now)
        let nowMinute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        guard nowMinute >= quietWindowStartMinutes, nowMinute <= quietWindowEndMinutes else {
            return []
        }

        return checkpointMinutes
            .sorted()
            .filter { slot in
                slot >= quietWindowStartMinutes
                    && slot <= quietWindowEndMinutes
                    && slot + retroEmissionGraceMinutes >= nowMinute
                    && slot <= nowMinute + scheduleAheadLookaheadMinutes
                    && !alreadyFiredSlots.contains(slot)
            }
            .filter { isBehindPace(targetML: targetML, consumedML: consumedML, checkpointMinuteOfDay: $0) }
    }

    /// Whole fluid ounces for imperial conversion (rounded). Storage and
    /// round-trip conversion only — prefer `fluidOuncesDisplay` for rendering,
    /// which avoids the whole-ounce rounding artifact (500 ml is 16.9 fl oz).
    public static func fluidOunces(fromML millilitres: Int) -> Int {
        Int((Double(millilitres) / 29.573_529_562_5).rounded())
    }

    /// Exact fluid ounces for editable fields, unrounded.
    public static func exactFluidOunces(fromML millilitres: Int) -> Double {
        Double(millilitres) / 29.573_529_562_5
    }

    /// Rendered fluid ounces: a whole number only when the value sits within
    /// 0.05 fl oz of an integer, otherwise up to one decimal. Canonical ml
    /// defaults (2 514 / 237 / 473 / 710) render as exact 85/8/16/24, while
    /// metric-era values like 500 ml render as "16.9", never a false "17".
    public static func fluidOuncesDisplay(fromML millilitres: Int) -> String {
        let ounces = exactFluidOunces(fromML: millilitres)
        if abs(ounces - ounces.rounded()) < 0.05 {
            return String(Int(ounces.rounded()))
        }
        return ounces.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// Millilitres converted from whole fluid ounces.
    public static func millilitres(fromFluidOunces ounces: Int) -> Int {
        Int((Double(ounces) * 29.573_529_562_5).rounded())
    }

    /// Millilitres converted from an exact fluid-ounce amount (editable fields).
    public static func millilitres(fromExactFluidOunces ounces: Double) -> Int {
        Int((ounces * 29.573_529_562_5).rounded())
    }
}
