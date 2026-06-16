import XCTest
@testable import ThermoMoleCore

final class MemoryCalculatorTests: XCTestCase {
    func testCalculatesActivityMonitorStyleMemory() {
        let snapshot = MemoryCalculator.snapshot(
            pageSize: 16_384,
            activePages: 200_000,
            wiredPages: 100_000,
            compressedPages: 50_000,
            speculativePages: 20_000,
            inactivePages: 80_000,
            freePages: 50_000,
            totalBytes: 8_192_000_000
        )

        XCTAssertEqual(snapshot.usedBytes, 5_734_400_000)
        XCTAssertEqual(snapshot.usedPercent, 70)
        XCTAssertEqual(snapshot.pressure, .normal)
    }

    func testMapsPressure() {
        XCTAssertEqual(MemoryPressure.from(usedPercent: 71), .warning)
        XCTAssertEqual(MemoryPressure.from(usedPercent: 88), .critical)
    }
}
