import XCTest
@testable import ThermoMoleCore

final class StatusSnapshotStoreTests: XCTestCase {
    func testStatusSnapshotStoreWritesAndReadsLastSnapshot() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StatusSnapshotStore(snapshotURL: root.appendingPathComponent("last-status.json"))
        var snapshot = SystemSnapshot.placeholder
        snapshot.sampledAt = Date(timeIntervalSince1970: 123)
        snapshot.chipName = "M4"
        snapshot.modelIdentifier = "Mac16,1"
        snapshot.memory = MemorySnapshot(
            usedBytes: 8_000,
            totalBytes: 16_000,
            usedPercent: 50,
            pressure: .normal,
            activeBytes: 4_000,
            wiredBytes: 2_000,
            compressedBytes: 2_000,
            freeBytes: 8_000
        )
        snapshot.thermal = ThermalSnapshot(
            cpuDisplayC: 42.5,
            cpuTemperatureSource: .cpuDieHotspot,
            batteryDisplayC: 31.48,
            batteryTemperatureSource: .ioregTemperature,
            batteryIORegC: 31.48,
            batteryWarningLevel: .normal
        )

        try store.save(snapshot)
        let loaded = try store.load()

        XCTAssertEqual(loaded, snapshot)
    }

    func testStatusSnapshotStoreReturnsNilForMissingOrCorruptSnapshot() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("last-status.json")
        let store = StatusSnapshotStore(snapshotURL: url)

        XCTAssertNil(try store.load())

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)

        XCTAssertNil(try store.load())
    }
}
