import XCTest
@testable import ThermoMoleCore

private final class SpyStore: ThermalExposurePersisting, @unchecked Sendable {
    var saved: [ThermalExposureRecord] = []
    var loadResult: ThermalExposureRecord?
    var failSave = false
    func load() throws -> ThermalExposureRecord? { loadResult }
    func save(_ record: ThermalExposureRecord) throws {
        if failSave { throw NSError(domain: "test", code: 1) }
        saved.append(record)
    }
}

final class ThermalExposureCoordinatorTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testThrottleFlushesAtMostOncePerInterval() async {
        let spy = SpyStore()
        let coord = ThermalExposureCoordinator(store: spy, flushInterval: 60)
        for i in 0..<30 { // t0 .. t0+58s
            await coord.record(temperatureC: 42, at: t0.addingTimeInterval(Double(i * 2)), calendar: cal)
        }
        let countWithin60 = await coord.flushCountForTesting
        XCTAssertEqual(countWithin60, 1)
        await coord.record(temperatureC: 42, at: t0.addingTimeInterval(60), calendar: cal)
        let countAfter = await coord.flushCountForTesting
        XCTAssertEqual(countAfter, 2)
    }

    func testFlushNowBypassesThrottle() async {
        let spy = SpyStore()
        let coord = ThermalExposureCoordinator(store: spy, flushInterval: 60)
        await coord.record(temperatureC: 42, at: t0, calendar: cal)            // flush #1
        await coord.record(temperatureC: 42, at: t0.addingTimeInterval(2), calendar: cal) // no flush
        await coord.flushNow(at: t0.addingTimeInterval(2))                      // forced #2
        XCTAssertEqual(spy.saved.count, 2)
    }

    func testWriteFailureRetainsStateAndSurfacesError() async {
        let spy = SpyStore()
        spy.failSave = true
        let coord = ThermalExposureCoordinator(store: spy, flushInterval: 60)
        await coord.record(temperatureC: 42, at: t0, calendar: cal)             // flush attempt fails
        await coord.record(temperatureC: 42, at: t0.addingTimeInterval(2), calendar: cal) // also flushes+fails (lastFlushAt still nil); state retained
        let err = await coord.lastWriteError
        XCTAssertNotNil(err)
        spy.failSave = false
        await coord.flushNow(at: t0.addingTimeInterval(4))
        XCTAssertEqual(try XCTUnwrap(spy.saved.last?.days.first?.secondsAbove40), 2, accuracy: 0.0001) // 2 s retained
    }

    func testBootstrapSeedsFromStore() async {
        let spy = SpyStore()
        spy.loadResult = ThermalExposureRecord(schemaVersion: 2, days: [
            DailyThermalExposure(day: ThermalExposureTracker.dayKey(for: t0, calendar: cal), secondsAbove40: 100)
        ])
        let coord = ThermalExposureCoordinator(store: spy, flushInterval: 60)
        await coord.bootstrap()
        let summary = await coord.summary(at: t0, calendar: cal)
        XCTAssertEqual(summary.today.secondsAbove40, 100, accuracy: 0.0001)
    }

    func testAllDaysReturnsEveryTrackedDay() async {
        let coord = ThermalExposureCoordinator(store: SpyStore(), flushInterval: 60)
        await coord.record(temperatureC: 42, at: t0, calendar: cal)
        await coord.record(temperatureC: 42, at: t0.addingTimeInterval(2), calendar: cal)
        await coord.record(temperatureC: 42, at: t0.addingTimeInterval(2 * 3600), calendar: cal) // next day
        let all = await coord.allDays()
        XCTAssertEqual(Set(all.map { $0.day }).count, 2)
    }
}
