import XCTest
@testable import ThermoMoleCore

final class BatteryRingScaleTests: XCTestCase {
    func testFractionClampsAcross20to45() {
        XCTAssertEqual(BatteryRingScale(temperatureC: 20).fraction, 0, accuracy: 0.0001)
        XCTAssertEqual(BatteryRingScale(temperatureC: 45).fraction, 1, accuracy: 0.0001)
        XCTAssertEqual(BatteryRingScale(temperatureC: 32.5).fraction, 0.5, accuracy: 0.0001)
        XCTAssertEqual(BatteryRingScale(temperatureC: 10).fraction, 0, accuracy: 0.0001)
        XCTAssertEqual(BatteryRingScale(temperatureC: 60).fraction, 1, accuracy: 0.0001)
    }

    func testLevelMatchesThresholds() {
        XCTAssertEqual(BatteryRingScale(temperatureC: 30).level, .normal)
        XCTAssertEqual(BatteryRingScale(temperatureC: 43).level, .caution)  // ≥42 → caution
        XCTAssertEqual(BatteryRingScale(temperatureC: 49).level, .hot)      // ≥48 → hot
    }

    func testNilTemperatureIsZeroFractionNormal() {
        let s = BatteryRingScale(temperatureC: nil)
        XCTAssertEqual(s.fraction, 0, accuracy: 0.0001)
        XCTAssertEqual(s.level, .normal)
    }
}
