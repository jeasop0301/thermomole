import XCTest
@testable import ThermoMoleCore

final class BatteryHealthLogTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func day(_ d: Int) -> Date {
        cal.date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 6, day: d, hour: 12))!
    }

    func testRecordStoresOneEntry() {
        var log = BatteryHealthLog()
        log.record(healthPercent: 92, cycleCount: 120, maxCapacityMAh: 4500, designCapacityMAh: 4900, at: day(16), calendar: cal)
        XCTAssertEqual(log.all().count, 1)
        XCTAssertEqual(log.latest?.healthPercent, 92)
    }

    func testSameDayUpsertsLatestWins() {
        var log = BatteryHealthLog()
        log.record(healthPercent: 92, cycleCount: 120, maxCapacityMAh: 4500, designCapacityMAh: 4900, at: day(16), calendar: cal)
        log.record(healthPercent: 91, cycleCount: 121, maxCapacityMAh: 4490, designCapacityMAh: 4900, at: day(16).addingTimeInterval(3600), calendar: cal)
        XCTAssertEqual(log.all().count, 1)
        XCTAssertEqual(log.latest?.healthPercent, 91)
        XCTAssertEqual(log.latest?.cycleCount, 121)
    }

    func testMultiDayOrderedChronologically() {
        var log = BatteryHealthLog()
        log.record(healthPercent: 95, cycleCount: 100, maxCapacityMAh: 4600, designCapacityMAh: 4900, at: day(18), calendar: cal)
        log.record(healthPercent: 96, cycleCount: 98, maxCapacityMAh: 4620, designCapacityMAh: 4900, at: day(16), calendar: cal)
        let all = log.all()
        XCTAssertEqual(all.map(\.day), ["2026-06-16", "2026-06-18"])
        XCTAssertEqual(log.latest?.day, "2026-06-18")
    }

    func testHealthSeriesMapsNewest() {
        var log = BatteryHealthLog()
        log.record(healthPercent: 96, cycleCount: 98, maxCapacityMAh: 4620, designCapacityMAh: 4900, at: day(16), calendar: cal)
        log.record(healthPercent: 95, cycleCount: 100, maxCapacityMAh: 4600, designCapacityMAh: 4900, at: day(17), calendar: cal)
        XCTAssertEqual(log.healthSeries(), [96, 95])
        XCTAssertEqual(log.healthSeries(maxDays: 1), [95])
    }
}
