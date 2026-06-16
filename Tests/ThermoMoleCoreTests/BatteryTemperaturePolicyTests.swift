import XCTest
@testable import ThermoMoleCore

final class BatteryTemperaturePolicyTests: XCTestCase {
    func testParsesRealAppleSmartBatteryTemperature() throws {
        let sample = """
          "Temperature" = 3141
          "VirtualTemperature" = 4089
          "CycleCount" = 7
        """

        let parsed = AppleSmartBatteryParser.parse(sample)

        XCTAssertEqual(parsed.temperatureC, 31.41)
        XCTAssertEqual(parsed.virtualTemperatureC, 40.89)
    }

    func testChoosesIORegTemperatureBeforeSMCCellMax() {
        let thermal = BatteryTemperaturePolicy.resolve(
            smcCellTemperaturesC: [32.4, 35.8, 34.1],
            ioregTemperatureC: 31.41
        )

        XCTAssertEqual(thermal.batteryDisplayC, 31.41)
        XCTAssertEqual(thermal.batteryTemperatureSource, .ioregTemperature)
        XCTAssertEqual(thermal.batteryWarningLevel, .normal)
    }

    func testFallsBackToSMCCellMaxWhenIORegTemperatureIsUnavailable() {
        let thermal = BatteryTemperaturePolicy.resolve(
            smcCellTemperaturesC: [35.8],
            ioregTemperatureC: nil
        )

        XCTAssertEqual(thermal.batteryDisplayC, 35.8)
        XCTAssertEqual(thermal.batteryTemperatureSource, .smcCellMax)
        XCTAssertEqual(thermal.batteryWarningLevel, .caution)
    }

    func testDetectsSensorMismatch() {
        let thermal = BatteryTemperaturePolicy.resolve(
            smcCellTemperaturesC: [36.0],
            ioregTemperatureC: 31.0
        )

        XCTAssertTrue(thermal.hasBatterySensorMismatch)
    }
}
