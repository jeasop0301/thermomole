import Foundation

/// Forward-only "since install" cumulative high-SoC dwell. Captures completed days BEFORE the
/// 30-day prune drops them, so totals reflect the whole observed history, not just the last month.
/// Honest framing: "since install" (since the app first started recording), never "lifetime".
public struct CumulativeChargeExposure: Codable, Equatable, Sendable {
    public var firstDay: String?           // earliest counted "yyyy-MM-dd"
    public var lastCountedDay: String?     // newest counted "yyyy-MM-dd" (high-water mark)
    public var secondsAbove80OnAC: Double
    public var secondsAbove95OnAC: Double

    public init(
        firstDay: String? = nil,
        lastCountedDay: String? = nil,
        secondsAbove80OnAC: Double = 0,
        secondsAbove95OnAC: Double = 0
    ) {
        self.firstDay = firstDay
        self.lastCountedDay = lastCountedDay
        self.secondsAbove80OnAC = secondsAbove80OnAC
        self.secondsAbove95OnAC = secondsAbove95OnAC
    }

    /// Folds in ONLY days that are (a) strictly before `today` (today is still in progress) AND
    /// (b) newer than `lastCountedDay` (not already counted). Idempotent and monotonic: re-running
    /// with the same data changes nothing, totals never decrease, and a day pruned from `days`
    /// after being counted stays counted. Day-strings sort chronologically, so string compares
    /// give chronological order. Returns the updated cumulative (pure).
    public func accumulating(days: [DailyChargeExposure], today: String) -> CumulativeChargeExposure {
        var result = self
        for day in days.sorted(by: { $0.day < $1.day }) {
            guard day.day < today else { continue }                 // exclude today + future
            if let last = result.lastCountedDay, day.day <= last { continue } // already counted
            result.secondsAbove80OnAC += day.secondsAbove80OnAC
            result.secondsAbove95OnAC += day.secondsAbove95OnAC
            result.firstDay = result.firstDay.map { min($0, day.day) } ?? day.day
            result.lastCountedDay = result.lastCountedDay.map { max($0, day.day) } ?? day.day
        }
        return result
    }
}

public struct ChargeExposureRecord: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var days: [DailyChargeExposure]
    public var cumulative: CumulativeChargeExposure

    public init(
        schemaVersion: Int = 2,
        days: [DailyChargeExposure] = [],
        cumulative: CumulativeChargeExposure = CumulativeChargeExposure()
    ) {
        self.schemaVersion = schemaVersion
        self.days = days
        self.cumulative = cumulative
    }

    // Custom decode so pre-cumulative (v1) JSON without the `cumulative` key still loads, with an
    // empty cumulative. Forward-compatible migration: existing records aren't broken.
    private enum CodingKeys: String, CodingKey { case schemaVersion, days, cumulative }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        self.days = try c.decode([DailyChargeExposure].self, forKey: .days)
        self.cumulative = try c.decodeIfPresent(CumulativeChargeExposure.self, forKey: .cumulative)
            ?? CumulativeChargeExposure()
    }

    /// Keeps the newest `limit` day-entries ("yyyy-MM-dd" sorts chronologically). Cumulative is
    /// preserved across the prune — that's the whole point of having it.
    public func pruned(toDays limit: Int = 30) -> ChargeExposureRecord {
        let sorted = days.sorted { $0.day < $1.day }
        return ChargeExposureRecord(
            schemaVersion: schemaVersion,
            days: Array(sorted.suffix(max(0, limit))),
            cumulative: cumulative
        )
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
