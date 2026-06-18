import XCTest
@testable import ThermoMoleCore

private final class SpyStore: HourlyHeatPersisting, @unchecked Sendable {
    var saved: HourlyHeatRecord?
    var saveCount = 0
    var failSave = false
    func load() throws -> HourlyHeatRecord? { saved }
    func save(_ record: HourlyHeatRecord) throws {
        if failSave { throw NSError(domain: "test", code: 1) }
        saved = record; saveCount += 1
    }
}

final class HourlyHeatCoordinatorTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000) // hour 22 UTC

    func testRecordThenGridReflectsSample() async {
        let coord = HourlyHeatCoordinator(store: SpyStore(), flushInterval: 60)
        await coord.record(temperatureC: 38, at: t0, calendar: cal)
        let grid = await coord.grid(maxDays: 1, endingAt: t0, calendar: cal)
        XCTAssertEqual(grid.count, 1)
        XCTAssertEqual(grid.first?.hours[22].count, 1)
        XCTAssertEqual(grid.first?.hours[22].peakC, 38)
    }

    func testFlushThrottleAndForce() async {
        let spy = SpyStore()
        let coord = HourlyHeatCoordinator(store: spy, flushInterval: 60)
        await coord.record(temperatureC: 38, at: t0, calendar: cal)            // first -> flush
        await coord.record(temperatureC: 39, at: t0.addingTimeInterval(5), calendar: cal) // within window -> no flush
        let afterTwo = spy.saveCount
        await coord.flushNow(at: t0.addingTimeInterval(5))                       // force
        XCTAssertEqual(afterTwo, 1)
        XCTAssertEqual(spy.saveCount, 2)
        XCTAssertEqual(spy.saved?.schemaVersion, 1)
    }

    func testWriteFailureSurfacesError() async {
        let spy = SpyStore()
        spy.failSave = true
        let coord = HourlyHeatCoordinator(store: spy, flushInterval: 60)
        await coord.record(temperatureC: 38, at: t0, calendar: cal)             // flush attempt fails
        await coord.record(temperatureC: 39, at: t0.addingTimeInterval(2), calendar: cal) // also flushes+fails (lastFlushAt still nil)
        let err = await coord.lastWriteError
        XCTAssertNotNil(err)
    }

    func testBootstrapSeedsFromStore() async {
        let spy = SpyStore()
        var seedDay = DailyHourlyHeat.empty(day: HourlyHeatTracker.dayKey(for: t0, calendar: cal))
        seedDay.hours[22] = HourHeatCell(sumC: 36, count: 1, peakC: 36)
        spy.saved = HourlyHeatRecord(days: [seedDay])
        let coord = HourlyHeatCoordinator(store: spy, flushInterval: 60)
        await coord.bootstrap()
        let grid = await coord.grid(maxDays: 1, endingAt: t0, calendar: cal)
        XCTAssertEqual(grid.first?.hours[22].count, 1)
    }
}
