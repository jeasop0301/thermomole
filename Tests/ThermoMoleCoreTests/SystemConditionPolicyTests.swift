import XCTest
@testable import ThermoMoleCore

final class SystemConditionPolicyTests: XCTestCase {
    func testCPUHotspotMakesMenuBarConditionHotEvenWhenBatteryIsNormal() {
        let condition = SystemConditionPolicy.resolve(
            cpuTemperatureC: 95,
            batteryWarningLevel: .normal,
            memoryPressure: .normal,
            healthBand: .excellent
        )

        XCTAssertEqual(condition, .hot)
    }

    func testBatteryCautionMakesMenuBarConditionCaution() {
        let condition = SystemConditionPolicy.resolve(
            cpuTemperatureC: 55,
            batteryWarningLevel: .caution,
            memoryPressure: .normal,
            healthBand: .excellent
        )

        XCTAssertEqual(condition, .caution)
    }

    func testNormalSensorsKeepMenuBarConditionNormal() {
        let condition = SystemConditionPolicy.resolve(
            cpuTemperatureC: 48,
            batteryWarningLevel: .normal,
            memoryPressure: .normal,
            healthBand: .excellent
        )

        XCTAssertEqual(condition, .normal)
    }
}
