import Foundation

/// "N / ~M rated cycles" context. Apple rates Apple Silicon packs for ~M cycles (DesignCycleCount9C,
/// usually 1000) to 80% health — a SPEC / expectation, NOT a hard limit. Batteries keep working past
/// it. This is pure display context: the user sees where their count sits relative to Apple's number.
///
/// Construct via `make`, which returns nil for junk/missing inputs so callers naturally hide the line.
public struct RatedCycleContext: Equatable, Sendable {
    public let cycleCount: Int
    public let ratedCycleCount: Int

    /// Percent of the rated count used, floored. Can exceed 100 once past the rating — left honest
    /// (not clamped) so a well-aged pack reads truthfully rather than pinned at 100%.
    public var percentThrough: Int {
        cycleCount * 100 / ratedCycleCount
    }

    /// Returns context only when the rated count is reported and positive and the cycle count is a
    /// valid non-negative reading; otherwise nil (hide the line — some Macs don't report a rating).
    public static func make(cycleCount: Int, ratedCycleCount: Int?) -> RatedCycleContext? {
        guard let rated = ratedCycleCount, rated > 0, cycleCount >= 0 else { return nil }
        return RatedCycleContext(cycleCount: cycleCount, ratedCycleCount: rated)
    }
}
