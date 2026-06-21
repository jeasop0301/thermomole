import XCTest
@testable import ThermoMoleCore

/// Covers the forward-only "since install" cumulative accumulation semantics — the tricky part:
/// only completed days count, idempotency, survival across a 30-day prune, firstDay/lastCountedDay
/// bookkeeping, the seconds→hours summary, and v1-JSON migration (no cumulative → empty).
final class SinceInstallExposureTests: XCTestCase {

    // MARK: - Charge accumulator

    func testOnlyCompletedDaysBeforeTodayCount() {
        let days = [
            DailyChargeExposure(day: "2026-06-01", secondsAbove80OnAC: 100, secondsAbove95OnAC: 10),
            DailyChargeExposure(day: "2026-06-02", secondsAbove80OnAC: 200, secondsAbove95OnAC: 20),
            DailyChargeExposure(day: "2026-06-03", secondsAbove80OnAC: 999, secondsAbove95OnAC: 99), // today, in progress
        ]
        let result = CumulativeChargeExposure().accumulating(days: days, today: "2026-06-03")
        XCTAssertEqual(result.secondsAbove80OnAC, 300, accuracy: 0.0001) // 06-03 excluded
        XCTAssertEqual(result.secondsAbove95OnAC, 30, accuracy: 0.0001)
        XCTAssertEqual(result.firstDay, "2026-06-01")
        XCTAssertEqual(result.lastCountedDay, "2026-06-02")
    }

    func testIdempotentSameDataCountsEachDayOnce() {
        let days = [
            DailyChargeExposure(day: "2026-06-01", secondsAbove80OnAC: 100, secondsAbove95OnAC: 10),
            DailyChargeExposure(day: "2026-06-02", secondsAbove80OnAC: 200, secondsAbove95OnAC: 20),
        ]
        let once = CumulativeChargeExposure().accumulating(days: days, today: "2026-06-03")
        let twice = once.accumulating(days: days, today: "2026-06-03")
        XCTAssertEqual(once, twice) // second pass adds nothing
        XCTAssertEqual(twice.secondsAbove80OnAC, 300, accuracy: 0.0001)
    }

    func testForwardOnlyAcrossPrune() {
        // Simulate the real flush path: accumulate over the FULL day-set, prune the days, then
        // a later flush sees a longer history (older days already pruned away from `days`) — the
        // pruned days must remain counted in the cumulative, neither lost nor double-counted.
        var cumulative = CumulativeChargeExposure()

        // Day 1..30 exist; today is day 31. All 30 are completed → counted.
        let early = (1...30).map {
            DailyChargeExposure(day: String(format: "2026-01-%02d", $0), secondsAbove80OnAC: 60, secondsAbove95OnAC: 6)
        }
        cumulative = cumulative.accumulating(days: early, today: "2026-01-31")
        XCTAssertEqual(cumulative.secondsAbove80OnAC, 30 * 60, accuracy: 0.0001)

        // Prune to 30 keeps days 02..31; day 01 is dropped from `days`.
        let pruned = ChargeExposureRecord(days: early + [
            DailyChargeExposure(day: "2026-01-31", secondsAbove80OnAC: 60, secondsAbove95OnAC: 6)
        ]).pruned(toDays: 30)
        XCTAssertNil(pruned.days.first { $0.day == "2026-01-01" }) // day 01 gone from stored days

        // Next flush: a day later, today = 2026-02-01. day 31 is now completed and counts;
        // day 01 (pruned from `days`) is NOT re-summed but stays in the total.
        cumulative = cumulative.accumulating(days: pruned.days, today: "2026-02-01")
        XCTAssertEqual(cumulative.secondsAbove80OnAC, 31 * 60, accuracy: 0.0001) // 31 days total, no loss/dup
        XCTAssertEqual(cumulative.firstDay, "2026-01-01") // earliest never forgotten
        XCTAssertEqual(cumulative.lastCountedDay, "2026-01-31")
    }

