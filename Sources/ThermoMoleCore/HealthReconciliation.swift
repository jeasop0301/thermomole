import Foundation

/// Reconciles the swinging battery-health % users see (macOS / other apps can read 83% then 98%
/// the same day) into one honest read: a robust SMOOTHED trend figure plus a STABILITY flag.
///
/// The intraday swing is gauge noise, not real capacity loss, so we DON'T pick a single raw
/// sample and we DON'T average (a mean is dragged by the spikes). We take the median of the
/// recent window — it resists the spikes — and report dispersion as a coarse flag (steady /
/// variable), never a fabricated decimal "confidence". This is explicitly a TREND read, not a
/// claim about the battery's true capacity, and we never invent a 4th authoritative number.
///
/// Pure + deterministic: no IO, no wall-clock, no Date.
public struct HealthReconciliation: Equatable, Sendable {
    public enum Stability: String, Sendable, Equatable { case stable, variable }

    /// Robust central estimate (median) of the recent window, rounded to a whole percent.
    /// nil when there are no readings.
    public var smoothedPercent: Int?
    /// Coarse read on intraday/recent dispersion. Never a numeric confidence.
    public var stability: Stability
    /// How many readings the median/dispersion were computed over (≤ `window`).
    public var sampleCount: Int

    public init(smoothedPercent: Int?, stability: Stability, sampleCount: Int) {
        self.smoothedPercent = smoothedPercent
        self.stability = stability
        self.sampleCount = sampleCount
    }

    /// Recent-window size: the last up-to-7 daily readings. A week of readings is enough to
    /// cancel daily gauge jitter without lagging behind a real trend.
    public static let window = 7

    /// Inclusive spread (max − min, percentage points) over the window at/above which we flag the
    /// reading as `variable`. Real day-to-day fade is far below this; a spread of 3+ pts within a
    /// week is the gauge re-estimating, not the battery degrading.
    public static let variableSpreadThreshold = 3

    /// - series: recent daily health %, oldest → newest.
    /// - reported: the current raw reading (kept for callers framing "raw vs trend"; the smoothed
    ///   figure is derived from the series so it stays robust to the raw spike).
    public static func from(series: [Double], reported: Int) -> HealthReconciliation {
        let recent = Array(series.suffix(window))
        guard !recent.isEmpty else {
            return HealthReconciliation(smoothedPercent: nil, stability: .stable, sampleCount: 0)
        }

        let smoothed = Int(median(recent).rounded())

        let lo = recent.min() ?? 0
        let hi = recent.max() ?? 0
        let spread = hi - lo
        let stability: Stability = spread >= Double(variableSpreadThreshold) ? .variable : .stable

        return HealthReconciliation(
            smoothedPercent: smoothed,
            stability: stability,
            sampleCount: recent.count
        )
    }

    static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2.0
    }
}
