import XCTest
@testable import ThermoMoleCore

final class BatteryLongevityTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func rec(_ day: String, health: Int, cycles: Int) -> DailyBatteryHealth {
        DailyBatteryHealth(day: day, healthPercent: health, cycleCount: cycles, maxCapacityMAh: 4500, designCapacityMAh: 4900)
    }

    func testEmptyHistoryReturnsNil() {
        XCTAssertNil(BatteryLongevity.evaluate(history: [], calendar: cal))
    }

    func testNewBatteryScoresVeryHigh() {
        let history = (1...10).map { rec(String(format: "2026-06-%02d", $0), health: 100, cycles: 5) }
        let r = BatteryLongevity.evaluate(history: history, calendar: cal)!
        XCTAssertGreaterThanOrEqual(r.score, 95)
        XCTAssertEqual(r.healthPercent, 100)
        XCTAssertTrue(r.alerts.isEmpty)
        XCTAssertNil(r.projectedMonthsTo80) // not declining
    }

    func testSlowDeclineProjectsAndScoresLowerThanNew() {
        let history = [rec("2026-06-01", health: 95, cycles: 200), rec("2026-06-11", health: 90, cycles: 210)]
        let r = BatteryLongevity.evaluate(history: history, calendar: cal)!
        XCTAssertNotNil(r.healthDropPerWeek)
        XCTAssertNotNil(r.projectedMonthsTo80)
        XCTAssertFalse(r.alerts.contains(.fastFade)) // 3.5%/wk < 5
        XCTAssertLessThan(r.score, 95)
    }

    func testFastFadeRaisesAlert() {
        let history = [rec("2026-06-01", health: 95, cycles: 300), rec("2026-06-04", health: 85, cycles: 305)]
        let r = BatteryLongevity.evaluate(history: history, calendar: cal)!
        XCTAssertTrue(r.alerts.contains(.fastFade)) // ~23%/wk
    }

    func testLowHealthThresholdAlerts() {
        let r80 = BatteryLongevity.evaluate(history: [rec("2026-06-01", health: 78, cycles: 600)], calendar: cal)!
        XCTAssertTrue(r80.alerts.contains(.healthBelow80))
        XCTAssertFalse(r80.alerts.contains(.healthBelow60))

        let r60 = BatteryLongevity.evaluate(history: [rec("2026-06-01", health: 55, cycles: 900)], calendar: cal)!
        XCTAssertTrue(r60.alerts.contains(.healthBelow60))
    }

    func testHighCycleRateAlert() {
        let history = [rec("2026-06-01", health: 92, cycles: 100), rec("2026-06-08", health: 92, cycles: 130)]
        let r = BatteryLongevity.evaluate(history: history, calendar: cal)!
        XCTAssertTrue(r.alerts.contains(.highCycleRate)) // 30 cycles/week
    }

    func testInsufficientSpanLeavesRatesNil() {
        let history = [rec("2026-06-01", health: 90, cycles: 100), rec("2026-06-02", health: 90, cycles: 100)]
        let r = BatteryLongevity.evaluate(history: history, calendar: cal)!
        XCTAssertNil(r.healthDropPerWeek)
        XCTAssertNil(r.cyclesPerWeek)
        XCTAssertEqual(r.healthPercent, 90)
    }
}
