// Tests/ThermoMoleCoreTests/HealthProjectionTests.swift
import XCTest
@testable import ThermoMoleCore

final class HealthProjectionTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func h(_ day: String, _ pct: Int) -> DailyBatteryHealth {
        DailyBatteryHealth(day: day, healthPercent: pct, cycleCount: 100, maxCapacityMAh: 5000, designCapacityMAh: 6000)
    }

    func testInsufficientWhenSpanTooShort() {
        let r = HealthProjection.evaluate([h("2026-06-10", 95), h("2026-06-18", 94)], calendar: cal)
        XCTAssertEqual(r.status, .insufficient)
        XCTAssertTrue(r.points.isEmpty)
    }

    func testFlatWhenNoMeasurableDrop() {
        let days = (1...40).map { h(String(format: "2026-05-%02d", $0), 95) }
        let r = HealthProjection.evaluate(days, calendar: cal)
        XCTAssertEqual(r.status, .flat)
        XCTAssertNil(r.monthsTo80Range)
    }

    func testProjectingProducesOrderedBandAndRange() {
        // ~1% per ~10 days -> declining; 60 days 100 -> 94
        let days = stride(from: 0, through: 60, by: 1).map { d -> DailyBatteryHealth in
            let pct = 100 - Int(Double(d) / 10.0)
            return h(String(format: "2026-04-%02d", d + 1), max(80, pct))
        }
        let r = HealthProjection.evaluate(days, calendar: cal)
        XCTAssertEqual(r.status, .projecting)
        XCTAssertFalse(r.points.isEmpty)
        for p in r.points {
            XCTAssertLessThanOrEqual(p.low, p.central + 0.0001)
            XCTAssertLessThanOrEqual(p.central, p.high + 0.0001)
        }
        XCTAssertEqual(r.points.first?.monthOffset, 0)
        if let range = r.monthsTo80Range {
            XCTAssertLessThanOrEqual(range.min, range.max)
            XCTAssertGreaterThanOrEqual(range.min, 0)
        }
    }

    func testRisingThenFallingDoesNotProjectUpward() {
        // earliest 90 < latest 92 (lifetimeRate < 0), recent 28d dropping 95->92
        let days = [h("2026-01-01", 90), h("2026-02-01", 95), h("2026-03-01", 92)]
        let r = HealthProjection.evaluate(days, calendar: cal)
        // 어떤 시나리오도 현재 건강도 위로 상승 예측하지 않음
        for p in r.points {
            XCTAssertLessThanOrEqual(p.high, Double(r.currentHealthPercent) + 0.001)
            XCTAssertLessThanOrEqual(p.low, p.central + 0.0001)
            XCTAssertLessThanOrEqual(p.central, p.high + 0.0001)
        }
    }
}
