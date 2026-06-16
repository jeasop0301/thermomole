import Foundation

public struct DailyThermalExposure: Codable, Equatable, Sendable {
    public var day: String              // "yyyy-MM-dd" in the recording calendar's timezone
    public var secondsAbove35: TimeInterval
    public var secondsAbove40: TimeInterval
    public var peakC: Double?

    public init(
        day: String,
        secondsAbove35: TimeInterval = 0,
        secondsAbove40: TimeInterval = 0,
        peakC: Double? = nil
    ) {
        self.day = day
        self.secondsAbove35 = secondsAbove35
        self.secondsAbove40 = secondsAbove40
        self.peakC = peakC
    }

    public static func empty(day: String) -> DailyThermalExposure { .init(day: day) }
}

public struct ThermalExposureSummary: Equatable, Sendable {
    public var today: DailyThermalExposure
    public var recent: [DailyThermalExposure]

    public init(today: DailyThermalExposure, recent: [DailyThermalExposure]) {
        self.today = today
        self.recent = recent
    }

    public static let empty = ThermalExposureSummary(today: .empty(day: ""), recent: [])
}

/// Pure, deterministic per-day battery thermal-exposure accumulator.
/// All time/calendar inputs are injected — it never reads the wall clock — so every
/// edge case (clock-backwards, sleep gaps, midnight, DST) is unit-testable.
public struct ThermalExposureTracker: Equatable, Sendable {
    /// Ceiling on credited seconds per interval (3× the 2 s sample cadence). A gap larger
    /// than this (sleep/suspension/stall) credits only this much, not the whole gap.
    public static let gapCapSeconds: TimeInterval = 6.0

    public private(set) var days: [String: DailyThermalExposure]
    private var lastSampleAt: Date?      // session-only; not persisted
    private var lastTemperatureC: Double?

    public init(days: [String: DailyThermalExposure] = [:]) {
        self.days = days
    }

    public static func dayKey(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public mutating func ingest(temperatureC: Double?, at sampledAt: Date, calendar: Calendar) {
        defer {
            lastSampleAt = sampledAt
            lastTemperatureC = temperatureC
        }

        updatePeak(temperatureC, at: sampledAt, calendar: calendar)

        guard let prev = lastSampleAt else { return }      // first sample: no interval
        let rawElapsed = sampledAt.timeIntervalSince(prev)
        guard rawElapsed > 0 else { return }  // clock backward / duplicate: skip credit; defer still updates anchor to sampledAt
        let elapsed = min(rawElapsed, Self.gapCapSeconds)
        let band = Self.band(for: lastTemperatureC)
        guard band != .none else { return }
        distribute(duration: elapsed, from: prev, band: band, calendar: calendar)
    }

    public func today(at date: Date, calendar: Calendar) -> DailyThermalExposure {
        let key = Self.dayKey(for: date, calendar: calendar)
        return days[key] ?? .empty(day: key)
    }

    public func recentDays(_ n: Int, endingAt date: Date, calendar: Calendar) -> [DailyThermalExposure] {
        (0..<max(0, n)).compactMap { offset in
            guard let d = calendar.date(byAdding: .day, value: -offset, to: date) else { return nil }
            let key = Self.dayKey(for: d, calendar: calendar)
            return days[key] ?? .empty(day: key)
        }
    }

    public mutating func reset() {
        days = [:]
        lastSampleAt = nil
        lastTemperatureC = nil
    }

    // MARK: - Private

    private enum Band { case none, caution, hot }

    private static func band(for temp: Double?) -> Band {
        guard let temp else { return .none }
        if temp >= ThermalThresholds.batteryHotC { return .hot }
        if temp >= ThermalThresholds.batteryCautionC { return .caution }
        return .none
    }

    private mutating func distribute(duration: TimeInterval, from start: Date, band: Band, calendar: Calendar) {
        var cursor = start
        var remaining = duration
        while remaining > 0 {
            let key = Self.dayKey(for: cursor, calendar: calendar)
            let nextMidnight = calendar.nextDate(
                after: cursor,
                matching: DateComponents(hour: 0, minute: 0, second: 0),
                matchingPolicy: .nextTime
            ) ?? cursor.addingTimeInterval(remaining)
            let untilBoundary = nextMidnight.timeIntervalSince(cursor)
            let chunk = min(remaining, untilBoundary)
            guard chunk > 0 else { break }
            credit(chunk, toDay: key, band: band)
            cursor = cursor.addingTimeInterval(chunk)
            remaining -= chunk
        }
    }

    private mutating func credit(_ seconds: TimeInterval, toDay key: String, band: Band) {
        var day = days[key] ?? .empty(day: key)
        day.secondsAbove35 += seconds
        if band == .hot { day.secondsAbove40 += seconds }
        days[key] = day
    }

    private mutating func updatePeak(_ temp: Double?, at date: Date, calendar: Calendar) {
        guard let temp else { return }
        let key = Self.dayKey(for: date, calendar: calendar)
        var day = days[key] ?? .empty(day: key)
        day.peakC = day.peakC.map { max($0, temp) } ?? temp
        days[key] = day
    }
}
