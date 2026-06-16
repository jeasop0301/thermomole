import XCTest
@testable import ThermoMoleCore

final class BatteryHealthStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("tm-health-test-\(UUID().uuidString)")
            .appendingPathComponent("battery-health.json")
    }

    func testRoundTrip() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = BatteryHealthStore(fileURL: url)
        let record = BatteryHealthRecord(days: [
            DailyBatteryHealth(day: "2026-06-16", healthPercent: 92, cycleCount: 120, maxCapacityMAh: 4500, designCapacityMAh: 4900)
        ])
        try store.save(record)
        XCTAssertEqual(try store.load(), record)
    }

    func testMissingFileLoadsNil() throws {
        let store = BatteryHealthStore(fileURL: tempURL())
        XCTAssertNil(try store.load())
    }

    func testPruneKeepsNewest400Days() {
        let days = (1...450).map { DailyBatteryHealth(day: String(format: "2026-%05d", $0), healthPercent: 90, cycleCount: 1, maxCapacityMAh: 1, designCapacityMAh: 1) }
        let pruned = BatteryHealthRecord(days: days).pruned(toDays: 400)
        XCTAssertEqual(pruned.days.count, 400)
    }
}
