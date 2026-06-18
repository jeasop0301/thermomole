import XCTest
@testable import ThermoMoleCore

final class AgingStrainStoreTests: XCTestCase {
    private func tempStore() -> (AgingStrainStore, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = AgingStrainStore(fileURL: root.appendingPathComponent("aging-strain.json"))
        return (store, root)
    }

    func testRoundTrip() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let record = AgingStrainRecord(days: [
            DailyAgingStrain(day: "2026-06-16", effectiveSeconds: 200, calendarSeconds: 100, peakMultiplier: 3.5)
        ])
        try store.save(record)
        XCTAssertEqual(try store.load(), record)
    }

    func testMissingFileReturnsNil() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertNil(try store.load())
    }

    func testCorruptFileReturnsNil() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("aging-strain.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)
        XCTAssertNil(try store.load())
    }

    func testPrunedKeepsNewest() {
        let days = (1...40).map { DailyAgingStrain(day: String(format: "2026-03-%02d", $0)) }
        let pruned = AgingStrainRecord(days: days).pruned(toDays: 30)
        XCTAssertEqual(pruned.days.count, 30)
        XCTAssertEqual(pruned.days.first?.day, "2026-03-11")
        XCTAssertEqual(pruned.days.last?.day, "2026-03-40")
    }
}
