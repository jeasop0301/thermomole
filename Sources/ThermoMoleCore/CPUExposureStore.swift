import Foundation

public struct CPUExposureRecord: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var days: [DailyCPUExposure]

    public init(schemaVersion: Int = 1, days: [DailyCPUExposure] = []) {
        self.schemaVersion = schemaVersion
        self.days = days
    }

    public func pruned(toDays limit: Int = 30) -> CPUExposureRecord {
        let sorted = days.sorted { $0.day < $1.day }
        return CPUExposureRecord(schemaVersion: schemaVersion, days: Array(sorted.suffix(max(0, limit))))
    }
}

public protocol CPUExposurePersisting: Sendable {
    func load() throws -> CPUExposureRecord?
    func save(_ record: CPUExposureRecord) throws
}

/// Atomic JSON codec for the CPU-exposure record. Mirrors ThermalExposureStore.
public struct CPUExposureStore: CPUExposurePersisting, Sendable {
    public let fileURL: URL

    public init(fileURL: URL = CPUExposureStore.defaultURL) {
        self.fileURL = fileURL
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("ThermoMole", isDirectory: true)
            .appendingPathComponent("cpu-exposure.json")
    }

    public func save(_ record: CPUExposureRecord) throws {
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

    public func load() throws -> CPUExposureRecord? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CPUExposureRecord.self, from: data)
    }
}
