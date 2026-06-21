import Foundation

/// Persists the machine-readable `FleetMetricsExport` to a stable on-disk path so remote/headless
/// Macs can be polled without opening the UI. Mirrors `StatusSnapshotStore`: deterministic encoding
/// (`.sortedKeys` + ISO-8601 dates) and an atomic write into Application Support.
public struct MetricsExportStore: Sendable {
    public var exportURL: URL

    public init(exportURL: URL = MetricsExportStore.defaultURL) {
        self.exportURL = exportURL
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("ThermoMole", isDirectory: true)
            .appendingPathComponent("fleet-metrics.json")
    }

    public static var live: MetricsExportStore {
        MetricsExportStore()
    }

    public func save(_ export: FleetMetricsExport) throws {
        try FileManager.default.createDirectory(
            at: exportURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(export)
        try data.write(to: exportURL, options: .atomic)
    }

    public func load() throws -> FleetMetricsExport? {
        guard FileManager.default.fileExists(atPath: exportURL.path) else { return nil }
        let data = try Data(contentsOf: exportURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(FleetMetricsExport.self, from: data)
    }
}
