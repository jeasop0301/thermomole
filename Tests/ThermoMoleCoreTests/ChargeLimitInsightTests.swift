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

    // MARK: - socAgingReductionPercent(currentMaxSoc:cap:) — generalized cap

    func testGeneralizedReduction98To80() {
        // socFactor(98)=1.91, socFactor(80)=1.55 → (1 - 1.55/1.91)*100 ≈ 18.8 → 19
        XCTAssertEqual(ChargeLimitInsight.socAgingReductionPercent(currentMaxSoc: 98, cap: 80), 19)
    }

    func testGeneralizedReduction98To90() {
        // socFactor(90)=1.75 → (1 - 1.75/1.91)*100 ≈ 8.4 → 8
        XCTAssertEqual(ChargeLimitInsight.socAgingReductionPercent(currentMaxSoc: 98, cap: 90), 8)
    }

    func testGeneralizedReduction98To85() {
        // socFactor(85)=1.65 → (1 - 1.65/1.91)*100 ≈ 13.6 → 14
        XCTAssertEqual(ChargeLimitInsight.socAgingReductionPercent(currentMaxSoc: 98, cap: 85), 14)
    }

    func testGeneralizedReduction98To95() {
        // socFactor(95)=1.85 → (1 - 1.85/1.91)*100 ≈ 3.1 → 3
        XCTAssertEqual(ChargeLimitInsight.socAgingReductionPercent(currentMaxSoc: 98, cap: 95), 3)
    }

    func testGeneralizedReduction100To85() {
        // socFactor(100)=1.95, socFactor(85)=1.65 → (1 - 1.65/1.95)*100 ≈ 15.4 → 15
        XCTAssertEqual(ChargeLimitInsight.socAgingReductionPercent(currentMaxSoc: 100, cap: 85), 15)
    }

    func testGeneralizedReductionCapNotBelowCurrentClampsToZero() {
        // cap >= currentMax → no benefit → clamped ≥ 0
        XCTAssertEqual(ChargeLimitInsight.socAgingReductionPercent(currentMaxSoc: 90, cap: 95), 0)
        XCTAssertEqual(ChargeLimitInsight.socAgingReductionPercent(currentMaxSoc: 90, cap: 90), 0)
    }

    func testOneArgMatchesGeneralizedAtCap80() {
        for soc in [85, 90, 95, 98, 100] {
            XCTAssertEqual(
                ChargeLimitInsight.socAgingReductionPercent(currentMaxSoc: soc),
                ChargeLimitInsight.socAgingReductionPercent(currentMaxSoc: soc, cap: 80)
            )
        }
    }

    // MARK: - chargeLimitComparison (table builder)

    func testComparisonAt98ReturnsAllFourCapsBelow() {
        let rows = ChargeLimitInsight.chargeLimitComparison(currentMaxSoc: 98)
        XCTAssertEqual(rows.map(\.cap), [80, 85, 90, 95])
        XCTAssertEqual(rows.map(\.reductionPct), [19, 14, 8, 3])
    }

    func testComparisonAt90ExcludesCapsAtOrAboveCurrent() {
        // Only caps strictly below 90 → 80, 85
        let rows = ChargeLimitInsight.chargeLimitComparison(currentMaxSoc: 90)
        XCTAssertEqual(rows.map(\.cap), [80, 85])
        XCTAssertEqual(rows.map(\.reductionPct), [11, 6])
    }

    func testComparisonAt100ReturnsAllFourCaps() {
        let rows = ChargeLimitInsight.chargeLimitComparison(currentMaxSoc: 100)
        XCTAssertEqual(rows.map(\.cap), [80, 85, 90, 95])
        XCTAssertEqual(rows.map(\.reductionPct), [21, 15, 10, 5])
    }

    func testComparisonAt80OrBelowIsEmpty() {
        XCTAssertTrue(ChargeLimitInsight.chargeLimitComparison(currentMaxSoc: 80).isEmpty)
        XCTAssertTrue(ChargeLimitInsight.chargeLimitComparison(currentMaxSoc: 75).isEmpty)
    }

    func testComparisonAt85ReturnsOnlyCap80() {
        let rows = ChargeLimitInsight.chargeLimitComparison(currentMaxSoc: 85)
        XCTAssertEqual(rows.map(\.cap), [80])
        XCTAssertEqual(rows.map(\.reductionPct), [6])
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

    // MARK: - nativeLimitHolding (authoritative BMS ChargerData read)

    func testNativeLimitHoldingWhenHeldOnAC() {
        // On AC, not charging, sitting at 80% with a non-zero reason → the OS is holding the pack.
        XCTAssertTrue(ChargeLimitInsight.nativeLimitHolding(
            isOnACPower: true, isCharging: false, currentCapacityPercent: 80, notChargingReason: 16777216))
    }

    func testNativeLimitNotHoldingWhileCharging() {
        XCTAssertFalse(ChargeLimitInsight.nativeLimitHolding(
            isOnACPower: true, isCharging: true, currentCapacityPercent: 60, notChargingReason: 16777216))
    }

    func testNativeLimitNotHoldingOnBattery() {
        XCTAssertFalse(ChargeLimitInsight.nativeLimitHolding(
            isOnACPower: false, isCharging: false, currentCapacityPercent: 80, notChargingReason: 16777216))
    }

    func testNativeLimitNotHoldingWhenFull() {
        // 100% on AC, not charging is a normal full pack, not a limit — the ≤90 ceiling excludes it.
        XCTAssertFalse(ChargeLimitInsight.nativeLimitHolding(
            isOnACPower: true, isCharging: false, currentCapacityPercent: 100, notChargingReason: 16777216))
    }

    func testNativeLimitNotHoldingNearFull() {
        // 95% holding could be a 95 limit OR a near-full taper — ambiguous, so excluded (≤90).
        XCTAssertFalse(ChargeLimitInsight.nativeLimitHolding(
            isOnACPower: true, isCharging: false, currentCapacityPercent: 95, notChargingReason: 16777216))
    }

    func testNativeLimitNotHoldingWithoutReason() {
        XCTAssertFalse(ChargeLimitInsight.nativeLimitHolding(
            isOnACPower: true, isCharging: false, currentCapacityPercent: 80, notChargingReason: nil))
        XCTAssertFalse(ChargeLimitInsight.nativeLimitHolding(
            isOnACPower: true, isCharging: false, currentCapacityPercent: 80, notChargingReason: 0))
    }

    // MARK: - classify with authoritative override

    func testClassifyAuthoritativeOverridesHighExposure() {
        // dailyMaxSoc=95 alone → highExposure, but a confirmed hold → limitActive wins.
        XCTAssertEqual(ChargeLimitInsight.classify(dailyMaxSoc: 95, nativeLimitHolding: true), .limitActive)
    }

    func testClassifyAuthoritativeOverridesNilSoc() {
        XCTAssertEqual(ChargeLimitInsight.classify(dailyMaxSoc: nil, nativeLimitHolding: true), .limitActive)
    }

    func testClassifyFallsBackToInferenceWhenNotHolding() {
        XCTAssertEqual(
            ChargeLimitInsight.classify(dailyMaxSoc: 95, nativeLimitHolding: false),
            .highExposure(reductionPct: 16))
        XCTAssertEqual(ChargeLimitInsight.classify(dailyMaxSoc: 85, nativeLimitHolding: false), .normal)
    }
}
