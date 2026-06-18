import XCTest
@testable import ThermoMoleCore

final class ThermalThresholdsTests: XCTestCase {
    func testThresholdConstants() {
        XCTAssertEqual(ThermalThresholds.batteryCautionC, 42.0)
        XCTAssertEqual(ThermalThresholds.batteryHotC, 48.0)
        XCTAssertEqual(ThermalThresholds.batteryExposureWarmC, 40.0)
        XCTAssertEqual(ThermalThresholds.batteryExposureHotC, 45.0)
        XCTAssertEqual(ThermalThresholds.cpuWarmC, 85.0)
        XCTAssertEqual(ThermalThresholds.cpuHotC, 95.0)
    }

    func testBatteryWarningLevelUsesThresholdsAtBoundaries() {
        XCTAssertEqual(TemperatureWarningLevel.batteryLevel(for: 41.0), .normal)
        XCTAssertEqual(TemperatureWarningLevel.batteryLevel(for: ThermalThresholds.batteryCautionC), .caution)
        XCTAssertEqual(TemperatureWarningLevel.batteryLevel(for: 43.0), .caution)
        XCTAssertEqual(TemperatureWarningLevel.batteryLevel(for: 49.0), .hot)
        XCTAssertEqual(TemperatureWarningLevel.batteryLevel(for: ThermalThresholds.batteryHotC), .hot)
    }
}
