import XCTest
@testable import ThermoMoleCore

/// FALSE-POSITIVE DISCIPLINE is the whole feature. These tests pin the conservative behavior:
/// only a *clear, robust* acceleration (separated CIs + ≥1.5× median + still losing) trips
/// `.accelerating`; linear fade, jitter, a single step-recalibration, and short/sparse series
/// all stay quiet.
final class FadeTrendTests: XCTestCase {

    /// Daily samples (one point per day, 0…days-1) following a piecewise-linear ratio path.
    /// `slopeEarly`/`slopeRecent` are ratio-per-day for the first/second calendar halves.
    private func biphasic(days: Int, slopeEarly: Double, slopeRecent: Double,
                          start: Double = 0.95, jitter: Double = 0) -> [(day: Double, ratio: Double)] {
        let mid = days / 2
        var r = start
        var out: [(day: Double, ratio: Double)] = []
        for d in 0..<days {
            let slope = d < mid ? slopeEarly : slopeRecent
            // Deterministic, mean-zero "jitter" so windows stay symmetric: ±jitter sawtooth.
            let wobble = jitter == 0 ? 0 : (d % 2 == 0 ? jitter : -jitter)
            out.append((day: Double(d), ratio: r + wobble))
            r += slope
        }
        return out
    }

    // MARK: Accelerating (the positive case)

    func testAcceleratingWhenRecentClearlySteeper() {
        // Earlier ~0.01%/day, recent ~0.05%/day → 5× steeper, CIs cleanly separated, 200-day span.
        let pts = biphasic(days: 200, slopeEarly: -0.0001, slopeRecent: -0.0005)
        XCTAssertEqual(FadeTrend.evaluate(points: pts), .accelerating)
    }

    // MARK: Steady — linear

    func testSteadyForLinearFade() {
        // Same slope throughout → not accelerating.
        let pts = biphasic(days: 200, slopeEarly: -0.0003, slopeRecent: -0.0003)
        XCTAssertEqual(FadeTrend.evaluate(points: pts), .steady)
    }

    // MARK: Steady — noisy but flat

    func testSteadyForNoisyButFlat() {
        // No real change in rate, just jitter on top of one constant slope → CIs overlap.
        let pts = biphasic(days: 200, slopeEarly: -0.0002, slopeRecent: -0.0002, jitter: 0.0008)
        XCTAssertEqual(FadeTrend.evaluate(points: pts), .steady)
    }

    // MARK: Steady — single step recalibration (the false-alarm guard)

    func testSingleStepJumpDoesNotTrigger() {
        // Otherwise-FLAT series (no real fade) with ONE big downward step late in the recent
        // half — exactly the FCC step-recalibration that fools a naive 2nd derivative. The
        // robust rank CI must absorb it: NOT accelerating.
        var pts: [(day: Double, ratio: Double)] = (0..<200).map { (day: Double($0), ratio: 0.95) }
        for i in 170..<200 { pts[i].ratio = 0.92 } // single ~3% step drop, then flat again

        // Sanity: a NAIVE detector (recent half's mean ratio dropped vs earlier half) WOULD
        // see this as a big recent loss and alarm — this is precisely the false positive we reject.
        let earlierMean = pts[0..<100].map(\.ratio).reduce(0, +) / 100
        let recentMean = pts[100..<200].map(\.ratio).reduce(0, +) / 100
        XCTAssertLessThan(recentMean, earlierMean, "the step makes recent capacity lower (naive trap)")

        let r = FadeTrend.evaluate(points: pts)
        XCTAssertNotEqual(r, .accelerating, "a single step recalibration must not raise a knee alarm")
    }

    func testSingleStepJumpOnGentleFadeDoesNotTrigger() {
        // Gentle genuine linear fade in BOTH halves + one step drop. Still must not trip:
        // the step inflates recent point-slope but the rank CI rejects it.
        var pts = biphasic(days: 220, slopeEarly: -0.00008, slopeRecent: -0.00008)
        for i in 190..<220 { pts[i].ratio -= 0.03 } // one late step
        XCTAssertNotEqual(FadeTrend.evaluate(points: pts), .accelerating)
    }

    // MARK: Insufficient — span gate

    func testInsufficientWhenSpanTooShort() {
        // 120-day span < 180, even with plenty of points and a real acceleration.
        let pts = biphasic(days: 120, slopeEarly: -0.0001, slopeRecent: -0.0006)
        XCTAssertEqual(FadeTrend.evaluate(points: pts), .insufficient)
    }

    // MARK: Insufficient — too few points in a window

    func testInsufficientWhenTooFewPointsPerWindow() {
        // Long span (200 days) but sparse: ~8 points per half (< 12).
        let pts = stride(from: 0, through: 200, by: 14).map {
            (day: Double($0), ratio: 0.95 - 0.0002 * Double($0))
        }
        XCTAssertEqual(FadeTrend.evaluate(points: pts), .insufficient)
    }

    // MARK: Degenerate inputs — never crash

    func testEmptyIsInsufficient() {
        XCTAssertEqual(FadeTrend.evaluate(points: []), .insufficient)
    }

    func testSinglePointIsInsufficient() {
        XCTAssertEqual(FadeTrend.evaluate(points: [(day: 0, ratio: 0.95)]), .insufficient)
    }

    func testZeroVarianceFlatIsSteadyNotCrash() {
        // 200 days, perfectly flat ratio → both fades 0 → steady (not accelerating, no crash).
        let pts: [(day: Double, ratio: Double)] = (0..<200).map { (day: Double($0), ratio: 0.95) }
        XCTAssertEqual(FadeTrend.evaluate(points: pts), .steady)
    }

    func testNaNAndNonFiniteRowsDropped() {
        var pts = biphasic(days: 200, slopeEarly: -0.0001, slopeRecent: -0.0005)
        pts[5] = (day: .nan, ratio: 0.9)
        pts[7] = (day: 7, ratio: .infinity)
        pts[9] = (day: 9, ratio: -1) // non-positive ratio
        // The acceleration signal survives dropping a few rows.
        XCTAssertEqual(FadeTrend.evaluate(points: pts), .accelerating)
    }

    func testZeroSpanDuplicateDaysIsInsufficient() {
        // All same day → zero span → insufficient, no divide-by-zero.
        let pts: [(day: Double, ratio: Double)] = (0..<50).map { _ in (day: 0, ratio: 0.95) }
        XCTAssertEqual(FadeTrend.evaluate(points: pts), .insufficient)
    }

    // MARK: Direction guard — capacity GAIN (gauge recovery) is not "accelerating loss"

    func testRisingRatioIsNotAccelerating() {
        // Ratio increasing (gauge recovered) → fades negative → steady, never accelerating.
        let pts = biphasic(days: 200, slopeEarly: 0.0001, slopeRecent: 0.0005)
        XCTAssertEqual(FadeTrend.evaluate(points: pts), .steady)
    }
}
