import XCTest
@testable import ThermoMoleCore

final class ThermalExposureStoreTests: XCTestCase {
    func testRoundTrip() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ThermalExposureStore(fileURL: root.appendingPathComponent("thermal-exposure.json"))
        let record = ThermalExposureRecord(days: [
            DailyThermalExposure(day: "2026-06-16", secondsAbove40: 120, secondsAbove45: 30, peakC: 41.2)
        ])

        try store.save(record)
        XCTAssertEqual(try store.load(), record)
    }

    func testMissingFileReturnsNil() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ThermalExposureStore(fileURL: root.appendingPathComponent("thermal-exposure.json"))
        XCTAssertNil(try store.load())
    }

    func testCorruptFileReturnsNilThenOverwrites() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("thermal-exposure.json")
        let store = ThermalExposureStore(fileURL: url)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)

        XCTAssertNil(try store.load())

        let record = ThermalExposureRecord(days: [DailyThermalExposure(day: "2026-06-16", secondsAbove40: 5)])
        try store.save(record)
        XCTAssertEqual(try store.load(), record)
    }

    func testPrunedKeepsNewestThirtyDays() {
        let days = (1...40).map { DailyThermalExposure(day: String(format: "2026-03-%02d", $0)) }
        let pruned = ThermalExposureRecord(days: days).pruned(toDays: 30)
        XCTAssertEqual(pruned.days.count, 30)
        XCTAssertEqual(pruned.days.first?.day, "2026-03-11")
        XCTAssertEqual(pruned.days.last?.day, "2026-03-40")
    }

    func testUnreadablePathThrows() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // fileURL points at a directory: fileExists is true, but reading it as Data throws.
        let dirAsFile = root.appendingPathComponent("thermal-exposure.json", isDirectory: true)
        try FileManager.default.createDirectory(at: dirAsFile, withIntermediateDirectories: true)
        let store = ThermalExposureStore(fileURL: dirAsFile)
        XCTAssertThrowsError(try store.load())
    }
}