    func testFirstDayPinnedToEarliestCountedAndLastAdvances() {
        // First flush sees days 05..07 (today 08): firstDay pins to the earliest, last to newest.
        var c = CumulativeChargeExposure()
        let batch1 = (5...7).map { DailyChargeExposure(day: String(format: "2026-06-%02d", $0), secondsAbove80OnAC: 10) }
        c = c.accumulating(days: batch1, today: "2026-06-08")
        XCTAssertEqual(c.firstDay, "2026-06-05")
        XCTAssertEqual(c.lastCountedDay, "2026-06-07")
        // Later flush adds days 08..09 (today 10): firstDay stays, last advances; no re-count.
        let batch2 = (5...9).map { DailyChargeExposure(day: String(format: "2026-06-%02d", $0), secondsAbove80OnAC: 10) }
        c = c.accumulating(days: batch2, today: "2026-06-10")
        XCTAssertEqual(c.firstDay, "2026-06-05")   // never forgotten, never re-lowered below earliest
        XCTAssertEqual(c.lastCountedDay, "2026-06-09")
        XCTAssertEqual(c.secondsAbove80OnAC, 5 * 10, accuracy: 0.0001) // 5 distinct days, each once
    }

    func testAlreadyCountedEarlierDayIsNotDoubleCounted() {
        // High-water mark guards double-counting: a day at or before lastCountedDay is skipped,
        // so its seconds are never added twice even if it reappears in `days`.
        var c = CumulativeChargeExposure()
        c = c.accumulating(days: [DailyChargeExposure(day: "2026-06-10", secondsAbove80OnAC: 100)], today: "2026-06-11")
        XCTAssertEqual(c.secondsAbove80OnAC, 100, accuracy: 0.0001)
        // 06-05 is <= lastCountedDay(06-10): skipped, no double-count, totals unchanged.
        c = c.accumulating(days: [DailyChargeExposure(day: "2026-06-05", secondsAbove80OnAC: 50)], today: "2026-06-11")
        XCTAssertEqual(c.secondsAbove80OnAC, 100, accuracy: 0.0001)
        XCTAssertEqual(c.firstDay, "2026-06-10")
    }

    func testEmptyAndTodayOnlyAccumulateNothing() {
        let empty = CumulativeChargeExposure().accumulating(days: [], today: "2026-06-03")
        XCTAssertEqual(empty, CumulativeChargeExposure())
        let todayOnly = CumulativeChargeExposure().accumulating(
            days: [DailyChargeExposure(day: "2026-06-03", secondsAbove80OnAC: 500)],
            today: "2026-06-03"
        )
        XCTAssertEqual(todayOnly, CumulativeChargeExposure()) // today in progress, not counted
    }

    // MARK: - Thermal accumulator

    func testThermalOnlyCompletedDaysCount() {
        let days = [
            DailyThermalExposure(day: "2026-06-01", secondsAbove40: 100, secondsAbove45: 10),
            DailyThermalExposure(day: "2026-06-02", secondsAbove40: 200, secondsAbove45: 20),
            DailyThermalExposure(day: "2026-06-03", secondsAbove40: 999, secondsAbove45: 99), // today
        ]
        let r = CumulativeThermalExposure().accumulating(days: days, today: "2026-06-03")
        XCTAssertEqual(r.secondsAbove40, 300, accuracy: 0.0001)
        XCTAssertEqual(r.secondsAbove45, 30, accuracy: 0.0001)
        XCTAssertEqual(r.firstDay, "2026-06-01")
        XCTAssertEqual(r.lastCountedDay, "2026-06-02")
    }

    func testThermalIdempotent() {
        let days = [DailyThermalExposure(day: "2026-06-01", secondsAbove40: 100, secondsAbove45: 10)]
        let once = CumulativeThermalExposure().accumulating(days: days, today: "2026-06-03")
        let twice = once.accumulating(days: days, today: "2026-06-03")
        XCTAssertEqual(once, twice)
    }

    // MARK: - Summary (seconds → hours)

    func testSinceInstallSummaryConvertsSecondsToHoursAndPicksEarliestDay() {
        let charge = CumulativeChargeExposure(
            firstDay: "2026-06-02", lastCountedDay: "2026-06-10",
            secondsAbove80OnAC: 3600 * 140, secondsAbove95OnAC: 3600 * 60
        )
        let thermal = CumulativeThermalExposure(
            firstDay: "2026-06-01", lastCountedDay: "2026-06-10",
            secondsAbove40: 3600 * 12, secondsAbove45: 3600 * 3
        )
        let summary = SinceInstallExposure.from(thermal: thermal, charge: charge)
        XCTAssertEqual(summary.sinceDay, "2026-06-01") // earliest of the two firstDays
        XCTAssertEqual(summary.hoursAbove40, 12, accuracy: 0.0001)
        XCTAssertEqual(summary.hoursAbove45, 3, accuracy: 0.0001)
        XCTAssertEqual(summary.hoursAbove80OnAC, 140, accuracy: 0.0001)
        XCTAssertEqual(summary.hoursAbove95OnAC, 60, accuracy: 0.0001)
    }

