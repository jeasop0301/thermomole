import XCTest
@testable import ThermoMoleCore

final class BatterySensorSummaryTests: XCTestCase {
    private func thermal(ioreg: Double?, cellMax: Double?, virtual: Double?, mismatch: Bool = false) -> ThermalSnapshot {
        ThermalSnapshot(
            batteryDisplayC: ioreg,
            batteryTemperatureSource: ioreg != nil ? .ioregTemperature : .unavailable,
            batteryCellMaxC: cellMax,
            batteryIORegC: ioreg,
            batteryVirtualC: virtual,
            batteryWarningLevel: .normal,
            hasBatterySensorMismatch: mismatch
        )
    }

    func testAllThreeSourcesInOrder() {
        let summary = BatterySensorSummary(thermal: thermal(ioreg: 30.45, cellMax: 31.4, virtual: 31.19))
        XCTAssertEqual(summary.rows.map(\.kind), [.bms, .cellMax, .virtual])
        XCTAssertEqual(summary.rows.map(\.temperatureC), [30.45, 31.4, 31.19])
    }

    func testVirtualOmittedWhenNil() {
        let summary = BatterySensorSummary(thermal: thermal(ioreg: 30.0, cellMax: 31.0, virtual: nil))
        XCTAssertEqual(summary.rows.map(\.kind), [.bms, .cellMax])
    }

    func testOnlyCellMaxWhenIORegMissing() {
        let summary = BatterySensorSummary(thermal: thermal(ioreg: nil, cellMax: 31.0, virtual: nil))
        XCTAssertEqual(summary.rows.map(\.kind), [.cellMax])
    }

    func testMismatchPropagated() {
        let summary = BatterySensorSummary(thermal: thermal(ioreg: 30.0, cellMax: 33.0, virtual: nil, mismatch: true))
        XCTAssertTrue(summary.hasMismatch)
    }
}
