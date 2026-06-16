import Foundation

public struct ChargeExposureRecord: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var days: [DailyChargeExposure]

    public init(schemaVersion: Int = 1, days: [DailyChargeExposure] = []) {
        self.schemaVersion = schemaVersion
        self.days = days
    }

    /// Keeps the newest `limit` day-entries ("yyyy-MM-dd" sorts chronologically).
    public func pruned(toDays limit: Int = 30) -> ChargeExposureRecord {
        let sorted = days.sorted { $0.day < $1.day }
        return ChargeExposureRecord(schemaVersion: schemaVersion, days: Array(sorted.suffix(max(0, limit))))
    }
}

public protocol ChargeExposurePersisting: Sendable {
    func load() throws -> ChargeExposureRecord?
    func save(_ record: ChargeExposureRecord) throws
}

/// Atomic JSON codec for the SoC-dwell record. Missing file -> nil; corrupt-but-readable ->
/// nil; unreadable IO -> throws. Mirrors ThermalExposureStore.
public struct ChargeExposureStore: ChargeExposurePersisting, Sendable {
    public let fileURL: URL

    public init(fileURL: URL = ChargeExposureStore.defaultURL) {
        self.fileURL = fileURL
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("ThermoMole", isDirectory: true)
            .appendingPathComponent("charge-exposure.json")
    }

    public func save(_ record: ChargeExposureRecord) throws {
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

    public func load() throws -> ChargeExposureRecord? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ChargeExposureRecord.self, from: data)
    }
}
