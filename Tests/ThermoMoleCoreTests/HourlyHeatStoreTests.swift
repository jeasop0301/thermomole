// Tests/ThermoMoleCoreTests/HourlyHeatStoreTests.swift
import XCTest
@testable import ThermoMoleCore

final class HourlyHeatStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("hourly-heat-\(UUID().uuidString).json")
    }

    private func day(_ d: String, hour: Int, sum: Double, count: Int) -> DailyHourlyHeat {
        var hh = DailyHourlyHeat.empty(day: d)
        hh.hours[hour] = HourHeatCell(sumC: sum, count: count, peakC: sum / Double(count))
        return hh
    }

    func testRoundTrip() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = HourlyHeatStore(fileURL: url)
        let record = HourlyHeatRecord(days: [day("2026-06-18", hour: 14, sum: 76, count: 2)])
        try store.save(record)
        let loaded = try store.load()
        XCTAssertEqual(loaded, record)
        XCTAssertEqual(loaded?.days.first?.hours[14].meanC ?? 0, 38, accuracy: 0.0001)
    }

    func testMissingFileReturnsNil() throws {
        XCTAssertNil(try HourlyHeatStore(fileURL: tempURL()).load())
    }

    func testCorruptReturnsNil() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = HourlyHeatStore(fileURL: url)
        try Data("not json".utf8).write(to: url)
        XCTAssertNil(try store.load())

        let record = HourlyHeatRecord(days: [day("2026-06-18", hour: 14, sum: 76, count: 2)])
        try store.save(record)
        XCTAssertEqual(try store.load(), record)
    }

    func testUnreadablePathThrows() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // fileURL points at a directory: fileExists is true, but reading it as Data throws.
        let dirAsFile = root.appendingPathComponent("hourly-heat.json", isDirectory: true)
        try FileManager.default.createDirectory(at: dirAsFile, withIntermediateDirectories: true)
        let store = HourlyHeatStore(fileURL: dirAsFile)
        XCTAssertThrowsError(try store.load())
    }

    func testPrunedKeepsNewest() {
        let days = (1...40).map { day(String(format: "2026-05-%02d", $0), hour: 0, sum: 30, count: 1) }
        let pruned = HourlyHeatRecord(days: days).pruned(toDays: 30)
        XCTAssertEqual(pruned.days.count, 30)
        XCTAssertEqual(pruned.days.first?.day, "2026-05-11")
        XCTAssertEqual(pruned.days.last?.day, "2026-05-40") // string suffix order
    }

    func testDecodeNormalizesShortHoursArray() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"schemaVersion":1,"days":[{"day":"2026-06-18","hours":[]}]}"#.utf8).write(to: url)
        let loaded = try HourlyHeatStore(fileURL: url).load()
        XCTAssertEqual(loaded?.days.first?.hours.count, 24)
    }
}
