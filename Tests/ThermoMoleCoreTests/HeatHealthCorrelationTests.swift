// Tests/ThermoMoleCoreTests/HeatHealthCorrelationTests.swift
import XCTest
@testable import ThermoMoleCore

final class HeatHealthCorrelationTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    // warm: peakC 41 ≥ batteryExposureWarmC(40) → classified warm
    private func warm(_ day: String) -> DailyThermalExposure {
        DailyThermalExposure(day: day, secondsAbove40: 600, secondsAbove45: 0, peakC: 41)
    }
    private func cool(_ day: String) -> DailyThermalExposure {
        DailyThermalExposure(day: day, secondsAbove40: 0, secondsAbove45: 0, peakC: 30)
    }
    private func health(_ day: String, _ pct: Int) -> DailyBatteryHealth {
        DailyBatteryHealth(day: day, healthPercent: pct, cycleCount: 100, maxCapacityMAh: 5000, designCapacityMAh: 6000)
    }

    func testInsufficientWhenTooFewBuckets() {
        let thermal = [warm("2026-06-16"), warm("2026-06-17")]
        let h = [health("2026-06-16", 90), health("2026-06-17", 89)]
        let insight = HeatHealthCorrelation.evaluate(thermal: thermal, health: h, calendar: cal)
        XCTAssertEqual(insight.verdict, .insufficientData)
    }

    func testWarmFadesFaster() {
        // 4 warm intervals dropping fast, 4 cool intervals flat
        var thermal: [DailyThermalExposure] = []
        var h: [DailyBatteryHealth] = []
        // warm block: days 1..5, health 100->96 (drop 1/day)
        for (i, pct) in [100, 99, 98, 97, 96].enumerated() {
            let day = String(format: "2026-06-%02d", 1 + i)
            thermal.append(warm(day)); h.append(health(day, pct))
        }
        // cool block: days 10..14, health 96->95 (drop tiny)
        for (i, pct) in [96, 96, 96, 96, 95].enumerated() {
            let day = String(format: "2026-06-%02d", 10 + i)
            thermal.append(cool(day)); h.append(health(day, pct))
        }
        let insight = HeatHealthCorrelation.evaluate(thermal: thermal, health: h, calendar: cal)
        XCTAssertEqual(insight.verdict, .warmFadesFaster)
        XCTAssertGreaterThan(insight.warmFadePerWeek ?? 0, insight.coolFadePerWeek ?? 0)
        XCTAssertGreaterThanOrEqual(insight.warmDays, 3)
        XCTAssertGreaterThanOrEqual(insight.coolDays, 3)
    }

    func testHealthRecoveryDoesNotDistort() {
        // warm block contains a recovery interval (health rises +1); clamp must keep warm fade >= 0
        // and verdict must not flip abnormally.
        var thermal: [DailyThermalExposure] = []
        var h: [DailyBatteryHealth] = []
        // warm block: days 1..6, health 100,99,98,99,97,96 (one +1 recovery at idx 3)
        for (i, pct) in [100, 99, 98, 99, 97, 96].enumerated() {
            let day = String(format: "2026-06-%02d", 1 + i)
            thermal.append(warm(day)); h.append(health(day, pct))
        }
        // cool block: days 10..15, health 96..95 (drop tiny)
        for (i, pct) in [96, 96, 96, 96, 96, 95].enumerated() {
            let day = String(format: "2026-06-%02d", 10 + i)
            thermal.append(cool(day)); h.append(health(day, pct))
        }
        let insight = HeatHealthCorrelation.evaluate(thermal: thermal, health: h, calendar: cal)
        XCTAssertGreaterThanOrEqual(insight.warmFadePerWeek ?? -1, 0)
        XCTAssertEqual(insight.verdict, .warmFadesFaster)
    }

    func testNoClearDifferenceWhenSimilar() {
        var thermal: [DailyThermalExposure] = []
        var h: [DailyBatteryHealth] = []
        let pcts = [100, 99, 98, 97, 96, 95, 94, 93]
        for (i, pct) in pcts.enumerated() {
            let day = String(format: "2026-06-%02d", 1 + i)
            thermal.append(i % 2 == 0 ? warm(day) : cool(day))
            h.append(health(day, pct))
        }
        let insight = HeatHealthCorrelation.evaluate(thermal: thermal, health: h, calendar: cal)
        XCTAssertEqual(insight.verdict, .noClearDifference)
    }
}
