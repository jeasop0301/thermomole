import Foundation

public struct ThermalExposureRecord: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var days: [DailyThermalExposure]

    public init(schemaVersion: Int = 2, days: [DailyThermalExposure] = []) {
        self.schemaVersion = schemaVersion
        self.days = days
    }

    /// Keeps the newest `limit` day-entries (sorted by "yyyy-MM-dd" string, which sorts chronologically).
    public func pruned(toDays limit: Int = 30) -> ThermalExposureRecord {
        let sorted = days.sorted { $0.day < $1.day }
        return ThermalExposureRecord(schemaVersion: schemaVersion, days: Array(sorted.suffix(max(0, limit))))
    }
}

public protocol ThermalExposurePersisting: Sendable {
    func load() throws -> ThermalExposureRecord?
    func save(_ record: ThermalExposureRecord) throws
}

/// Atomic JSON codec for the exposure record. Mirrors StatusSnapshotStore exactly:
/// missing file -> nil; corrupt-but-readable -> nil (try?); unreadable IO -> throws.
public struct ThermalExposureStore: ThermalExposurePersisting, Sendable {
    public let fileURL: URL

    public init(fileURL: URL = ThermalExposureStore.defaultExposureURL) {
        self.fileURL = fileURL
    }

    public static var defaultExposureURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("ThermoMole", isDirectory: true)
            .appendingPathComponent("thermal-exposure.json")
    }

    public func save(_ record: ThermalExposureRecord) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        try data.write(to: fileURL, options: .atomic)
    }

    public func load() throws -> ThermalExposureRecord? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ThermalExposureRecord.self, from: data)
    }
}
