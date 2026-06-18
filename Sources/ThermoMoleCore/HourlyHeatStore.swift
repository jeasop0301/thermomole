import Foundation

public struct HourlyHeatRecord: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var days: [DailyHourlyHeat]

    public init(schemaVersion: Int = 1, days: [DailyHourlyHeat] = []) {
        self.schemaVersion = schemaVersion
        self.days = days
    }

    /// Keeps the newest `limit` day-entries (by "yyyy-MM-dd" string order == chronological).
    public func pruned(toDays limit: Int = 30) -> HourlyHeatRecord {
        let sorted = days.sorted { $0.day < $1.day }
        return HourlyHeatRecord(schemaVersion: schemaVersion, days: Array(sorted.suffix(max(0, limit))))
    }
}

public protocol HourlyHeatPersisting: Sendable {
    func load() throws -> HourlyHeatRecord?
    func save(_ record: HourlyHeatRecord) throws
}

/// Atomic JSON codec. Mirrors ThermalExposureStore: missing file -> nil;
/// corrupt-but-readable -> nil (try?); unreadable IO -> throws.
public struct HourlyHeatStore: HourlyHeatPersisting, Sendable {
    public let fileURL: URL

    public init(fileURL: URL = HourlyHeatStore.defaultHourlyHeatURL) { self.fileURL = fileURL }

    public static var defaultHourlyHeatURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("ThermoMole", isDirectory: true)
            .appendingPathComponent("hourly-heat.json")
    }

    public func save(_ record: HourlyHeatRecord) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(record).write(to: fileURL, options: .atomic)
    }

    public func load() throws -> HourlyHeatRecord? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HourlyHeatRecord.self, from: data)
    }
}
