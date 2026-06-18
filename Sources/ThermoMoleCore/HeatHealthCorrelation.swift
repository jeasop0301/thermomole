// Sources/ThermoMoleCore/HeatHealthCorrelation.swift
import Foundation

/// Observational (not causal) link between daily battery thermal exposure and the rate of
/// battery-health fade. Classifies each consecutive health-record interval as warm/cool by the
/// thermal exposure on its start day, then compares mean %/week drop. Gated to avoid false signal.
public struct HeatHealthInsight: Equatable, Sendable {
    public enum Verdict: String, Sendable, Equatable {
        case insufficientData
        case warmFadesFaster
        case noClearDifference
    }

    public var verdict: Verdict
    public var warmFadePerWeek: Double?   // %/week drop magnitude (avg over warm intervals)
    public var coolFadePerWeek: Double?
    public var warmDays: Int   // count of consecutive health intervals classified warm (NOT calendar days; ≈ days when records are daily)
    public var coolDays: Int   // count of consecutive health intervals classified cool (NOT calendar days; ≈ days when records are daily)

    public init(verdict: Verdict, warmFadePerWeek: Double?, coolFadePerWeek: Double?, warmDays: Int, coolDays: Int) {
        self.verdict = verdict
        self.warmFadePerWeek = warmFadePerWeek
        self.coolFadePerWeek = coolFadePerWeek
        self.warmDays = warmDays
        self.coolDays = coolDays
    }

    public static let empty = HeatHealthInsight(verdict: .insufficientData, warmFadePerWeek: nil, coolFadePerWeek: nil, warmDays: 0, coolDays: 0)
}

public enum HeatHealthCorrelation {
    public static func evaluate(
        thermal: [DailyThermalExposure],
        health: [DailyBatteryHealth],
        calendar: Calendar = .current
    ) -> HeatHealthInsight {
        let thermalByDay = Dictionary(thermal.map { ($0.day, $0) }, uniquingKeysWith: { _, b in b })
        let sorted = health.sorted { $0.day < $1.day }
        guard sorted.count >= 2 else { return .empty }

        var warmFades: [Double] = []
        var coolFades: [Double] = []
        var totalDrop = 0

        for i in 1..<sorted.count {
            let prev = sorted[i - 1], cur = sorted[i]
            guard let d0 = date(from: prev.day, calendar: calendar),
                  let d1 = date(from: cur.day, calendar: calendar) else { continue }
            let gapDays = d1.timeIntervalSince(d0) / 86_400.0
            guard gapDays >= 1 else { continue }
            guard let t = thermalByDay[prev.day] else { continue }  // need thermal for the start day

            let drop = max(0, prev.healthPercent - cur.healthPercent)   // clamp recovery/recalibration to 0
            let dropPerWeek = Double(drop) / gapDays * 7.0
            totalDrop += drop
            let isWarm = (t.peakC ?? 0) >= ThermalThresholds.batteryCautionC || t.secondsAbove35 > 0
            if isWarm { warmFades.append(dropPerWeek) } else { coolFades.append(dropPerWeek) }
        }

        let warmDays = warmFades.count, coolDays = coolFades.count
        guard warmDays >= 3, coolDays >= 3, totalDrop >= 1 else {
            return HeatHealthInsight(verdict: .insufficientData, warmFadePerWeek: nil, coolFadePerWeek: nil, warmDays: warmDays, coolDays: coolDays)
        }

        let warmAvg = warmFades.reduce(0, +) / Double(warmDays)
        let coolAvg = coolFades.reduce(0, +) / Double(coolDays)
        let verdict: HeatHealthInsight.Verdict = (warmAvg - coolAvg >= warmFasterThresholdPerWeek) ? .warmFadesFaster : .noClearDifference
        return HeatHealthInsight(verdict: verdict, warmFadePerWeek: warmAvg, coolFadePerWeek: coolAvg, warmDays: warmDays, coolDays: coolDays)
    }

    // Conservative gap vs. normal aging (~0.04–0.08%/week) below which we report no clear difference.
    private static let warmFasterThresholdPerWeek = 0.3

    private static func date(from day: String, calendar: Calendar) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
