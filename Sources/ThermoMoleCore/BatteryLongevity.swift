import Foundation

public enum BatteryLongevityAlert: String, Codable, Equatable, Sendable {
    case fastFade          // health dropping >= 5%/week
    case healthBelow80     // capacity faded under 80%
    case healthBelow60     // capacity faded under 60%
    case highCycleRate     // >= 15 cycles/week
}

/// Derived view of battery longevity computed purely from the persisted daily health log:
/// a 0–100 score, fade/cycle rates, a projection to the 80% service threshold, and alerts.
public struct BatteryLongevityReport: Equatable, Sendable {
    public var score: Int                    // 0–100, higher is healthier
    public var healthPercent: Int
    public var cycleCount: Int
    public var healthDropPerWeek: Double?     // % per week (positive = declining); nil if too little history
    public var cyclesPerWeek: Double?
    public var projectedMonthsTo80: Double?   // nil if already <=80% or not declining
    /// Estimated capacity loss/yr from cycle throughput (measured cycles × published per-EFC
    /// loss). A range, not a point value; nil when cyclesPerWeek is nil. Heat is NOT included
    /// here (that's the calendar term) — these are shown separately, never fused.
    public var cycleWearPctPerYearLow: Double?
    public var cycleWearPctPerYearHigh: Double?
    public var alerts: [BatteryLongevityAlert]

    public init(
        score: Int,
        healthPercent: Int,
        cycleCount: Int,
        healthDropPerWeek: Double?,
        cyclesPerWeek: Double?,
        projectedMonthsTo80: Double?,
        cycleWearPctPerYearLow: Double? = nil,
        cycleWearPctPerYearHigh: Double? = nil,
        alerts: [BatteryLongevityAlert]
    ) {
        self.score = score
        self.healthPercent = healthPercent
        self.cycleCount = cycleCount
        self.healthDropPerWeek = healthDropPerWeek
        self.cyclesPerWeek = cyclesPerWeek
        self.projectedMonthsTo80 = projectedMonthsTo80
        self.cycleWearPctPerYearLow = cycleWearPctPerYearLow
        self.cycleWearPctPerYearHigh = cycleWearPctPerYearHigh
        self.alerts = alerts
    }
}

public enum BatteryLongevity {
    /// Capacity loss per equivalent full cycle (EFC), in percent. Anchored to Apple's design
    /// spec (recent Macs ~80% at 1000 cycles ⇒ ~0.02%/cycle); ceiling ~0.06%/cycle from
    /// deep-cycle lab data (Battery University BU-808). CycleCount already counts EFCs.
    public static let capacityLossPerEFCLowPct = 0.02
    public static let capacityLossPerEFCCentralPct = 0.03   // real-world mid (used for calibration subtraction)
    public static let capacityLossPerEFCHighPct = 0.06

    /// Pure evaluation over a (chronological or unordered) daily health history.
    public static func evaluate(history: [DailyBatteryHealth], calendar: Calendar = .current) -> BatteryLongevityReport? {
        let sorted = history.sorted { $0.day < $1.day }
        guard let earliest = sorted.first, let latest = sorted.last else { return nil }

        var healthDropPerWeek: Double?
        var cyclesPerWeek: Double?
        if let d0 = date(from: earliest.day, calendar: calendar),
           let d1 = date(from: latest.day, calendar: calendar) {
            let daySpan = d1.timeIntervalSince(d0) / 86_400.0
            if daySpan >= 3 {
                healthDropPerWeek = Double(earliest.healthPercent - latest.healthPercent) / daySpan * 7.0
                // Negative delta = battery service / SMC reset / firmware re-estimation —
                // don't fabricate a rate from it.
                let cycleDelta = latest.cycleCount - earliest.cycleCount
                if cycleDelta >= 0 {
                    cyclesPerWeek = Double(cycleDelta) / daySpan * 7.0
                }
            }
        }

        var cycleWearPctPerYearLow: Double?
        var cycleWearPctPerYearHigh: Double?
        if let cw = cyclesPerWeek {
            cycleWearPctPerYearLow = cw * 52.0 * capacityLossPerEFCLowPct
            cycleWearPctPerYearHigh = cw * 52.0 * capacityLossPerEFCHighPct
        }

        var projectedMonthsTo80: Double?
        if latest.healthPercent > 80, let drop = healthDropPerWeek, drop > 0.1 {
            let weeks = Double(latest.healthPercent - 80) / drop
            projectedMonthsTo80 = weeks / 4.345
        }

        let cyclePenalty = min(15.0, Double(latest.cycleCount) / 1000.0 * 15.0)
        let fadePenalty = max(0, healthDropPerWeek ?? 0) > 0 ? min(15.0, max(0, healthDropPerWeek ?? 0) * 2.0) : 0
        let score = Int(max(0, min(100, (Double(latest.healthPercent) - cyclePenalty - fadePenalty).rounded())))

        var alerts: [BatteryLongevityAlert] = []
        if let drop = healthDropPerWeek, drop >= 5 { alerts.append(.fastFade) }
        if latest.healthPercent < 60 {
            alerts.append(.healthBelow60)
        } else if latest.healthPercent < 80 {
            alerts.append(.healthBelow80)
        }
        if let cw = cyclesPerWeek, cw >= 15 { alerts.append(.highCycleRate) }

        return BatteryLongevityReport(
            score: score,
            healthPercent: latest.healthPercent,
            cycleCount: latest.cycleCount,
            healthDropPerWeek: healthDropPerWeek,
            cyclesPerWeek: cyclesPerWeek,
            projectedMonthsTo80: projectedMonthsTo80,
            cycleWearPctPerYearLow: cycleWearPctPerYearLow,
            cycleWearPctPerYearHigh: cycleWearPctPerYearHigh,
            alerts: alerts
        )
    }

    private static func date(from day: String, calendar: Calendar) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
