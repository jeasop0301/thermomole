// Sources/ThermoMoleCore/HourlyHeatTracker.swift
import Foundation

public struct HourHeatCell: Codable, Equatable, Sendable {
    public var sumC: Double
    public var count: Int
    public var peakC: Double?

    public init(sumC: Double = 0, count: Int = 0, peakC: Double? = nil) {
        self.sumC = sumC
        self.count = count
        self.peakC = peakC
    }

    public var meanC: Double? { count > 0 ? sumC / Double(count) : nil }
}

public struct DailyHourlyHeat: Codable, Equatable, Sendable {
    public var day: String          // "yyyy-MM-dd" in the recording calendar's timezone
    public var hours: [HourHeatCell] // always length 24, index == hour 0...23

    private enum CodingKeys: String, CodingKey { case day, hours }

    public init(day: String, hours: [HourHeatCell]? = nil) {
        self.day = day
        self.hours = DailyHourlyHeat.normalized(hours)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(String.self, forKey: .day)
        hours = DailyHourlyHeat.normalized(try c.decodeIfPresent([HourHeatCell].self, forKey: .hours))
    }

    private static func normalized(_ hours: [HourHeatCell]?) -> [HourHeatCell] {
        var h = hours ?? []
        if h.count < 24 { h.append(contentsOf: Array(repeating: HourHeatCell(), count: 24 - h.count)) }
        else if h.count > 24 { h = Array(h.prefix(24)) }
        return h
    }

    public static func empty(day: String) -> DailyHourlyHeat { .init(day: day) }
}

/// Pure per-(day, hour) battery-temperature sampler. Stores running sum/count/peak per hour
/// bucket so a mean can be derived; time/calendar inputs are injected (never reads the clock).
/// Sampling-based — no gap-cap or elapsed logic needed.
public struct HourlyHeatTracker: Equatable, Sendable {
    public private(set) var days: [String: DailyHourlyHeat]

    public init(days: [String: DailyHourlyHeat] = [:]) { self.days = days }

    public static func dayKey(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public mutating func ingest(temperatureC: Double?, at sampledAt: Date, calendar: Calendar) {
        guard let temp = temperatureC else { return }
        let key = Self.dayKey(for: sampledAt, calendar: calendar)
        let hour = calendar.component(.hour, from: sampledAt)
        // calendar.component(.hour:) is always 0–23; defensive bound.
        guard (0..<24).contains(hour) else { return }
        var day = days[key] ?? .empty(day: key)
        var cell = day.hours[hour]
        cell.sumC += temp
        cell.count += 1
        cell.peakC = cell.peakC.map { max($0, temp) } ?? temp
        day.hours[hour] = cell
        days[key] = day
    }

    public func day(_ date: Date, calendar: Calendar) -> DailyHourlyHeat {
        let key = Self.dayKey(for: date, calendar: calendar)
        return days[key] ?? .empty(day: key)
    }

    /// Oldest → newest, `n` entries ending at `date`; missing days return empty (24 zero cells).
    // NOTE: oldest→newest (unlike ThermalExposureTracker.recentDays, which is newest-first).
    public func recentDays(_ n: Int, endingAt date: Date, calendar: Calendar) -> [DailyHourlyHeat] {
        (0..<max(0, n)).reversed().compactMap { offset in
            guard let d = calendar.date(byAdding: .day, value: -offset, to: date) else { return nil }
            let key = Self.dayKey(for: d, calendar: calendar)
            return days[key] ?? .empty(day: key)
        }
    }

    public mutating func reset() { days = [:] }
}
