import Foundation

public struct BatteryHealthRecord: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var days: [DailyBatteryHealth]

    public init(schemaVersion: Int = 1, days: [DailyBatteryHealth] = []) {
        self.schemaVersion = schemaVersion
        self.days = days
    }

    /// Keeps the newest `limit` day-entries. Health history is tiny, so the window is long.
    public func pruned(toDays limit: Int = 400) -> BatteryHealthRecord {
        let sorted = days.sorted { $0.day < $1.day }
        return BatteryHealthRecord(schemaVersion: schemaVersion, days: Array(sorted.suffix(max(0, limit))))
    }
}

public protocol BatteryHealthPersisting: Sendable {
    func load() throws -> BatteryHealthRecord?
    func save(_ record: BatteryHealthRecord) throws
}

/// Atomic JSON codec for the battery-health log. Mirrors ThermalExposureStore.
public struct BatteryHealthStore: BatteryHealthPersisting, Sendable {
    public let fileURL: URL

    public init(fileURL: URL = BatteryHealthStore.defaultURL) {
        self.fileURL = fileURL
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("ThermoMole", isDirectory: true)
            .appendingPathComponent("battery-health.json")
    }

    public func save(_ record: BatteryHealthRecord) throws {
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

    public func load() throws -> BatteryHealthRecord? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(BatteryHealthRecord.self, from: data)
    }
}
