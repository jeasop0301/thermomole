import Foundation

/// Anchors Patina's *relative* calendar-aging model to the user's OWN measured capacity fade,
/// so the headline reflects their real battery rather than generic kinetics.
///
/// Pure + deterministic (no wall-clock). Output is a coarse BAND, never a false-precision
/// number: the measured fade signal (full-charge-capacity mAh trend) jitters by tens of mAh
/// and recalibrates in steps, so we use a robust Theil–Sen slope, hard SNR/length gates, heavy
/// shrinkage toward "no adjustment", and report slower / about / faster — not a decimal.
public struct BatteryCalibrationResult: Equatable, Sendable {
    public enum Status: String, Sendable, Equatable { case modeled, calibrated }
    /// How the user's measured calendar aging compares to the generic 25°C/50% model.
    public enum Band: String, Sendable, Equatable { case slower, about, faster }

    public var status: Status
    public var band: Band?      // nil while modeled
    public var k: Double?       // shrunk scale factor (debug/opt-in only); nil while modeled
    public var windowDays: Int

    public init(status: Status, band: Band? = nil, k: Double? = nil, windowDays: Int = 0) {
        self.status = status
        self.band = band
        self.k = k
        self.windowDays = windowDays
    }

    public static let modeled = BatteryCalibrationResult(status: .modeled)
}

public enum BatteryCalibration {
    /// Ideal-idle calendar fade prior (~1%/yr at 25°C / 50% SoC), expressed per week.
    /// A literature prior (consumer Li-ion calendar life), medium confidence — used only to
    /// turn the unitless strain ratio into an expected %/time for the comparison.
    public static let baselineCalendarFadePctPerWeek = 1.0 / 52.0

    /// Gates before any calibration is shown (else `.modeled`).
    public static let minWindowDays = 56              // ~8 weeks
    public static let minPoints = 24
    public static let minDropPctOfDesign = 0.5        // SNR floor: real fade must clear gauge jitter
    public static let kClamp = 0.5 ... 2.0            // beyond 2× over 8 weeks ⇒ gauge artifact, refuse

    /// - points: (dayOffset, rawRatio) where rawRatio = maxCapacityMAh / designCapacityMAh
    ///           (un-clamped, may exceed 1.0). Oldest → newest.
    /// - strainRatio: the model's recent strain ratio (effective/calendar aging, ≈1 at ideal idle).
    /// - cycleWearPctPerWeek: estimated cycle-only fade to remove so calendar k isn't polluted
    ///   by cycle aging (0 if unknown).
    public static func evaluate(points: [(day: Double, ratio: Double)],
                                strainRatio: Double,
                                cycleWearPctPerWeek: Double) -> BatteryCalibrationResult {
        let pts = points.filter { $0.ratio.isFinite && $0.ratio > 0 && $0.day.isFinite }
        guard pts.count >= minPoints, let first = pts.first, let last = pts.last else { return .modeled }

        let windowDays = Int((last.day - first.day).rounded())
        guard windowDays >= minWindowDays else { return .modeled }

        // Robust slope (ratio per day). Theil–Sen survives the FCC jitter/step-recalibration.
        let slopePerDay = theilSenSlope(pts)
        // Fade = capacity DECREASING ⇒ positive. ratio is a fraction; ×100 → percent.
        let measuredFadePctPerWeek = -slopePerDay * 7.0 * 100.0

        // SNR: the total measured drop over the window must clear the noise floor.
        let totalDropPct = -slopePerDay * Double(windowDays) * 100.0
        guard abs(totalDropPct) >= minDropPctOfDesign else { return .modeled }

        // Calendar-only fade: remove the cycle-wear estimate so calendar k isn't polluted.
        let calendarFadePctPerWeek = max(0.0, measuredFadePctPerWeek - max(0.0, cycleWearPctPerWeek))
        let modelExpected = baselineCalendarFadePctPerWeek * max(0.1, strainRatio)
        guard modelExpected > 0 else { return .modeled }

        let kRaw = calendarFadePctPerWeek / modelExpected
        // Shrink toward 1 (no adjustment) until there's plenty of data; then clamp hard.
        let w = min(1.0, Double(windowDays) / 120.0)
        let k = min(kClamp.upperBound, max(kClamp.lowerBound, w * kRaw + (1 - w) * 1.0))

        let band: BatteryCalibrationResult.Band = k < 0.85 ? .slower : (k > 1.15 ? .faster : .about)
        return BatteryCalibrationResult(status: .calibrated, band: band, k: k, windowDays: windowDays)
    }

    static func theilSenSlope(_ pts: [(day: Double, ratio: Double)]) -> Double {
        var slopes: [Double] = []
        slopes.reserveCapacity(pts.count * (pts.count - 1) / 2)
        for i in 0..<pts.count {
            for j in (i + 1)..<pts.count {
                let dx = pts[j].day - pts[i].day
                if dx != 0 { slopes.append((pts[j].ratio - pts[i].ratio) / dx) }
            }
        }
        return median(slopes)
    }

    static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2.0
    }
}
