import XCTest
@testable import ThermoMoleCore

final class MetricsExportStoreTests: XCTestCase {

    private func sampleExport() -> FleetMetricsExport {
        FleetMetricsExport(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            appVersion: "0.2.0",
            batteryHealthPercent: 92,
            cycleCount: 211,
            agingMultiplier: 1.8,
            agingBand: "elevated",
            dominantDriver: "charge",
            calibrationStatus: "calibrated",
            calibrationBand: "faster",
            dailyMaxSoc: 96,
            dailyMinSoc: 74,
            chargeLimitState: "highExposure",
            cappingAt80ReductionPct: 16,
            nativeChargeLimitAvailable: true,
            batteryTempC: 31.4,
            secondsAbove80OnACToday: 12_345.0,
            secondsAbove95OnACToday: 678.0
        )
    }

    func testWritesAndReadsBack() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MetricsExportStore(exportURL: root.appendingPathComponent("fleet-metrics.json"))

        let export = sampleExport()
        try store.save(export)
        XCTAssertEqual(try store.load(), export)
    }

    func testSaveCreatesIntermediateDirectories() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("nested", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let url = root.appendingPathComponent("fleet-metrics.json")
        let store = MetricsExportStore(exportURL: url)

        try store.save(sampleExport())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testReturnsNilForMissingOrCorruptFile() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("fleet-metrics.json")
        let store = MetricsExportStore(exportURL: url)

        XCTAssertNil(try store.load())

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        XCTAssertNil(try store.load())
    }

    func testDefaultURLPointsAtApplicationSupport() {
        let url = MetricsExportStore.defaultURL
        XCTAssertEqual(url.lastPathComponent, "fleet-metrics.json")
        XCTAssertTrue(url.path.contains("Application Support/ThermoMole"), url.path)
    }
}
