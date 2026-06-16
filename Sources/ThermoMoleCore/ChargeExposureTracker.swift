import Foundation

public enum ChargeThresholds {
    public static let highPercent = 80
    public static let veryHighPercent = 95
}

public struct DailyChargeExposure: Codable, Equatable, Sendable {
    public var day: String              // "yyyy-MM-dd" in the recording calendar's timezone
    public var secondsAbove80OnAC: TimeInterval
    public var secondsAbove95OnAC: TimeInterval
    public var peakPercentOnAC: Int?

    public init(
        day: String,
        secondsAbove80OnAC: TimeInterval = 0,
        secondsAbove95OnAC: TimeInterval = 0,
        peakPercentOnAC: Int? = nil
    ) {
        self.day = day
        self.secondsAbove80OnAC = secondsAbove80OnAC
        self.secondsAbove95OnAC = secondsAbove95OnAC
        self.peakPercentOnAC = peakPercentOnAC
    }

    public static func empty(day: String) -> DailyChargeExposure { .init(day: day) }
}

public struct ChargeExposureSummary: Equatable, Sendable {
    public var today: DailyChargeExposure
    public var recent: [DailyChargeExposure]

    public init(today: DailyChargeExposure, recent: [DailyChargeExposure]) {
        self.today = today
        self.recent = recent
    }

    public static let empty = ChargeExposureSummary(today: .empty(day: ""), recent: [])
}

/// Pure, deterministic per-day high-state-of-charge dwell accumulator.
/// Credits elapsed time only while the battery is on AC power and held at a high charge,
/// because that is the actionable aging factor ("plugged in and left full"). All time/
/// calendar inputs are injected — it never reads the wall clock — so every edge case
/// (clock-backwards, sleep gaps, midnight) is unit-testable. Mirrors ThermalExposureTracker.
public struct ChargeExposureTracker: Equatable, Sendable {
    /// Ceiling on credited seconds per interval (3× the 2 s sample cadence). A larger gap
    /// (sleep/suspension) credits only this much, not the whole gap.
    public static let gapCapSeconds: TimeInterval = 6.0

    public private(set) var days: [String: DailyChargeExposure]
    private var lastSampleAt: Date?      // session-only; not persisted
    private var lastPercent: Int?
    private var lastOnAC: Bool = false

    public init(days: [String: DailyChargeExposure] = [:]) {
        self.days = days
    }

    public static func dayKey(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public mutating func ingest(percent: Int, isOnACPower: Bool, at sampledAt: Date, calendar: Calendar) {
        defer {
            lastSampleAt = sampledAt
            lastPercent = percent
            lastOnAC = isOnACPower
        }

        updatePeak(percent: percent, isOnACPower: isOnACPower, at: sampledAt, calendar: calendar)

        guard let prev = lastSampleAt else { return }      // first sample: no interval
        let rawElapsed = sampledAt.timeIntervalSince(prev)
        guard rawElapsed > 0 else { return }                // clock backward / duplicate
        let elapsed = min(rawElapsed, Self.gapCapSeconds)
        let band = Self.band(percent: lastPercent, isOnAC: lastOnAC)
        guard band != .none else { return }
        distribute(duration: elapsed, from: prev, band: band, calendar: calendar)
    }

    public func today(at date: Date, calendar: Calendar) -> DailyChargeExposure {
        let key = Self.dayKey(for: date, calendar: calendar)
        return days[key] ?? .empty(day: key)
    }

    public func recentDays(_ n: Int, endingAt date: Date, calendar: Calendar) -> [DailyChargeExposure] {
        (0..<max(0, n)).compactMap { offset in
            guard let d = calendar.date(byAdding: .day, value: -offset, to: date) else { return nil }
            let key = Self.dayKey(for: d, calendar: calendar)
            return days[key] ?? .empty(day: key)
        }
    }

    public mutating func reset() {
        days = [:]
        lastSampleAt = nil
        lastPercent = nil
        lastOnAC = false
    }

    // MARK: - Private

    private enum Band { case none, high, veryHigh }

    private static func band(percent: Int?, isOnAC: Bool) -> Band {
        guard isOnAC, let percent else { return .none }
        if percent >= ChargeThresholds.veryHighPercent { return .veryHigh }
        if percent >= ChargeThresholds.highPercent { return .high }
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
        day.secondsAbove80OnAC += seconds
        if band == .veryHigh { day.secondsAbove95OnAC += seconds }
        days[key] = day
    }

    private mutating func updatePeak(percent: Int, isOnACPower: Bool, at date: Date, calendar: Calendar) {
        guard isOnACPower else { return }
        let key = Self.dayKey(for: date, calendar: calendar)
        var day = days[key] ?? .empty(day: key)
        day.peakPercentOnAC = day.peakPercentOnAC.map { max($0, percent) } ?? percent
        days[key] = day
    }
}
