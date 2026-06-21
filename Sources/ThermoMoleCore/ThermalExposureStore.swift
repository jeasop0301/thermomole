import Foundation

/// Forward-only "since install" cumulative thermal exposure. Captures completed days BEFORE the
/// 30-day prune drops them. Honest framing: "since install", never "lifetime". Mirrors
/// CumulativeChargeExposure.
public struct CumulativeThermalExposure: Codable, Equatable, Sendable {
    public var firstDay: String?           // earliest counted "yyyy-MM-dd"
    public var lastCountedDay: String?     // newest counted "yyyy-MM-dd" (high-water mark)
    public var secondsAbove40: Double
    public var secondsAbove45: Double

    public init(
        firstDay: String? = nil,
        lastCountedDay: String? = nil,
        secondsAbove40: Double = 0,
        secondsAbove45: Double = 0
    ) {
        self.firstDay = firstDay
        self.lastCountedDay = lastCountedDay
        self.secondsAbove40 = secondsAbove40
        self.secondsAbove45 = secondsAbove45
    }

    /// Folds in ONLY days strictly before `today` AND newer than `lastCountedDay`. Idempotent,
    /// monotonic, prune-surviving — see CumulativeChargeExposure.accumulating for the contract.
    public func accumulating(days: [DailyThermalExposure], today: String) -> CumulativeThermalExposure {
        var result = self
        for day in days.sorted(by: { $0.day < $1.day }) {
            guard day.day < today else { continue }
            if let last = result.lastCountedDay, day.day <= last { continue }
            result.secondsAbove40 += day.secondsAbove40
            result.secondsAbove45 += day.secondsAbove45
            result.firstDay = result.firstDay.map { min($0, day.day) } ?? day.day
            result.lastCountedDay = result.lastCountedDay.map { max($0, day.day) } ?? day.day
        }
        return result
    }
}

public struct ThermalExposureRecord: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var days: [DailyThermalExposure]
    public var cumulative: CumulativeThermalExposure

    public init(
        schemaVersion: Int = 3,
        days: [DailyThermalExposure] = [],
        cumulative: CumulativeThermalExposure = CumulativeThermalExposure()
    ) {
        self.schemaVersion = schemaVersion
        self.days = days
        self.cumulative = cumulative
    }

    // Custom decode so pre-cumulative JSON (v2, no `cumulative` key) still loads with an empty
    // cumulative. Note v1 (old 35/40 bands) is still discarded by the coordinator's bootstrap.
    private enum CodingKeys: String, CodingKey { case schemaVersion, days, cumulative }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        self.days = try c.decode([DailyThermalExposure].self, forKey: .days)
        self.cumulative = try c.decodeIfPresent(CumulativeThermalExposure.self, forKey: .cumulative)
            ?? CumulativeThermalExposure()
    }

    /// Keeps the newest `limit` day-entries (sorted by "yyyy-MM-dd" string, which sorts chronologically).
    /// Cumulative is preserved across the prune.
    public func pruned(toDays limit: Int = 30) -> ThermalExposureRecord {
        let sorted = days.sorted { $0.day < $1.day }
        return ThermalExposureRecord(
            schemaVersion: schemaVersion,
            days: Array(sorted.suffix(max(0, limit))),
            cumulative: cumulative
        )
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
