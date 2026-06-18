import XCTest
@testable import ThermoMoleCore

final class AgingStrainTrackerTests: XCTestCase {
    private var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func testEffectiveAccumulation() {
        var t = AgingStrainTracker()
        t.ingest(rawMultiplier: 5.0, at: t0, calendar: cal)
        t.ingest(rawMultiplier: 5.0, at: at(2), calendar: cal)
        let d = t.today(at: at(2), calendar: cal)
        XCTAssertEqual(d.calendarSeconds, 2, accuracy: 0.001)
        XCTAssertEqual(d.effectiveSeconds, 10, accuracy: 0.001)
        XCTAssertEqual(d.peakMultiplier, 5.0, accuracy: 0.001)
    }
    func testFloorAtOne() {
        var t = AgingStrainTracker()
        t.ingest(rawMultiplier: 0.5, at: t0, calendar: cal)
        t.ingest(rawMultiplier: 0.5, at: at(2), calendar: cal)
        XCTAssertEqual(t.today(at: at(2), calendar: cal).effectiveSeconds, 2, accuracy: 0.001)
    }
    func testGapCap() {
        var t = AgingStrainTracker()
        t.ingest(rawMultiplier: 1.0, at: t0, calendar: cal)
        t.ingest(rawMultiplier: 1.0, at: at(600), calendar: cal)
        XCTAssertEqual(t.today(at: at(600), calendar: cal).calendarSeconds, 6, accuracy: 0.001)
    }
    func testFirstSampleNoCredit() {
        var t = AgingStrainTracker()
        t.ingest(rawMultiplier: 5.0, at: t0, calendar: cal)
        XCTAssertEqual(t.today(at: t0, calendar: cal).calendarSeconds, 0, accuracy: 0.001)
    }
    func testReset() {
        var t = AgingStrainTracker()
        t.ingest(rawMultiplier: 5, at: t0, calendar: cal); t.ingest(rawMultiplier: 5, at: at(2), calendar: cal)
        t.reset()
        XCTAssertEqual(t.today(at: at(2), calendar: cal).effectiveSeconds, 0, accuracy: 0.001)
    }
}
