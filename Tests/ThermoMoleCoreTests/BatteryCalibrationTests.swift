import XCTest
@testable import ThermoMoleCore

final class BatteryCalibrationTests: XCTestCase {

    private func series(days: Int, slopePerDay: Double, start: Double = 1.0) -> [(day: Double, ratio: Double)] {
        (0..<days).map { (day: Double($0), ratio: start + slopePerDay * Double($0)) }
    }

    func testModeledWhenWindowTooShort() {
        let pts = series(days: 30, slopePerDay: -0.0005) // 29-day window < 56
        let r = BatteryCalibration.evaluate(points: pts, strainRatio: 1.0, cycleWearPctPerWeek: 0)
        XCTAssertEqual(r.status, .modeled)
        XCTAssertNil(r.band)
    }

    func testModeledWhenFlatBelowNoiseFloor() {
        let pts = series(days: 60, slopePerDay: 0) // no fade
        let r = BatteryCalibration.evaluate(points: pts, strainRatio: 1.0, cycleWearPctPerWeek: 0)
        XCTAssertEqual(r.status, .modeled)
    }

    func testModeledWhenTooFewPoints() {
        // 11 points spanning 60 days — long enough window but sparse (< minPoints)
        let pts = stride(from: 0, through: 60, by: 6).map { (day: Double($0), ratio: 1.0 - 0.0005 * Double($0)) }
        let r = BatteryCalibration.evaluate(points: pts, strainRatio: 1.0, cycleWearPctPerWeek: 0)
        XCTAssertEqual(r.status, .modeled)
    }

    func testFasterThanModelForRapidFade() {
        // ~3% drop over 60 days, at ideal strain ⇒ far faster than the ~1%/yr baseline.
        let pts = series(days: 60, slopePerDay: -0.0005)
        let r = BatteryCalibration.evaluate(points: pts, strainRatio: 1.0, cycleWearPctPerWeek: 0)
        XCTAssertEqual(r.status, .calibrated)
        XCTAssertEqual(r.band, .faster)
        XCTAssertEqual(r.windowDays, 59)
        XCTAssertEqual(r.k ?? 0, 2.0, accuracy: 0.0001) // clamped
    }

    func testSlowerThanModelWhenStressHighButFadeLow() {
        // High strain (lots of heat/charge) but only ~0.6% measured drop ⇒ aging slower than stress predicts.
        let pts = series(days: 60, slopePerDay: -0.0001)
        let r = BatteryCalibration.evaluate(points: pts, strainRatio: 6.0, cycleWearPctPerWeek: 0)
        XCTAssertEqual(r.status, .calibrated)
        XCTAssertEqual(r.band, .slower)
    }

    func testCycleWearSubtractionRaisesK() {
        // Same measured fade; removing a chunk as cycle wear lowers the calendar share (→ lower k).
        let pts = series(days: 60, slopePerDay: -0.0003)
        let noCycle = BatteryCalibration.evaluate(points: pts, strainRatio: 3.0, cycleWearPctPerWeek: 0)
        let withCycle = BatteryCalibration.evaluate(points: pts, strainRatio: 3.0, cycleWearPctPerWeek: 0.1)
        XCTAssertEqual(noCycle.status, .calibrated)
        XCTAssertEqual(withCycle.status, .calibrated)
        XCTAssertLessThan(withCycle.k ?? 0, noCycle.k ?? 0)
    }

    func testInvalidRowsRejected() {
        var pts = series(days: 60, slopePerDay: -0.0005)
        pts[10] = (day: 10, ratio: 0)            // garbage (design==0 style)
        pts[20] = (day: 20, ratio: .nan)
        let r = BatteryCalibration.evaluate(points: pts, strainRatio: 1.0, cycleWearPctPerWeek: 0)
        XCTAssertEqual(r.status, .calibrated)    // still enough valid rows; doesn't crash
    }

    // MARK: - Cycle-wear term (BatteryLongevity)

    private func day(_ d: String, health: Int, cycles: Int) -> DailyBatteryHealth {
        DailyBatteryHealth(day: d, healthPercent: health, cycleCount: cycles,
                           maxCapacityMAh: 5760 * health / 100, designCapacityMAh: 5760)
    }

    func testCycleWearRangeFromMeasuredCycles() {
        // 14 cycles over 14 days = 7 EFC/week.
        let report = BatteryLongevity.evaluate(history: [
            day("2026-06-01", health: 100, cycles: 100),
            day("2026-06-15", health: 100, cycles: 114),
        ])!
        XCTAssertEqual(report.cyclesPerWeek ?? 0, 7.0, accuracy: 0.001)
        XCTAssertEqual(report.cycleWearPctPerYearLow ?? 0, 7.0 * 52 * 0.02, accuracy: 0.001)
        XCTAssertEqual(report.cycleWearPctPerYearHigh ?? 0, 7.0 * 52 * 0.06, accuracy: 0.001)
        XCTAssertLessThan(report.cycleWearPctPerYearLow!, report.cycleWearPctPerYearHigh!)
    }

    func testNegativeCycleDeltaIgnored() {
        // Battery service / SMC reset: cycle count drops — don't fabricate a rate.
        let report = BatteryLongevity.evaluate(history: [
            day("2026-06-01", health: 90, cycles: 300),
            day("2026-06-15", health: 100, cycles: 5),
        ])!
        XCTAssertNil(report.cyclesPerWeek)
        XCTAssertNil(report.cycleWearPctPerYearLow)
        XCTAssertNil(report.cycleWearPctPerYearHigh)
    }
}
