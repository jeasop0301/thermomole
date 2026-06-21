import Foundation

/// Conservative "knee" / accelerating-fade early warning.
///
/// Question it answers: *is the user's capacity loss speeding up* — the replacement-timing
/// signal Apple's Normal/Service binary never gives. This is deliberately a RARE, in-UI-only
/// hint (no notification): the full-charge-capacity (FCC) gauge step-recalibrates and is noisy,
/// so a naive second derivative produces false alarms. The robustness bar *is* the feature —
/// when uncertain we say nothing.
///
/// Pure + deterministic (no wall-clock). Points are `(day, ratio)` where
/// `ratio = maxCapacityMAh / designCapacityMAh`, oldest → newest — the same construction
/// `BatteryCalibration` uses.
///
/// Method
/// ------
/// 1. Split the series into two halves by the calendar MIDPOINT day (earlier vs recent), so a
///    burst of recent samples can't shift the boundary in time.
/// 2. In each half compute the full Theil–Sen pairwise-slope distribution and take its MEDIAN
///    plus a rank CI `[p10, p90]`. Fade = −slope (positive ⇒ losing capacity).
/// 3. Flag `.accelerating` ONLY when the recent window is *clearly* faster:
///      • the CIs don't overlap (recent fade LOWER bound > earlier fade UPPER bound), AND
///      • recent median fade ≥ `accelerationRatio`× earlier median fade, AND
///      • both medians are positive (actually losing capacity).
///    Otherwise `.steady`. A single step-recalibration drop is absorbed by the rank CI.
public enum FadeTrend: String, Sendable, Equatable {
    /// Not enough long-baseline data to judge — show nothing.
    case insufficient
    /// Fade is not clearly speeding up (linear, noise, or a one-off step). Show nothing.
    case steady
    /// Recent fade is clearly and robustly faster than earlier fade — soft in-UI hint only.
    case accelerating

    // MARK: Discipline constants

    /// Total span the series must cover before we'll even look (≥ ~6 months of baseline).
    public static let defaultMinSpanDays: Double = 180

    /// Each comparison window must hold at least this many usable points.
    public static let defaultMinPointsPerWindow = 12

    /// Recent median fade must be at least this multiple of the earlier median fade.
    /// Above the CI-separation test; a deliberately blunt "clearly faster, not marginally".
    public static let accelerationRatio: Double = 1.5

    /// Rank CI percentiles taken over each window's pairwise-slope distribution.
    public static let ciLowerPercentile: Double = 10
    public static let ciUpperPercentile: Double = 90

    /// Robust fade summary for one window: median fade + a rank CI, all in ratio/day units
    /// expressed as fade (−slope), so positive = losing capacity.
    struct WindowFade: Equatable {
        var medianFade: Double
        var lowerFade: Double   // CI lower bound (p10 of fade)
        var upperFade: Double   // CI upper bound (p90 of fade)
    }

    /// Evaluate whether capacity fade is accelerating.
    ///
    /// - Parameters:
    ///   - points: `(day, ratio)` oldest→newest; `ratio = maxCapacityMAh/designCapacityMAh`.
    ///   - minSpanDays: total-span gate (default 180).
    ///   - minPointsPerWindow: per-window point-count gate (default 12).
    /// - Returns: `.insufficient` when the data is too short/sparse/degenerate,
    ///   `.accelerating` only when recent fade is clearly+robustly faster, else `.steady`.
    public static func evaluate(points: [(day: Double, ratio: Double)],
                                minSpanDays: Double = defaultMinSpanDays,
                                minPointsPerWindow: Int = defaultMinPointsPerWindow) -> FadeTrend {
        // Defensive: keep only finite, positive-ratio rows; sort oldest→newest by day.
        let pts = points
            .filter { $0.day.isFinite && $0.ratio.isFinite && $0.ratio > 0 }
            .sorted { $0.day < $1.day }
        guard let first = pts.first, let last = pts.last else { return .insufficient }

        let span = last.day - first.day
        guard span.isFinite, span >= minSpanDays else { return .insufficient }

        // Split by the calendar midpoint day (not the index midpoint): a recent burst of
        // samples can't move the time boundary. `<` earlier, `>=` recent.
        let midDay = first.day + span / 2.0
        let earlier = pts.filter { $0.day < midDay }
        let recent = pts.filter { $0.day >= midDay }

        guard earlier.count >= minPointsPerWindow,
              recent.count >= minPointsPerWindow else { return .insufficient }

        guard let earlyFade = windowFade(earlier),
              let recentFade = windowFade(recent) else { return .insufficient }

        // Both windows must actually be LOSING capacity for "accelerating loss" to mean anything.
        guard earlyFade.medianFade > 0, recentFade.medianFade > 0 else { return .steady }

        // 1) CIs must NOT overlap: recent's lower bound strictly above earlier's upper bound.
        let separated = recentFade.lowerFade > earlyFade.upperFade
        // 2) Recent median clearly faster (blunt multiple, not marginal).
        let clearlyFaster = recentFade.medianFade >= accelerationRatio * earlyFade.medianFade

        return (separated && clearlyFaster) ? .accelerating : .steady
    }

    /// Theil–Sen pairwise-slope distribution → median fade + rank CI for one window.
    /// Returns nil only for a degenerate window (no distinct-day pairs).
    static func windowFade(_ pts: [(day: Double, ratio: Double)]) -> WindowFade? {
        var slopes: [Double] = []
        slopes.reserveCapacity(pts.count * (pts.count - 1) / 2)
        for i in 0..<pts.count {
            for j in (i + 1)..<pts.count {
                let dx = pts[j].day - pts[i].day
                if dx != 0 { slopes.append((pts[j].ratio - pts[i].ratio) / dx) }
            }
        }
        guard !slopes.isEmpty else { return nil }
        slopes.sort()

        // Fade = −slope. The p10 of slope is the p90 of fade and vice-versa, so swap the
        // bounds: lowerFade comes from the upper slope percentile, upperFade from the lower.
        let slopeMedian = median(sorted: slopes)
        let slopeLow = percentile(sorted: slopes, ciLowerPercentile)
        let slopeHigh = percentile(sorted: slopes, ciUpperPercentile)
        return WindowFade(medianFade: -slopeMedian,
                          lowerFade: -slopeHigh,
                          upperFade: -slopeLow)
    }

    /// Linear-interpolated percentile over an already-sorted array. Clamped to [0,100].
    static func percentile(sorted xs: [Double], _ p: Double) -> Double {
        guard let first = xs.first, let lastV = xs.last else { return 0 }
        if xs.count == 1 { return first }
        let pp = min(100, max(0, p))
        let rank = pp / 100.0 * Double(xs.count - 1)
        let lo = Int(rank.rounded(.down))
        let hi = Int(rank.rounded(.up))
        if lo == hi { return xs[lo] }
        guard hi < xs.count else { return lastV }
        let frac = rank - Double(lo)
        return xs[lo] + (xs[hi] - xs[lo]) * frac
    }

    static func median(sorted xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let n = xs.count
        return n % 2 == 1 ? xs[n / 2] : (xs[n / 2 - 1] + xs[n / 2]) / 2.0
    }
}
