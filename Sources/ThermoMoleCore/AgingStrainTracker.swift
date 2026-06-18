import Foundation

public struct DailyAgingStrain: Codable, Equatable, Sendable {
    public var day: String              // "yyyy-MM-dd" in the recording calendar's timezone
    public var effectiveSeconds: TimeInterval
    public var calendarSeconds: TimeInterval
    public var peakMultiplier: Double

    public init(
        day: String,
        effectiveSeconds: TimeInterval = 0,
        calendarSeconds: TimeInterval = 0,
        peakMultiplier: Double = 0
    ) {
        self.day = day
        self.effectiveSeconds = effectiveSeconds
        self.calendarSeconds = calendarSeconds
        self.peakMultiplier = peakMultiplier
    }

    public static func empty(day: String) -> DailyAgingStrain { .init(day: day) }
}

/// Pure, deterministic per-day cumulative aging-strain accumulator.
/// Tracks effective aging time = sum(max(1, rawMultiplier) * dt) vs calendar time.
/// All time/calendar inputs are injected — never reads the wall clock.
public struct AgingStrainTracker: Equatable, Sendable {
    /// Ceiling on credited seconds per interval (3× the 2 s sample cadence).
    public static let gapCapSeconds: TimeInterval = 6.0

    public private(set) var days: [String: DailyAgingStrain]
    private var lastSampleAt: Date?     // session-only; not persisted

    public init(days: [String: DailyAgingStrain] = [:]) {
        self.days = days
    }

    public static func dayKey(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public mutating func ingest(rawMultiplier: Double, at date: Date, calendar: Calendar) {
        defer { lastSampleAt = date }

        guard let prev = lastSampleAt else { return }   // first sample: no interval
        let rawElapsed = date.timeIntervalSince(prev)
        guard rawElapsed > 0 else { return }            // clock backward / duplicate: skip
        let elapsed = min(rawElapsed, Self.gapCapSeconds)

        // Attribute entire interval to the END day (acceptable for ratio computation)
        let key = Self.dayKey(for: date, calendar: calendar)
        var d = days[key] ?? .empty(day: key)
        d.calendarSeconds += elapsed
        d.effectiveSeconds += max(1.0, rawMultiplier) * elapsed
        d.peakMultiplier = max(d.peakMultiplier, rawMultiplier)
        days[key] = d
    }

    public func today(at date: Date, calendar: Calendar) -> DailyAgingStrain {
        let key = Self.dayKey(for: date, calendar: calendar)
        return days[key] ?? .empty(day: key)
    }

    public func recentDays(_ n: Int, endingAt date: Date, calendar: Calendar) -> [DailyAgingStrain] {
        (0..<max(0, n)).compactMap { offset in
            guard let d = calendar.date(byAdding: .day, value: -offset, to: date) else { return nil }
            let key = Self.dayKey(for: d, calendar: calendar)
            return days[key] ?? .empty(day: key)
        }
    }

    public mutating func reset() {
        days = [:]
        lastSampleAt = nil
    }
}
