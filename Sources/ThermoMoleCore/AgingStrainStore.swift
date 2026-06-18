import Foundation

public struct AgingStrainRecord: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var days: [DailyAgingStrain]

    public init(schemaVersion: Int = 1, days: [DailyAgingStrain] = []) {
        self.schemaVersion = schemaVersion
        self.days = days
    }

    /// Keeps the newest `limit` day-entries (sorted by "yyyy-MM-dd" string, which sorts chronologically).
    public func pruned(toDays limit: Int = 30) -> AgingStrainRecord {
        let sorted = days.sorted { $0.day < $1.day }
        return AgingStrainRecord(schemaVersion: schemaVersion, days: Array(sorted.suffix(max(0, limit))))
    }
}

public protocol AgingStrainPersisting: Sendable {
    func load() throws -> AgingStrainRecord?
    func save(_ record: AgingStrainRecord) throws
}

/// Atomic JSON codec for the aging-strain record.
/// Missing file -> nil; corrupt -> nil (try?); unreadable IO -> throws.
public struct AgingStrainStore: AgingStrainPersisting, Sendable {
    public let fileURL: URL

    public init(fileURL: URL = AgingStrainStore.defaultStrainURL) {
        self.fileURL = fileURL
    }

    public static var defaultStrainURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("ThermoMole", isDirectory: true)
            .appendingPathComponent("aging-strain.json")
    }

    public func save(_ record: AgingStrainRecord) throws {
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

    public func load() throws -> AgingStrainRecord? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AgingStrainRecord.self, from: data)
    }
}