    func testSinceInstallSummaryNilWhenNoCountedDays() {
        let summary = SinceInstallExposure.from(thermal: CumulativeThermalExposure(), charge: CumulativeChargeExposure())
        XCTAssertNil(summary.sinceDay)
        XCTAssertEqual(summary.hoursAbove40, 0, accuracy: 0.0001)
    }

    func testSinceInstallSummaryEarliestWhenOneSideEmpty() {
        let charge = CumulativeChargeExposure(firstDay: "2026-06-05", lastCountedDay: "2026-06-05", secondsAbove80OnAC: 3600)
        let summary = SinceInstallExposure.from(thermal: CumulativeThermalExposure(), charge: charge)
        XCTAssertEqual(summary.sinceDay, "2026-06-05")
        XCTAssertEqual(summary.hoursAbove80OnAC, 1, accuracy: 0.0001)
    }

    // MARK: - Schema migration (v1 JSON without cumulative decodes empty)

    func testChargeV1JSONWithoutCumulativeDecodesEmptyCumulative() throws {
        let json = """
        {"schemaVersion":1,"days":[{"day":"2026-06-01","peakPercentOnAC":99,"secondsAbove80OnAC":120,"secondsAbove95OnAC":30}]}
        """.data(using: .utf8)!
        let record = try JSONDecoder().decode(ChargeExposureRecord.self, from: json)
        XCTAssertEqual(record.days.count, 1)
        XCTAssertEqual(record.cumulative, CumulativeChargeExposure()) // missing key → empty default
    }

    func testThermalV1JSONWithoutCumulativeDecodesEmptyCumulative() throws {
        let json = """
        {"schemaVersion":2,"days":[{"day":"2026-06-01","peakC":44,"secondsAbove40":120,"secondsAbove45":30}]}
        """.data(using: .utf8)!
        let record = try JSONDecoder().decode(ThermalExposureRecord.self, from: json)
        XCTAssertEqual(record.days.count, 1)
        XCTAssertEqual(record.cumulative, CumulativeThermalExposure())
    }

    func testChargeRecordWithCumulativeRoundTrips() throws {
        var record = ChargeExposureRecord(days: [DailyChargeExposure(day: "2026-06-01", secondsAbove80OnAC: 60)])
        record.cumulative = CumulativeChargeExposure(
            firstDay: "2026-05-01", lastCountedDay: "2026-05-31",
            secondsAbove80OnAC: 1000, secondsAbove95OnAC: 100
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ChargeExposureRecord.self, from: data)
        XCTAssertEqual(decoded, record)
        XCTAssertEqual(decoded.cumulative.secondsAbove80OnAC, 1000, accuracy: 0.0001)
    }

    func testThermalRecordWithCumulativeRoundTrips() throws {
        var record = ThermalExposureRecord(days: [DailyThermalExposure(day: "2026-06-01", secondsAbove40: 60)])
        record.cumulative = CumulativeThermalExposure(
            firstDay: "2026-05-01", lastCountedDay: "2026-05-31",
            secondsAbove40: 1000, secondsAbove45: 100
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ThermalExposureRecord.self, from: data)
        XCTAssertEqual(decoded, record)
        XCTAssertEqual(decoded.cumulative.secondsAbove45, 100, accuracy: 0.0001)
    }
}

// MARK: - Coordinator wiring

private final class ChargeSpyStore: ChargeExposurePersisting, @unchecked Sendable {
    var saved: [ChargeExposureRecord] = []
    var loadResult: ChargeExposureRecord?
    func load() throws -> ChargeExposureRecord? { loadResult }
    func save(_ record: ChargeExposureRecord) throws { saved.append(record) }
}

