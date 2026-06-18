import XCTest
@testable import ThermoMoleCore

final class ThermalExposureTrackerTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14T22:13:20Z

    private func at(_ offset: TimeInterval) -> Date { t0.addingTimeInterval(offset) }

    func testGapCapConstantIsLocked() {
        XCTAssertEqual(ThermalExposureTracker.gapCapSeconds, 6.0)
    }

    func testFirstSampleCreditsZero() {
        var t = ThermalExposureTracker()
        t.ingest(temperatureC: 42, at: t0, calendar: cal)
        let today = t.today(at: t0, calendar: cal)
        XCTAssertEqual(today.secondsAbove40, 0)
        XCTAssertEqual(today.secondsAbove45, 0)
        XCTAssertEqual(today.peakC, 42)
    }

    // 42°C ≥ batteryExposureWarmC(40) and < batteryExposureHotC(45) → .caution
    // credits secondsAbove40 but NOT secondsAbove45
    func testNormalIntervalCreditsCautionBand() {
        var t = ThermalExposureTracker()
        t.ingest(temperatureC: 42, at: t0, calendar: cal)
        t.ingest(temperatureC: 42, at: at(2), calendar: cal)
        let today = t.today(at: at(2), calendar: cal)
        XCTAssertEqual(today.secondsAbove40, 2, accuracy: 0.0001)
        XCTAssertEqual(today.secondsAbove45, 0)
    }

    // 46°C ≥ batteryExposureHotC(45) → .hot, credits both bands
    func testHotBandCreditsAbove45TooAt46C() {
        var t = ThermalExposureTracker()
        t.ingest(temperatureC: 46, at: t0, calendar: cal)
        t.ingest(temperatureC: 46, at: at(2), calendar: cal)
        let today = t.today(at: at(2), calendar: cal)
        XCTAssertEqual(today.secondsAbove40, 2, accuracy: 0.0001)
        XCTAssertEqual(today.secondsAbove45, 2, accuracy: 0.0001)
    }

    // 38°C < batteryExposureWarmC(40) → .none, no credit
    func testBelowWarmBandCreditsNothing() {
        var t = ThermalExposureTracker()
        t.ingest(temperatureC: 38, at: t0, calendar: cal)
        t.ingest(temperatureC: 38, at: at(2), calendar: cal)
        let today = t.today(at: at(2), calendar: cal)
        XCTAssertEqual(today.secondsAbove40, 0)
        XCTAssertEqual(today.secondsAbove45, 0)
    }

    func testPreviousSampleAttribution() {
        var t = ThermalExposureTracker()
        t.ingest(temperatureC: 30, at: t0, calendar: cal)
        t.ingest(temperatureC: 46, at: at(2), calendar: cal) // prev 30 -> none
        XCTAssertEqual(t.today(at: at(2), calendar: cal).secondsAbove40, 0)
        t.ingest(temperatureC: 46, at: at(4), calendar: cal) // prev 46 -> hot
        XCTAssertEqual(t.today(at: at(4), calendar: cal).secondsAbove40, 2, accuracy: 0.0001)
        XCTAssertEqual(t.today(at: at(4), calendar: cal).secondsAbove45, 2, accuracy: 0.0001)
    }

    func testNilPreviousCreditsZeroButUpdatesPeak() {
        var t = ThermalExposureTracker()
        t.ingest(temperatureC: nil, at: t0, calendar: cal)
        t.ingest(temperatureC: 46, at: at(2), calendar: cal) // prev nil -> 0 credit, peak 46
        XCTAssertEqual(t.today(at: at(2), calendar: cal).secondsAbove40, 0)
        XCTAssertEqual(t.today(at: at(2), calendar: cal).peakC, 46)
    }

    func testNilCurrentDoesNotLowerPeak() {
        var t = ThermalExposureTracker()
        t.ingest(temperatureC: 50, at: t0, calendar: cal)
        t.ingest(temperatureC: nil, at: at(2), calendar: cal)
        t.ingest(temperatureC: 30, at: at(4), calendar: cal)
        t.ingest(temperatureC: nil, at: at(6), calendar: cal)
        XCTAssertEqual(t.today(at: t0, calendar: cal).peakC, 50)
    }

    func testClockBackwardsCreditsZeroAndRepairsAnchor() {
        var t = ThermalExposureTracker()
        t.ingest(temperatureC: 42, at: t0, calendar: cal)
        t.ingest(temperatureC: 42, at: at(-5), calendar: cal) // negative -> 0, anchor -> t0-5
        XCTAssertEqual(t.today(at: t0, calendar: cal).secondsAbove40, 0)
        t.ingest(temperatureC: 42, at: at(-3), calendar: cal) // 2s from repaired anchor
        XCTAssertEqual(t.today(at: t0, calendar: cal).secondsAbove40, 2, accuracy: 0.0001)
    }

    func testElapsedAtGapCapCreditsFullCap() {
        var t = ThermalExposureTracker()
        t.ingest(temperatureC: 42, at: t0, calendar: cal)
        t.ingest(temperatureC: 42, at: at(6), calendar: cal) // exactly cap
        XCTAssertEqual(t.today(at: t0, calendar: cal).secondsAbove40, 6, accuracy: 0.0001)
    }

    func testLongSleepClampsToGapCap() {
        var t = ThermalExposureTracker()
        t.ingest(temperatureC: 42, at: t0, calendar: cal)
        t.ingest(temperatureC: 42, at: at(3600), calendar: cal) // 1h -> clamp 6s (same UTC day)
        XCTAssertEqual(t.today(at: t0, calendar: cal).secondsAbove40, 6, accuracy: 0.0001)
    }

    func testIntervalSpanningMidnightIsSplit() {
        var t = ThermalExposureTracker()
        let beforeMidnight = Date(timeIntervalSince1970: -2) // 1969-12-31 23:59:58Z
        let afterMidnight = Date(timeIntervalSince1970: 2)   // 1970-01-01 00:00:02Z
        t.ingest(temperatureC: 42, at: beforeMidnight, calendar: cal)
        t.ingest(temperatureC: 42, at: afterMidnight, calendar: cal) // 4s, prev 42 caution
        XCTAssertEqual(t.today(at: beforeMidnight, calendar: cal).secondsAbove40, 2, accuracy: 0.0001)
        XCTAssertEqual(t.today(at: afterMidnight, calendar: cal).secondsAbove40, 2, accuracy: 0.0001)
    }

    func testNestedBandsAndBoundaries() {
        func seconds40(_ temp: Double) -> TimeInterval {
            var t = ThermalExposureTracker()
            t.ingest(temperatureC: temp, at: t0, calendar: cal)
            t.ingest(temperatureC: temp, at: at(2), calendar: cal)
            return t.today(at: t0, calendar: cal).secondsAbove40
        }
        func seconds45(_ temp: Double) -> TimeInterval {
            var t = ThermalExposureTracker()
            t.ingest(temperatureC: temp, at: t0, calendar: cal)
            t.ingest(temperatureC: temp, at: at(2), calendar: cal)
            return t.today(at: t0, calendar: cal).secondsAbove45
        }
        XCTAssertEqual(seconds40(39.99), 0)
        XCTAssertEqual(seconds40(40.0), 2, accuracy: 0.0001)  // ≥40 → caution → credits above40
        XCTAssertEqual(seconds45(44.99), 0)
        XCTAssertEqual(seconds40(44.99), 2, accuracy: 0.0001) // ≥40 but <45 → caution only
        XCTAssertEqual(seconds45(45.0), 2, accuracy: 0.0001)  // ≥45 → hot → credits both
    }

    func testInjectedTimezoneChangesDayAttribution() {
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        var plus14 = Calendar(identifier: .gregorian); plus14.timeZone = TimeZone(secondsFromGMT: 14 * 3600)!
        var a = ThermalExposureTracker()
        a.ingest(temperatureC: 42, at: t0, calendar: utc)
        var b = ThermalExposureTracker()
        b.ingest(temperatureC: 42, at: t0, calendar: plus14)
        XCTAssertNotEqual(
            ThermalExposureTracker.dayKey(for: t0, calendar: utc),
            ThermalExposureTracker.dayKey(for: t0, calendar: plus14)
        )
    }

    func testRecentDaysReturnsOrderedSequenceWithGapsFilled() {
        var t = ThermalExposureTracker()
        t.ingest(temperatureC: 42, at: t0, calendar: cal)
        t.ingest(temperatureC: 42, at: at(2), calendar: cal) // today gets 2s
        let recent = t.recentDays(3, endingAt: at(2), calendar: cal)
        XCTAssertEqual(recent.count, 3)
        XCTAssertEqual(recent[0].day, ThermalExposureTracker.dayKey(for: at(2), calendar: cal))
        XCTAssertEqual(recent[0].secondsAbove40, 2, accuracy: 0.0001)
        XCTAssertEqual(recent[1].secondsAbove40, 0)
        XCTAssertEqual(recent[2].secondsAbove40, 0)
        XCTAssertTrue(recent[0].day > recent[1].day)
        XCTAssertTrue(recent[1].day > recent[2].day)
    }

    func testRecentDaysZeroReturnsEmpty() {
        var t = ThermalExposureTracker()
        t.ingest(temperatureC: 42, at: t0, calendar: cal)
        XCTAssertTrue(t.recentDays(0, endingAt: t0, calendar: cal).isEmpty)
    }

    func testResetClearsEverything() {
        var t = ThermalExposureTracker()
        t.ingest(temperatureC: 42, at: t0, calendar: cal)
        t.ingest(temperatureC: 42, at: at(2), calendar: cal)
        t.reset()
        XCTAssertEqual(t.today(at: t0, calendar: cal).secondsAbove40, 0)
        XCTAssertNil(t.today(at: t0, calendar: cal).peakC)
    }
}
