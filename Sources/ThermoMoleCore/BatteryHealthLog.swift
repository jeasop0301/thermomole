import Foundation

public struct DailyBatteryHealth: Codable, Equatable, Sendable {
    public var day: String              // "yyyy-MM-dd"
    public var healthPercent: Int
    public var cycleCount: Int
    public var maxCapacityMAh: Int
    public var designCapacityMAh: Int

    public init(day: String, healthPercent: Int, cycleCount: Int, maxCapacityMAh: Int, designCapacityMAh: Int) {
        self.day = day
        self.healthPercent = healthPercent
        self.cycleCount = cycleCount
        self.maxCapacityMAh = maxCapacityMAh
        self.designCapacityMAh = designCapacityMAh
    }
}

/// Pure daily log of battery-health readings: one record per calendar day (latest reading
/// of the day wins). Used to surface a degradation trend. Time/calendar inputs injected.
public struct BatteryHealthLog: Equatable, Sendable {
    public private(set) var days: [String: DailyBatteryHealth]

    public init(days: [String: DailyBatteryHealth] = [:]) {
        self.days = days
    }

    public static func dayKey(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public mutating func record(
        healthPercent: Int,
        cycleCount: Int,
        maxCapacityMAh: Int,
        designCapacityMAh: Int,
        at date: Date,
        calendar: Calendar
    ) {
        let key = Self.dayKey(for: date, calendar: calendar)
        days[key] = DailyBatteryHealth(
            day: key,
            healthPercent: healthPercent,
            cycleCount: cycleCount,
            maxCapacityMAh: maxCapacityMAh,
            designCapacityMAh: designCapacityMAh
        )
    }

    /// All recorded days, oldest first.
    public func all() -> [DailyBatteryHealth] {
        days.values.sorted { $0.day < $1.day }
    }

    public var latest: DailyBatteryHealth? { all().last }

    /// Health-% series (oldest first), capped to the newest `maxDays` recorded days.
    public func healthSeries(maxDays: Int = 60) -> [Double] {
        all().suffix(max(0, maxDays)).map { Double($0.healthPercent) }
    }

    public mutating func reset() { days = [:] }
}