private final class ThermalSpyStore: ThermalExposurePersisting, @unchecked Sendable {
    var saved: [ThermalExposureRecord] = []
    var loadResult: ThermalExposureRecord?
    func load() throws -> ThermalExposureRecord? { loadResult }
    func save(_ record: ThermalExposureRecord) throws { saved.append(record) }
}

final class SinceInstallCoordinatorTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()
    // 2026-06-01 00:00:00 UTC
    private let day1 = Date(timeIntervalSince1970: 1_780_272_000)

    func testChargeFlushAccumulatesCompletedDaysBeforePruneAndPersists() async {
        let spy = ChargeSpyStore()
        let coord = ChargeExposureCoordinator(store: spy, flushInterval: 0)
        // Record dwell on day1, then a sample two days later → day1 is a completed day.
        await coord.record(percent: 90, isOnACPower: true, at: day1, calendar: cal)
        await coord.record(percent: 90, isOnACPower: true, at: day1.addingTimeInterval(4), calendar: cal)
        // Force a flush from a later day so day1 is "completed".
        let day3 = day1.addingTimeInterval(2 * 86_400)
        await coord.flushNow(at: day3)
        let last = try? XCTUnwrap(spy.saved.last)
        XCTAssertEqual(last?.cumulative.secondsAbove80OnAC ?? -1, 4, accuracy: 0.001)
        XCTAssertEqual(last?.cumulative.firstDay, "2026-06-01")
        XCTAssertEqual(last?.schemaVersion, 2)
    }

    func testChargeCumulativeSurvivesAcrossFlushesNoDoubleCount() async {
        let spy = ChargeSpyStore()
        let coord = ChargeExposureCoordinator(store: spy, flushInterval: 0)
        await coord.record(percent: 90, isOnACPower: true, at: day1, calendar: cal)
        await coord.record(percent: 90, isOnACPower: true, at: day1.addingTimeInterval(4), calendar: cal)
        let day3 = day1.addingTimeInterval(2 * 86_400)
        await coord.flushNow(at: day3)
        await coord.flushNow(at: day3) // second flush, same data → no double-count
        XCTAssertEqual(spy.saved.last?.cumulative.secondsAbove80OnAC ?? -1, 4, accuracy: 0.001)
    }

    func testChargeBootstrapSeedsCumulative() async {
        let spy = ChargeSpyStore()
        spy.loadResult = ChargeExposureRecord(
            schemaVersion: 2,
            days: [],
            cumulative: CumulativeChargeExposure(firstDay: "2026-05-01", lastCountedDay: "2026-05-31",
                                                 secondsAbove80OnAC: 7200, secondsAbove95OnAC: 3600)
        )
        let coord = ChargeExposureCoordinator(store: spy, flushInterval: 0)
        await coord.bootstrap()
        let since = await coord.sinceInstall()
        XCTAssertEqual(since.secondsAbove80OnAC, 7200, accuracy: 0.001)
        XCTAssertEqual(since.firstDay, "2026-05-01")
    }

    func testThermalFlushAccumulatesAndPersists() async {
        let spy = ThermalSpyStore()
        let coord = ThermalExposureCoordinator(store: spy, flushInterval: 0)
        await coord.record(temperatureC: 42, at: day1, calendar: cal)
        await coord.record(temperatureC: 42, at: day1.addingTimeInterval(4), calendar: cal)
        let day3 = day1.addingTimeInterval(2 * 86_400)
        await coord.flushNow(at: day3)
        XCTAssertEqual(spy.saved.last?.cumulative.secondsAbove40 ?? -1, 4, accuracy: 0.001)
        XCTAssertEqual(spy.saved.last?.cumulative.firstDay, "2026-06-01")
        XCTAssertEqual(spy.saved.last?.schemaVersion, 3)
    }

    func testThermalBootstrapSeedsCumulative() async {
        let spy = ThermalSpyStore()
        spy.loadResult = ThermalExposureRecord(
            schemaVersion: 3,
            days: [],
            cumulative: CumulativeThermalExposure(firstDay: "2026-05-01", lastCountedDay: "2026-05-31",
                                                  secondsAbove40: 7200, secondsAbove45: 3600)
        )
        let coord = ThermalExposureCoordinator(store: spy, flushInterval: 0)
        await coord.bootstrap()
        let since = await coord.sinceInstall()
        XCTAssertEqual(since.secondsAbove40, 7200, accuracy: 0.001)
    }
}
