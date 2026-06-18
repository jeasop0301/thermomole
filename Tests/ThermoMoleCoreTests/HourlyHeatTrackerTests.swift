// Tests/ThermoMoleCoreTests/HourlyHeatTrackerTests.swift
import XCTest
@testable import ThermoMoleCore

final class HourlyHeatTrackerTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    // 2023-11-14T22:13:20Z  (hour 22 in UTC)
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ offset: TimeInterval) -> Date { t0.addingTimeInterval(offset) }

    func testIngestAccumulatesIntoDayHourCell() {
        var t = HourlyHeatTracker()
        t.ingest(temperatureC: 30, at: t0, calendar: cal)
        t.ingest(temperatureC: 40, at: at(2), calendar: cal) // same hour 22
        let day = t.day(t0, calendar: cal)
        XCTAssertEqual(day.hours[22].count, 2)
        XCTAssertEqual(day.hours[22].sumC, 70, accuracy: 0.0001)
        XCTAssertEqual(day.hours[22].peakC, 40)
        XCTAssertEqual(day.hours[22].meanC ?? 0, 35, accuracy: 0.0001)
    }

    func testNilTemperatureIgnored() {
        var t = HourlyHeatTracker()
        t.ingest(temperatureC: nil, at: t0, calendar: cal)
        XCTAssertEqual(t.day(t0, calendar: cal).hours[22].count, 0)
    }

    func testSeparateHoursAndDays() {
        var t = HourlyHeatTracker()
        t.ingest(temperatureC: 33, at: t0, calendar: cal)            // day A hour 22
        t.ingest(temperatureC: 37, at: at(2 * 3600), calendar: cal)  // next day hour 00
        let dayA = t.day(t0, calendar: cal)
        let dayB = t.day(at(2 * 3600), calendar: cal)
        XCTAssertEqual(dayA.hours[22].count, 1)
        XCTAssertEqual(dayB.hours[0].count, 1)
        XCTAssertNotEqual(dayA.day, dayB.day)
    }

    func testRecentDaysOldestToNewestAndLength() {
        var t = HourlyHeatTracker()
        t.ingest(temperatureC: 36, at: t0, calendar: cal)
        let recent = t.recentDays(3, endingAt: t0, calendar: cal)
        XCTAssertEqual(recent.count, 3)
        XCTAssertEqual(recent.last?.day, HourlyHeatTracker.dayKey(for: t0, calendar: cal))
        XCTAssertEqual(recent.first?.hours.count, 24) // empty day normalized to 24
    }

    func testResetClears() {
        var t = HourlyHeatTracker()
        t.ingest(temperatureC: 36, at: t0, calendar: cal)
        t.reset()
        XCTAssertEqual(t.day(t0, calendar: cal).hours[22].count, 0)
    }

    func testPeakDoesNotDecrease() {
        var t = HourlyHeatTracker()
        t.ingest(temperatureC: 40, at: t0, calendar: cal)       // hour 22
        t.ingest(temperatureC: 30, at: at(2), calendar: cal)    // same hour 22, lower temp
        let cell = t.day(t0, calendar: cal).hours[22]
        XCTAssertEqual(cell.peakC, 40)
        XCTAssertEqual(cell.count, 2)
        XCTAssertEqual(cell.sumC, 70, accuracy: 0.0001)
    }

    func testRecentDaysZeroReturnsEmpty() {
        var t = HourlyHeatTracker()
        t.ingest(temperatureC: 36, at: t0, calendar: cal)
        XCTAssertEqual(t.recentDays(0, endingAt: t0, calendar: cal), [])
    }
}
