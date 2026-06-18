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

        XCTAssertEqual(thermal.batteryDisplayC, 31.41)               // 표시값은 BMS(ioreg)
        XCTAssertEqual(thermal.batteryTemperatureSource, .ioregTemperature)
        XCTAssertEqual(thermal.batteryWarningLevel, .normal)          // 셀최대 35.8 < 42 → normal (임계값 42/48)
    }

    func testWarningLevelUsesHottestCellNotDisplay() {
        // cellMax 49 ≥ batteryHotC(48) → hot
        let thermal = BatteryTemperaturePolicy.resolve(
            smcCellTemperaturesC: [49.0],
            ioregTemperatureC: 30.0
        )

        XCTAssertEqual(thermal.batteryDisplayC, 30.0)                // 표시값은 BMS(낮음)
        XCTAssertEqual(thermal.batteryTemperatureSource, .ioregTemperature)
        XCTAssertEqual(thermal.batteryWarningLevel, .hot)            // 셀최대 49 ≥ 48 → hot
    }

    func testWarningLevelCautionAtFortyTwo() {
        // cellMax 43 ≥ batteryCautionC(42) but < batteryHotC(48) → caution
        let thermal = BatteryTemperaturePolicy.resolve(
            smcCellTemperaturesC: [43.0],
            ioregTemperatureC: 30.0
        )

        XCTAssertEqual(thermal.batteryDisplayC, 30.0)
        XCTAssertEqual(thermal.batteryWarningLevel, .caution)
    }

    func testWarningLevelNormalWhenBothLow() {
        let thermal = BatteryTemperaturePolicy.resolve(
            smcCellTemperaturesC: [31.0],
            ioregTemperatureC: 30.0
        )

        XCTAssertEqual(thermal.batteryWarningLevel, .normal)
    }

    func testFallsBackToSMCCellMaxWhenIORegTemperatureIsUnavailable() {
        // cellMax 43 ≥ batteryCautionC(42) → caution
        let thermal = BatteryTemperaturePolicy.resolve(
            smcCellTemperaturesC: [43.0],
            ioregTemperatureC: nil
        )

        XCTAssertEqual(thermal.batteryDisplayC, 43.0)
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

    func testRejectsImplausibleIORegAndFallsBackToCell() {
        // 90°C is impossible for a battery pack (misread / wrong-units decode) — reject it.
        let thermal = BatteryTemperaturePolicy.resolve(
            smcCellTemperaturesC: [35.8],
            ioregTemperatureC: 90.0
        )

        XCTAssertEqual(thermal.batteryDisplayC, 35.8)
        XCTAssertEqual(thermal.batteryTemperatureSource, .smcCellMax)
        XCTAssertNil(thermal.batteryIORegC)
    }

    func testRejectsImplausibleCellsAsUnavailable() {
        let thermal = BatteryTemperaturePolicy.resolve(
            smcCellTemperaturesC: [90.0, 127.0],
            ioregTemperatureC: nil
        )

        XCTAssertNil(thermal.batteryDisplayC)
        XCTAssertEqual(thermal.batteryTemperatureSource, .unavailable)
        XCTAssertNil(thermal.batteryCellMaxC)
    }

    func testAcceptsHighButPlausibleBatteryTemperature() {
        let thermal = BatteryTemperaturePolicy.resolve(
            smcCellTemperaturesC: [],
            ioregTemperatureC: 79.0
        )

        XCTAssertEqual(thermal.batteryDisplayC, 79.0)
        XCTAssertEqual(thermal.batteryTemperatureSource, .ioregTemperature)
    }

    func testIsValidBatteryTemperatureBounds() {
        XCTAssertTrue(ThermalPolicy.isValidBatteryTemperature(0.1))
        XCTAssertTrue(ThermalPolicy.isValidBatteryTemperature(79.9))
        XCTAssertFalse(ThermalPolicy.isValidBatteryTemperature(0))
        XCTAssertFalse(ThermalPolicy.isValidBatteryTemperature(80))
        XCTAssertFalse(ThermalPolicy.isValidBatteryTemperature(127))
    }

    func testVirtualTemperaturePropagatedWhenValid() {
        let thermal = BatteryTemperaturePolicy.resolve(
            smcCellTemperaturesC: [31.4],
            ioregTemperatureC: 30.45,
            virtualTemperatureC: 31.19
        )

        XCTAssertEqual(thermal.batteryVirtualC, 31.19)
        XCTAssertEqual(thermal.batteryDisplayC, 30.45)          // 주값 불변(ioreg)
        XCTAssertEqual(thermal.batteryTemperatureSource, .ioregTemperature)
    }

    func testVirtualTemperatureRejectedWhenOutOfRange() {
        let thermal = BatteryTemperaturePolicy.resolve(
            smcCellTemperaturesC: [],
            ioregTemperatureC: 30.0,
            virtualTemperatureC: 999.0
        )

        XCTAssertNil(thermal.batteryVirtualC)
    }

    func testVirtualTemperatureNilByDefault() {
        let thermal = BatteryTemperaturePolicy.resolve(
            smcCellTemperaturesC: [30.0],
            ioregTemperatureC: 30.0
        )

        XCTAssertNil(thermal.batteryVirtualC)
    }
}
