import XCTest
@testable import ThermoMoleCore

final class ThermalPolicyTests: XCTestCase {
    func testUsesCPUHotspotFirst() {
        let resolved = ThermalPolicy.resolveCPUTemperature(
            cpuDieHotspotC: 72.4,
            cpuAverageC: 55.1
        )

        XCTAssertEqual(resolved.valueC, 72.4)
        XCTAssertEqual(resolved.source, .cpuDieHotspot)
    }

    func testFallsBackToAverage() {
        let resolved = ThermalPolicy.resolveCPUTemperature(
            cpuDieHotspotC: 0,
            cpuAverageC: 55.1
        )

        XCTAssertEqual(resolved.valueC, 55.1)
        XCTAssertEqual(resolved.source, .cpuAverage)
    }
}
