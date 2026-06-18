// Sources/ThermoMoleCore/HealthProjection.swift
import Foundation

/// Projects battery health forward as a scenario band: a central least-squares trend bounded by
/// the slower/faster of (lifetime rate, recent 28-day rate). Honest about uncertainty and silent
/// (flat/insufficient) when the data can't support a projection.
public struct HealthProjectionResult: Equatable, Sendable {
    public enum Status: String, Sendable, Equatable { case insufficient, flat, projecting }

    public struct Point: Equatable, Sendable {
        public var monthOffset: Int
        public var low: Double      // faster fade (lower health)
        public var central: Double
        public var high: Double     // slower fade (higher health)
        public init(monthOffset: Int, low: Double, central: Double, high: Double) {
            self.monthOffset = monthOffset; self.low = low; self.central = central; self.high = high
        }
    }

    public struct MonthsRange: Equatable, Sendable {
        public var min: Double
        public var max: Double
        public init(min: Double, max: Double) { self.min = min; self.max = max }
    }

    public var status: Status
    public var points: [Point]
    public var monthsTo80Range: MonthsRange?
    public var recentRatePerWeek: Double    // %/week drop
    public var lifetimeRatePerWeek: Double
    public var currentHealthPercent: Int

    public init(status: Status, points: [Point], monthsTo80Range: MonthsRange?, recentRatePerWeek: Double, lifetimeRatePerWeek: Double, currentHealthPercent: Int) {
        self.status = status
        self.points = points
        self.monthsTo80Range = monthsTo80Range
        self.recentRatePerWeek = recentRatePerWeek
        self.lifetimeRatePerWeek = lifetimeRatePerWeek
        self.currentHealthPercent = currentHealthPercent
    }

    public static let empty = HealthProjectionResult(status: .insufficient, points: [], monthsTo80Range: nil, recentRatePerWeek: 0, lifetimeRatePerWeek: 0, currentHealthPercent: 0)
}

public enum HealthProjection {
    private static let daysPerMonth = 30.44
    private static let maxMonths = 18
    private static let minSpanDays = 14.0
    private static let flatThresholdPerWeek = 0.1
    private static let recentWindowDays = 28.0
    private static let minRecentSpanDays = 3.0
    private static let nearZeroRate = 0.01

    public static func evaluate(_ history: [DailyBatteryHealth], calendar: Calendar = .current) -> HealthProjectionResult {
        let sorted = history.sorted { $0.day < $1.day }
        guard let earliest = sorted.first, let latest = sorted.last,
              let d0 = date(from: earliest.day, calendar: calendar),
              let d1 = date(from: latest.day, calendar: calendar) else { return .empty }

        let spanDays = d1.timeIntervalSince(d0) / 86_400.0
        let current = latest.healthPercent
        guard spanDays >= minSpanDays else {
            return HealthProjectionResult(status: .insufficient, points: [], monthsTo80Range: nil, recentRatePerWeek: 0, lifetimeRatePerWeek: 0, currentHealthPercent: current)
        }

        let lifetimeRate = Double(earliest.healthPercent - latest.healthPercent) / spanDays * 7.0

        var recentRate = lifetimeRate
        let recentCutoff = d1.addingTimeInterval(-recentWindowDays * 86_400)
        if let r0 = sorted.first(where: { (date(from: $0.day, calendar: calendar) ?? d0) >= recentCutoff }),
           let rd0 = date(from: r0.day, calendar: calendar) {
            let rspan = d1.timeIntervalSince(rd0) / 86_400.0
            if rspan >= minRecentSpanDays { recentRate = Double(r0.healthPercent - latest.healthPercent) / rspan * 7.0 }
        }

        let centralRate = regressionDropPerWeek(sorted, anchor: d0, calendar: calendar) ?? lifetimeRate
        let maxRate = max(lifetimeRate, recentRate, centralRate)
        let minRate = min(lifetimeRate, recentRate, centralRate)

        guard maxRate > flatThresholdPerWeek else {
            return HealthProjectionResult(status: .flat, points: [], monthsTo80Range: nil, recentRatePerWeek: recentRate, lifetimeRatePerWeek: lifetimeRate, currentHealthPercent: current)
        }

        // Health is never projected to rise above current: floor every scenario rate at 0,
        // so the slowest-fade edge is at best flat (honest — no upward projection).
        let effMax = max(0, maxRate)
        let effMin = max(0, minRate)
        let effCentral = max(0, centralRate)

        let weeksPerMonth = daysPerMonth / 7.0
        var points: [HealthProjectionResult.Point] = []
        for m in 0...maxMonths {
            let weeks = Double(m) * weeksPerMonth
            let fast = Double(current) - effMax * weeks
            let slow = Double(current) - effMin * weeks
            let cen  = Double(current) - effCentral * weeks
            let low = clampPct(min(fast, slow, cen))
            let high = clampPct(max(fast, slow, cen))
            let central = clampPct(min(max(cen, low), high))
            points.append(.init(monthOffset: m, low: low, central: central, high: high))
            if slow <= 80 { break }
        }

        var range: HealthProjectionResult.MonthsRange?
        if current > 80 {
            let monthsPerWeekUnit = 7.0 / daysPerMonth
            let toFast = effMax > nearZeroRate ? Double(current - 80) / effMax * monthsPerWeekUnit : Double(maxMonths)
            let toSlow = effMin > nearZeroRate ? Double(current - 80) / effMin * monthsPerWeekUnit : Double(maxMonths)
            range = .init(min: max(0, toFast), max: max(toFast, Swift.min(toSlow, Double(maxMonths))))
        }

        return HealthProjectionResult(status: .projecting, points: points, monthsTo80Range: range, recentRatePerWeek: recentRate, lifetimeRatePerWeek: lifetimeRate, currentHealthPercent: current)
    }

    private static func clampPct(_ v: Double) -> Double { max(0, min(100, v)) }

    /// Least-squares slope of healthPercent over days; returned as a positive %/week drop (nil if degenerate).
    private static func regressionDropPerWeek(_ points: [DailyBatteryHealth], anchor: Date, calendar: Calendar) -> Double? {
        let xy: [(x: Double, y: Double)] = points.compactMap { p in
            guard let d = date(from: p.day, calendar: calendar) else { return nil }
            return (x: d.timeIntervalSince(anchor) / 86_400.0, y: Double(p.healthPercent))
        }
        guard xy.count >= 2 else { return nil }
        let n = Double(xy.count)
        let sx = xy.reduce(0) { $0 + $1.x }, sy = xy.reduce(0) { $0 + $1.y }
        let sxx = xy.reduce(0) { $0 + $1.x * $1.x }, sxy = xy.reduce(0) { $0 + $1.x * $1.y }
        let denom = n * sxx - sx * sx
        guard abs(denom) > 1e-9 else { return nil }
        let slopePerDay = (n * sxy - sx * sy) / denom   // health-% per day (negative when declining)
        return -slopePerDay * 7.0                        // positive %/week drop
    }

    private static func date(from day: String, calendar: Calendar) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
