import XCTest
@testable import ThermoMoleCore

final class AppleSmartBatteryParserTests: XCTestCase {

    /// The nested `"BatteryData" = {…}` blob carries its own DesignCapacity/CycleCount/Voltage
    /// and appears BEFORE the top-level keys. The parser must read the TOP-LEVEL values, not the
    /// shadowing nested ones (which diverge after a battery service / firmware re-estimation).
    func testTopLevelKeysWinOverNestedBatteryData() {
        let raw = """
              "BatteryData" = {"DesignCapacity"=9999,"CycleCount"=999,"Voltage"=9999,"MaximumTemperature"=99,"Qmax"=(6094,6093)}
              "DesignCapacity" = 5760
              "CycleCount" = 8
              "Voltage" = 11698
              "Temperature" = 3010
              "AppleRawMaxCapacity" = 5815
              "Amperage" = 0
        """
        let info = AppleSmartBatteryParser.parse(raw)
        XCTAssertEqual(info.designCapacityMAh, 5760)   // not 9999
        XCTAssertEqual(info.cycleCount, 8)             // not 999
        XCTAssertEqual(info.voltageMV, 11698)          // not 9999
        XCTAssertEqual(info.rawMaxCapacityMAh, 5815)
        XCTAssertEqual(info.temperatureC ?? 0, 30.1, accuracy: 0.001)  // top-level, not nested Maximum 99
    }

    func testParsesNormallyWhenNoBatteryDataBlock() {
        let raw = """
              "DesignCapacity" = 5760
              "CycleCount" = 12
              "AppleRawMaxCapacity" = 5500
        """
        let info = AppleSmartBatteryParser.parse(raw)
        XCTAssertEqual(info.designCapacityMAh, 5760)
        XCTAssertEqual(info.cycleCount, 12)
        XCTAssertEqual(info.healthPercent, 95) // 5500/5760
    }

    func testStrippingHandlesNestedBraces() {
        let raw = #""BatteryData" = {"A"={"B"=1},"DesignCapacity"=1} "DesignCapacity" = 7"#
        XCTAssertEqual(AppleSmartBatteryParser.parse(raw).designCapacityMAh, 7)
    }

    /// DailyMaxSoc / DailyMinSoc live INSIDE the nested BatteryData block (so they are not in the
    /// stripped top-level view). They must be read from the full raw string.
    func testParsesDailySocFromNestedBatteryData() {
        let raw = """
              "BatteryData" = {"DesignCapacity"=9999,"DailyMaxSoc"=98,"DailyMinSoc"=52,"Qmax"=(6094,6093)}
              "DesignCapacity" = 5760
              "CycleCount" = 8
        """
        let info = AppleSmartBatteryParser.parse(raw)
        XCTAssertEqual(info.dailyMaxSoc, 98)
        XCTAssertEqual(info.dailyMinSoc, 52)
    }

    func testDailySocAbsentIsNil() {
        let raw = """
              "DesignCapacity" = 5760
              "CycleCount" = 12
        """
        let info = AppleSmartBatteryParser.parse(raw)
        XCTAssertNil(info.dailyMaxSoc)
        XCTAssertNil(info.dailyMinSoc)
    }
}
