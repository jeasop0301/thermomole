import XCTest
@testable import ThermoMoleCore

final class AppleSmartBatteryPowerTests: XCTestCase {
    func testInstantPowerIsVoltageTimesAmperage() {
        let info = AppleSmartBatteryInfo(voltageMV: 11717, amperageMA: 2000)
        XCTAssertEqual(info.instantPowerW, 23.434, accuracy: 0.001)
    }

    func testInstantPowerNegativeWhenDischarging() {
        let info = AppleSmartBatteryInfo(voltageMV: 12000, amperageMA: -1500)
        XCTAssertEqual(info.instantPowerW, -18.0, accuracy: 0.001)
    }

    func testInstantPowerZeroWithoutData() {
        XCTAssertEqual(AppleSmartBatteryInfo().instantPowerW, 0, accuracy: 0.001)
    }

    func testParsesVoltageAndAmperageIntoPower() {
        let raw = """
          "Voltage" = 11717
          "Amperage" = 2000
        """
        let info = AppleSmartBatteryParser.parse(raw)
        XCTAssertEqual(info.instantPowerW, 23.434, accuracy: 0.001)
    }

    func testParsesDischargeAmperageAsNegative() {
        // ioreg prints negative Amperage as a 64-bit two's-complement unsigned;
        // 18446744073709548286 == -3330 mA. The old formula overflowed to 0 (or crashed).
        let raw = """
          "Voltage" = 12000
          "Amperage" = 18446744073709548286
        """
        let info = AppleSmartBatteryParser.parse(raw)
        XCTAssertEqual(info.amperageMA, -3330)
        XCTAssertEqual(info.instantPowerW, -39.96, accuracy: 0.01)
    }
}
