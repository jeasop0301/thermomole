import XCTest
@testable import ThermoMoleCore

final class ThermalThresholdsTests: XCTestCase {
    func testThresholdConstants() {
        XCTAssertEqual(ThermalThresholds.batteryCautionC, 35.0)
        XCTAssertEqual(ThermalThresholds.batteryHotC, 40.0)
        XCTAssertEqual(ThermalThresholds.cpuWarmC, 85.0)
        XCTAssertEqual(ThermalThresholds.cpuHotC, 95.0)
    }

    func testBatteryWarningLevelUsesThresholdsAtBoundaries() {
        XCTAssertEqual(TemperatureWarningLevel.batteryLevel(for: 34.99), .normal)
        XCTAssertEqual(TemperatureWarningLevel.batteryLevel(for: ThermalThresholds.batteryCautionC), .caution)
        XCTAssertEqual(TemperatureWarningLevel.batteryLevel(for: 39.99), .caution)
        XCTAssertEqual(TemperatureWarningLevel.batteryLevel(for: ThermalThresholds.batteryHotC), .hot)
    }
}
