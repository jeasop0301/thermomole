import XCTest
@testable import ThermoMoleCore

final class ChargeExposureStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("tm-charge-test-\(UUID().uuidString)")
            .appendingPathComponent("charge-exposure.json")
    }

    func testRoundTrip() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ChargeExposureStore(fileURL: url)
        let record = ChargeExposureRecord(days: [
            DailyChargeExposure(day: "2026-06-16", secondsAbove80OnAC: 120, secondsAbove95OnAC: 30, peakPercentOnAC: 99)
        ])
        try store.save(record)
        XCTAssertEqual(try store.load(), record)
    }

    func testMissingFileLoadsNil() throws {
        let store = ChargeExposureStore(fileURL: tempURL())
        XCTAssertNil(try store.load())
    }

    func testPruneKeepsNewest30Days() {
        let days = (1...40).map { DailyChargeExposure(day: String(format: "2026-01-%02d", $0)) }
        let pruned = ChargeExposureRecord(days: days).pruned(toDays: 30)
        XCTAssertEqual(pruned.days.count, 30)
        XCTAssertEqual(pruned.days.first?.day, "2026-01-11")
        XCTAssertEqual(pruned.days.last?.day, "2026-01-40")
    }
}
