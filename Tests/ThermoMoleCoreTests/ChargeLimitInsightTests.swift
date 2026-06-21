import XCTest
@testable import ThermoMoleCore

final class ChargeLimitInsightTests: XCTestCase {

    // MARK: - socAgingReductionPercent

    func testReductionAt90() {
        // socFactor(90)=1.75, socFactor(80)=1.55 → (1 - 1.55/1.75)*100 ≈ 11.4 → 11
        XCTAssertEqual(ChargeLimitInsight.socAgingReductionPercent(currentMaxSoc: 90), 11, accuracy: 1)
    }

    func testReductionAt98() {
        // socFactor(98)=1.91 → (1 - 1.55/1.91)*100 ≈ 18.8 → 19
        XCTAssertEqual(ChargeLimitInsight.socAgingReductionPercent(currentMaxSoc: 98), 19, accuracy: 1)
    }

    func testReductionAt100() {
        // socFactor(100)=1.95 → (1 - 1.55/1.95)*100 ≈ 20.5 → 21
        XCTAssertEqual(ChargeLimitInsight.socAgingReductionPercent(currentMaxSoc: 100), 21, accuracy: 1)
    }

    func testReductionAt80IsZero() {
        XCTAssertEqual(ChargeLimitInsight.socAgingReductionPercent(currentMaxSoc: 80), 0)
    }

    func testReductionBelow80ClampsToZero() {
        // socFactor(70) < socFactor(80) → formula goes negative → clamped ≥ 0
        XCTAssertEqual(ChargeLimitInsight.socAgingReductionPercent(currentMaxSoc: 70), 0)
    }

    // MARK: - classify (3-state)

    func testClassifyLimitActiveAtEightyTwo() {
        XCTAssertEqual(ChargeLimitInsight.classify(dailyMaxSoc: 80), .limitActive)
        XCTAssertEqual(ChargeLimitInsight.classify(dailyMaxSoc: 82), .limitActive)
    }

    func testClassifyHighExposureAtNinetyFive() {
        XCTAssertEqual(ChargeLimitInsight.classify(dailyMaxSoc: 95), .highExposure(reductionPct: 16))
    }

    func testClassifyHighExposureAtNinety() {
        XCTAssertEqual(ChargeLimitInsight.classify(dailyMaxSoc: 90), .highExposure(reductionPct: 11))
    }

    func testClassifyNormalInMidBand() {
        XCTAssertEqual(ChargeLimitInsight.classify(dailyMaxSoc: 85), .normal)
        XCTAssertEqual(ChargeLimitInsight.classify(dailyMaxSoc: 83), .normal)
        XCTAssertEqual(ChargeLimitInsight.classify(dailyMaxSoc: 89), .normal)
    }

    func testClassifyNormalWhenNil() {
        XCTAssertEqual(ChargeLimitInsight.classify(dailyMaxSoc: nil), .normal)
    }
}
