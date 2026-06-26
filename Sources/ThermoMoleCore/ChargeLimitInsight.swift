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
        socAgingReductionPercent(currentMaxSoc: currentMaxSoc, cap: 80)
    }

    /// Generalized form of the above: high-charge (SoC) aging reduction if the pack were capped at
    /// `cap` instead of the current daily max. Same caveat — this is the SoC factor ONLY, not total
    /// battery life and not cycle wear. Negative (cap ≥ current) clamps to 0.
    /// Formula: max(0, round((1 - socFactor(cap)/socFactor(maxSoc)) * 100)).
    public static func socAgingReductionPercent(currentMaxSoc: Int, cap: Int) -> Int {
        let current = BatteryAgingRate.socFactor(Double(currentMaxSoc))
        guard current > 0 else { return 0 }
        let reduction = (1.0 - BatteryAgingRate.socFactor(Double(cap)) / current) * 100.0
        return max(0, Int(reduction.rounded()))
    }

    /// One row of the charge-limit comparison table: a candidate cap and the high-charge aging
    /// reduction it would yield vs the current daily max.
    public struct ChargeLimitStep: Equatable, Sendable {
        public let cap: Int
        public let reductionPct: Int
        public init(cap: Int, reductionPct: Int) {
            self.cap = cap
            self.reductionPct = reductionPct
        }
    }

    /// The candidate native Charge Limit caps macOS offers, in ascending order.
    public static let comparisonCaps: [Int] = [80, 85, 90, 95]

    /// Build the comparison rows: for each candidate cap strictly below `currentMaxSoc`, the
    /// high-charge aging reduction at that cap. Only caps below the current max make sense (a cap
    /// at or above the current habit yields nothing). Empty when `currentMaxSoc <= 80`.
    public static func chargeLimitComparison(currentMaxSoc: Int) -> [ChargeLimitStep] {
        comparisonCaps
            .filter { $0 < currentMaxSoc }
            .map { ChargeLimitStep(cap: $0, reductionPct: socAgingReductionPercent(currentMaxSoc: currentMaxSoc, cap: $0)) }
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

    /// Authoritative read of whether macOS is deliberately holding the pack below full on AC — the
    /// native Charge Limit or Optimized Battery Charging — from the BMS `ChargerData`. True only
    /// when on AC, not charging, sitting at ≤90%, with a non-zero `NotChargingReason`: a combination
    /// a normal near-full taper or an unplugged pack can't produce. The ≤90 ceiling keeps a 95%
    /// limit or a near-full charging pause from false-positiving (both carry little SoC benefit and
    /// are left to the dailyMaxSoc inference). macOS 26.4+ exposes no public charge-limit API, so
    /// this BMS read is the closest thing to an authoritative state.
    public static func nativeLimitHolding(
        isOnACPower: Bool,
        isCharging: Bool,
        currentCapacityPercent: Int,
        notChargingReason: Int?
    ) -> Bool {
        isOnACPower
            && !isCharging
            && (1...90).contains(currentCapacityPercent)
            && (notChargingReason ?? 0) != 0
    }

    /// Classify from the BMS daily max SoC, with an optional authoritative `nativeLimitHolding`
    /// read that overrides the inference. When the OS is confirmed holding the pack below full
    /// that's direct evidence of a limit, so it wins over the SoC heuristic. Otherwise "limitActive"
    /// stays INFERRED: a recent max ≤82% is treated as evidence a limit (or careful habit) is active.
    public static func classify(dailyMaxSoc: Int?, nativeLimitHolding: Bool = false) -> State {
        if nativeLimitHolding { return .limitActive }
        guard let maxSoc = dailyMaxSoc else { return .normal }
        if maxSoc <= 82 { return .limitActive }
        if maxSoc >= 90 { return .highExposure(reductionPct: socAgingReductionPercent(currentMaxSoc: maxSoc)) }
        return .normal
    }
}
