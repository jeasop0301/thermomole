import XCTest
@testable import ThermoMoleCore

final class ChargeExposureTrackerTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private let t0 = Date(timeIntervalSince1970: 1_781_000_000)

    func testFirstSampleCreditsNothing() {
        var t = ChargeExposureTracker()
        t.ingest(percent: 90, isOnACPower: true, at: t0, calendar: cal)
        XCTAssertEqual(t.today(at: t0, calendar: cal).secondsAbove80OnAC, 0, accuracy: 0.001)
    }

    func testOnACHighCreditsAbove80Only() {
        var t = ChargeExposureTracker()
        t.ingest(percent: 90, isOnACPower: true, at: t0, calendar: cal)
        t.ingest(percent: 90, isOnACPower: true, at: t0.addingTimeInterval(5), calendar: cal)
        let d = t.today(at: t0, calendar: cal)
        XCTAssertEqual(d.secondsAbove80OnAC, 5, accuracy: 0.001)
        XCTAssertEqual(d.secondsAbove95OnAC, 0, accuracy: 0.001)
    }

    func testOnACVeryHighCreditsBothBands() {
        var t = ChargeExposureTracker()
        t.ingest(percent: 98, isOnACPower: true, at: t0, calendar: cal)
        t.ingest(percent: 98, isOnACPower: true, at: t0.addingTimeInterval(4), calendar: cal)
        let d = t.today(at: t0, calendar: cal)
        XCTAssertEqual(d.secondsAbove80OnAC, 4, accuracy: 0.001)
        XCTAssertEqual(d.secondsAbove95OnAC, 4, accuracy: 0.001)
    }

    func testOffACCreditsNothing() {
        var t = ChargeExposureTracker()
        t.ingest(percent: 99, isOnACPower: false, at: t0, calendar: cal)
        t.ingest(percent: 99, isOnACPower: false, at: t0.addingTimeInterval(5), calendar: cal)
        XCTAssertEqual(t.today(at: t0, calendar: cal).secondsAbove80OnAC, 0, accuracy: 0.001)
    }

    func testBelowHighThresholdCreditsNothing() {
        var t = ChargeExposureTracker()
        t.ingest(percent: 70, isOnACPower: true, at: t0, calendar: cal)
        t.ingest(percent: 70, isOnACPower: true, at: t0.addingTimeInterval(5), calendar: cal)
        XCTAssertEqual(t.today(at: t0, calendar: cal).secondsAbove80OnAC, 0, accuracy: 0.001)
    }

    func testGapCapLimitsCreditedSeconds() {
        var t = ChargeExposureTracker()
        t.ingest(percent: 90, isOnACPower: true, at: t0, calendar: cal)
        t.ingest(percent: 90, isOnACPower: true, at: t0.addingTimeInterval(3600), calendar: cal)
        XCTAssertEqual(t.today(at: t0, calendar: cal).secondsAbove80OnAC, ChargeExposureTracker.gapCapSeconds, accuracy: 0.001)
    }

    func testClockBackwardCreditsNothing() {
        var t = ChargeExposureTracker()
        t.ingest(percent: 90, isOnACPower: true, at: t0.addingTimeInterval(10), calendar: cal)
        t.ingest(percent: 90, isOnACPower: true, at: t0, calendar: cal)
        XCTAssertEqual(t.today(at: t0, calendar: cal).secondsAbove80OnAC, 0, accuracy: 0.001)
    }

    func testPeakPercentTrackedOnlyOnAC() {
        var t = ChargeExposureTracker()
        t.ingest(percent: 99, isOnACPower: false, at: t0, calendar: cal)
        t.ingest(percent: 88, isOnACPower: true, at: t0.addingTimeInterval(5), calendar: cal)
        XCTAssertEqual(t.today(at: t0, calendar: cal).peakPercentOnAC, 88)
    }

    func testIntervalSplitsAcrossMidnight() {
        let comps = DateComponents(timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 6, day: 16, hour: 23, minute: 59, second: 57)
        let start = cal.date(from: comps)!
        var t = ChargeExposureTracker()
        t.ingest(percent: 90, isOnACPower: true, at: start, calendar: cal)
        t.ingest(percent: 90, isOnACPower: true, at: start.addingTimeInterval(6), calendar: cal)
        XCTAssertEqual(t.today(at: start, calendar: cal).secondsAbove80OnAC, 3, accuracy: 0.001)
        XCTAssertEqual(t.today(at: start.addingTimeInterval(6), calendar: cal).secondsAbove80OnAC, 3, accuracy: 0.001)
    }

    func testRecentDaysReturnsNewestFirst() {
        var t = ChargeExposureTracker()
        t.ingest(percent: 90, isOnACPower: true, at: t0, calendar: cal)
        t.ingest(percent: 90, isOnACPower: true, at: t0.addingTimeInterval(5), calendar: cal)
        let recent = t.recentDays(7, endingAt: t0, calendar: cal)
        XCTAssertEqual(recent.count, 7)
        XCTAssertEqual(recent.first?.day, ChargeExposureTracker.dayKey(for: t0, calendar: cal))
    }
}
