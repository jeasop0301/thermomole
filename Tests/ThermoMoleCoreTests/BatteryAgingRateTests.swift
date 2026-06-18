import XCTest
@testable import ThermoMoleCore

final class BatteryAgingRateTests: XCTestCase {
    func testTempFactorAnchors() {
        XCTAssertEqual(BatteryAgingRate.tempFactor(25), 1.000, accuracy: 0.005)
        XCTAssertEqual(BatteryAgingRate.tempFactor(35), 2.003, accuracy: 0.005)
        XCTAssertEqual(BatteryAgingRate.tempFactor(45), 3.841, accuracy: 0.005)
    }
    func testSocFactorAnchorsAndInterp() {
        XCTAssertEqual(BatteryAgingRate.socFactor(50), 1.00, accuracy: 0.001)
        XCTAssertEqual(BatteryAgingRate.socFactor(100), 1.95, accuracy: 0.001)
        XCTAssertEqual(BatteryAgingRate.socFactor(20), 0.65, accuracy: 0.001)
        XCTAssertEqual(BatteryAgingRate.socFactor(65), 1.275, accuracy: 0.001)
        XCTAssertEqual(BatteryAgingRate.socFactor(0), 0.65, accuracy: 0.001)
        XCTAssertEqual(BatteryAgingRate.socFactor(120), 1.95, accuracy: 0.001)
    }
    func testRawMultiplicative() {
        let r = BatteryAgingRate.evaluate(cellTempC: 35, socPercent: 90, isCharging: true)!
        XCTAssertEqual(r.rawMultiplier, 2.003 * 1.75, accuracy: 0.05)
        XCTAssertEqual(r.multiplier, r.rawMultiplier, accuracy: 0.06)
    }
    func testColdGuardFloorsDisplayAndFlagsChargeCaution() {
        let r = BatteryAgingRate.evaluate(cellTempC: 15, socPercent: 50, isCharging: true)!
        XCTAssertEqual(r.multiplier, 1.0, accuracy: 0.0001)
        XCTAssertTrue(r.coldChargeCaution)
        XCTAssertLessThan(r.rawMultiplier, 1.0)
    }
    func testClampHigh() {
        let r = BatteryAgingRate.evaluate(cellTempC: 70, socPercent: 100, isCharging: false)!
        XCTAssertEqual(r.multiplier, 10.0, accuracy: 0.0001)
    }
    func testNilInputs() {
        XCTAssertNil(BatteryAgingRate.evaluate(cellTempC: nil, socPercent: 50, isCharging: false))
        XCTAssertNil(BatteryAgingRate.evaluate(cellTempC: 30, socPercent: nil, isCharging: false))
    }
    func testDeadBand() {
        // 26°C / 50% SoC / not charging: raw ≈ 1.07 × 1.00 — falls inside the 0.9–1.1 dead-band → snaps to 1.0
        let r = BatteryAgingRate.evaluate(cellTempC: 26, socPercent: 50, isCharging: false)!
        XCTAssertEqual(r.multiplier, 1.0, accuracy: 0.0001)
    }
    func testDominantDriver() {
        // 35°C / 50%: tf≈2.003, sf=1.00 → temperature dominates
        let r1 = BatteryAgingRate.evaluate(cellTempC: 35, socPercent: 50, isCharging: false)!
        XCTAssertEqual(r1.dominantDriver, .temperature)
        // 25°C / 100%: tf≈1.00, sf=1.95 → charge dominates
        let r2 = BatteryAgingRate.evaluate(cellTempC: 25, socPercent: 100, isCharging: false)!
        XCTAssertEqual(r2.dominantDriver, .charge)
        // 35°C / 90%: tf≈2.003≥1.3, sf=1.75≥1.3 → balanced
        let r3 = BatteryAgingRate.evaluate(cellTempC: 35, socPercent: 90, isCharging: false)!
        XCTAssertEqual(r3.dominantDriver, .balanced)
    }
}
