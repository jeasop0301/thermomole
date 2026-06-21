import Foundation

/// Pure insight around the native macOS charge limit: how much high-charge (SoC) calendar aging
/// the user would shed by capping at 80%, plus a 3-state read on whether a limit already appears
/// active. No SMC writes, no daemon, no control — this only quantifies and classifies what the
/// BMS already reports (dailyMaxSoc), so the UI can confirm a working limit or nudge toward one.
public enum ChargeLimitInsight {

    /// Reduction in the SoC component of calendar aging if the pack were capped at 80% instead of
    /// the current daily max. This is the high-charge (SoC) factor only — NOT total battery life,
    /// NOT cycle wear. Phrase to the user as "high-charge aging by ~X%".
    /// Formula: max(0, round((1 - socFactor(80)/socFactor(maxSoc)) * 100)), clamped ≥ 0.
    public static func socAgingReductionPercent(currentMaxSoc: Int) -> Int {
        let current = BatteryAgingRate.socFactor(Double(currentMaxSoc))
        guard current > 0 else { return 0 }
        let reduction = (1.0 - BatteryAgingRate.socFactor(80) / current) * 100.0
        return max(0, Int(reduction.rounded()))
    }

    /// Three-state read on the user's charge habit, inferred purely from the BMS daily max SoC.
    public enum State: Equatable, Sendable {
        /// A limit appears active: the pack hasn't climbed past ~82% recently. Reassurance, not a problem.
        case limitActive
        /// The pack routinely sits near full (≥90%); carries the cap-at-80% benefit for the nudge/hint.
        case highExposure(reductionPct: Int)
        /// Mid-band (83–89%) or unknown — nothing to confirm or nudge.
        case normal
    }

    /// Classify from the BMS daily max SoC.
    /// NOTE: "limitActive" is INFERRED — macOS exposes no public API for the native charge-limit
    /// state, so we treat a recent max of ≤82% as evidence a limit (or careful habit) is in effect.
    public static func classify(dailyMaxSoc: Int?) -> State {
        guard let maxSoc = dailyMaxSoc else { return .normal }
        if maxSoc <= 82 { return .limitActive }
        if maxSoc >= 90 { return .highExposure(reductionPct: socAgingReductionPercent(currentMaxSoc: maxSoc)) }
        return .normal
    }
}
