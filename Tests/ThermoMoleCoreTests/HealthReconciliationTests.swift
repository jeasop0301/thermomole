import XCTest
@testable import ThermoMoleCore

final class HealthReconciliationTests: XCTestCase {

    // MARK: - smoothedPercent (robust median, NOT mean)

    func testSmoothedMedianOddWindow() {
        // last up-to-7: median of [80, 90, 85] = 85 (mean would be 85 here; use a skewed set below)
        let r = HealthReconciliation.from(series: [80, 90, 85], reported: 85)
        XCTAssertEqual(r.smoothedPercent, 85)
    }

    func testSmoothedMedianResistsSpike() {
        // [80, 81, 98, 80, 81] — mean ≈ 84, median = 81. Median must resist the 98 spike.
        let r = HealthReconciliation.from(series: [80, 81, 98, 80, 81], reported: 98)
        XCTAssertEqual(r.smoothedPercent, 81)
    }

    func testSmoothedMedianEvenWindow() {
        // last up-to-7 of [82, 84, 86, 88] → even count → mean of two middles (84+86)/2 = 85
        let r = HealthReconciliation.from(series: [82, 84, 86, 88], reported: 88)
        XCTAssertEqual(r.smoothedPercent, 85)
    }

    func testSmoothedUsesOnlyLastSeven() {
        // 10 readings; only last 7 [4,5,6,7,8,9,10] count → median = 7
        let r = HealthReconciliation.from(series: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], reported: 10)
        XCTAssertEqual(r.smoothedPercent, 7)
    }

    func testSmoothedRoundsToInt() {
        // even window [83, 86] → (83+86)/2 = 84.5 → rounds to 85 (round-half-up via .rounded())
        let r = HealthReconciliation.from(series: [83, 86], reported: 86)
        XCTAssertEqual(r.smoothedPercent, 85)
    }

    // MARK: - empty / single

    func testEmptySeries() {
        let r = HealthReconciliation.from(series: [], reported: 90)
        XCTAssertNil(r.smoothedPercent)
        XCTAssertEqual(r.sampleCount, 0)
        XCTAssertEqual(r.stability, .stable)
    }

    func testSingleReadingIsStableAndEqualsItself() {
        let r = HealthReconciliation.from(series: [88], reported: 88)
        XCTAssertEqual(r.smoothedPercent, 88)
        XCTAssertEqual(r.sampleCount, 1)
        XCTAssertEqual(r.stability, .stable)
    }

    // MARK: - stability (dispersion of last up-to-7)

    func testStableWhenSpreadBelowThreshold() {
        // max-min = 89-87 = 2 < 3 → stable
        let r = HealthReconciliation.from(series: [87, 88, 89, 88], reported: 88)
        XCTAssertEqual(r.stability, .stable)
    }

    func testVariableWhenSpreadAtThreshold() {
        // max-min = 90-87 = 3 ≥ 3 → variable (threshold is inclusive)
        let r = HealthReconciliation.from(series: [87, 88, 90], reported: 90)
        XCTAssertEqual(r.stability, .variable)
    }

    func testVariableWhenSpreadAboveThreshold() {
        // intraday swing 83→98 → variable
        let r = HealthReconciliation.from(series: [83, 98], reported: 98)
        XCTAssertEqual(r.stability, .variable)
    }

    func testStabilityConsidersOnlyLastSeven() {
        // Big spread in the OLD prefix [60,100,...]; last 7 [88,88,89,88,89,88,89] spread=1 → stable
        let r = HealthReconciliation.from(
            series: [60, 100, 88, 88, 89, 88, 89, 88, 89],
            reported: 89
        )
        XCTAssertEqual(r.stability, .stable)
    }

    // MARK: - sampleCount reflects window actually used

    func testSampleCountCapsAtSeven() {
        let r = HealthReconciliation.from(series: Array(repeating: 90.0, count: 12), reported: 90)
        XCTAssertEqual(r.sampleCount, 7)
    }

    func testSampleCountBelowCap() {
        let r = HealthReconciliation.from(series: [90, 91, 92], reported: 92)
        XCTAssertEqual(r.sampleCount, 3)
    }

    // MARK: - threshold constant

    func testThresholdConstant() {
        XCTAssertEqual(HealthReconciliation.variableSpreadThreshold, 3)
        XCTAssertEqual(HealthReconciliation.window, 7)
    }
}
