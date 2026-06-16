import Foundation

public struct DailyCPUExposure: Codable, Equatable, Sendable {
    public var day: String
    public var secondsAbove85: TimeInterval
    public var secondsAbove95: TimeInterval
    public var peakC: Double?

    public init(
        day: String,
        secondsAbove85: TimeInterval = 0,
        secondsAbove95: TimeInterval = 0,
        peakC: Double? = nil
    ) {
        self.day = day
        self.secondsAbove85 = secondsAbove85
        self.secondsAbove95 = secondsAbove95
        self.peakC = peakC
    }

    public static func empty(day: String) -> DailyCPUExposure { .init(day: day) }
}

public struct CPUExposureSummary: Equatable, Sendable {
    public var today: DailyCPUExposure
    public var recent: [DailyCPUExposure]

    public init(today: DailyCPUExposure, recent: [DailyCPUExposure]) {
        self.today = today
        self.recent = recent
    }

    public static let empty = CPUExposureSummary(today: .empty(day: ""), recent: [])
}

/// Pure per-day CPU/system thermal-exposure accumulator. Sustained CPU heat ages the whole
/// machine, not just the battery. Mirrors ThermalExposureTracker with cpuWarmC/cpuHotC bands.
public struct CPUExposureTracker: Equatable, Sendable {
    public static let gapCapSeconds: TimeInterval = 6.0

    public private(set) var days: [String: DailyCPUExposure]
    private var lastSampleAt: Date?
    private var lastTemperatureC: Double?

    public init(days: [String: DailyCPUExposure] = [:]) {
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

        guard let prev = lastSampleAt else { return }
        let rawElapsed = sampledAt.timeIntervalSince(prev)
        guard rawElapsed > 0 else { return }
        let elapsed = min(rawElapsed, Self.gapCapSeconds)
        let band = Self.band(for: lastTemperatureC)
        guard band != .none else { return }
        distribute(duration: elapsed, from: prev, band: band, calendar: calendar)
    }

    public func today(at date: Date, calendar: Calendar) -> DailyCPUExposure {
        let key = Self.dayKey(for: date, calendar: calendar)
        return days[key] ?? .empty(day: key)
    }

    public func recentDays(_ n: Int, endingAt date: Date, calendar: Calendar) -> [DailyCPUExposure] {
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

    private enum Band { case none, warm, hot }

    private static func band(for temp: Double?) -> Band {
        guard let temp else { return .none }
        if temp >= ThermalThresholds.cpuHotC { return .hot }
        if temp >= ThermalThresholds.cpuWarmC { return .warm }
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
        day.secondsAbove85 += seconds
        if band == .hot { day.secondsAbove95 += seconds }
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
