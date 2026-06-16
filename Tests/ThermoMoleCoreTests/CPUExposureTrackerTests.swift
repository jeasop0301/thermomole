import XCTest
@testable import ThermoMoleCore

final class CPUExposureTrackerTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private let t0 = Date(timeIntervalSince1970: 1_781_000_000)

    func testFirstSampleCreditsNothing() {
        var t = CPUExposureTracker()
        t.ingest(temperatureC: 90, at: t0, calendar: cal)
        XCTAssertEqual(t.today(at: t0, calendar: cal).secondsAbove85, 0, accuracy: 0.001)
    }

    func testWarmCreditsAbove85Only() {
        var t = CPUExposureTracker()
        t.ingest(temperatureC: 90, at: t0, calendar: cal)
        t.ingest(temperatureC: 90, at: t0.addingTimeInterval(5), calendar: cal)
        let d = t.today(at: t0, calendar: cal)
        XCTAssertEqual(d.secondsAbove85, 5, accuracy: 0.001)
        XCTAssertEqual(d.secondsAbove95, 0, accuracy: 0.001)
    }

    func testHotCreditsBothBands() {
        var t = CPUExposureTracker()
        t.ingest(temperatureC: 97, at: t0, calendar: cal)
        t.ingest(temperatureC: 97, at: t0.addingTimeInterval(4), calendar: cal)
        let d = t.today(at: t0, calendar: cal)
        XCTAssertEqual(d.secondsAbove85, 4, accuracy: 0.001)
        XCTAssertEqual(d.secondsAbove95, 4, accuracy: 0.001)
    }

    func testBelowWarmCreditsNothing() {
        var t = CPUExposureTracker()
        t.ingest(temperatureC: 70, at: t0, calendar: cal)
        t.ingest(temperatureC: 70, at: t0.addingTimeInterval(5), calendar: cal)
        XCTAssertEqual(t.today(at: t0, calendar: cal).secondsAbove85, 0, accuracy: 0.001)
    }

    func testGapCapLimitsCredit() {
        var t = CPUExposureTracker()
        t.ingest(temperatureC: 90, at: t0, calendar: cal)
        t.ingest(temperatureC: 90, at: t0.addingTimeInterval(3600), calendar: cal)
        XCTAssertEqual(t.today(at: t0, calendar: cal).secondsAbove85, CPUExposureTracker.gapCapSeconds, accuracy: 0.001)
    }

    func testNilTemperatureCreditsNothing() {
        var t = CPUExposureTracker()
        t.ingest(temperatureC: nil, at: t0, calendar: cal)
        t.ingest(temperatureC: nil, at: t0.addingTimeInterval(5), calendar: cal)
        XCTAssertEqual(t.today(at: t0, calendar: cal).secondsAbove85, 0, accuracy: 0.001)
    }

    func testPeakTracked() {
        var t = CPUExposureTracker()
        t.ingest(temperatureC: 88, at: t0, calendar: cal)
        t.ingest(temperatureC: 92, at: t0.addingTimeInterval(2), calendar: cal)
        XCTAssertEqual(t.today(at: t0, calendar: cal).peakC, 92)
    }
}
