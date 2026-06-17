import XCTest
@testable import ThermoMoleCore

final class NotificationPolicyTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func at(_ hour: Int) -> Date {
        cal.date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 6, day: 17, hour: hour, minute: 0))!
    }

    func testNeverSentIsDue() {
        let due = NotificationPolicy.due(active: [.chargingWhileHot], lastSent: [:], now: at(12), calendar: cal)
        XCTAssertEqual(due, [.chargingWhileHot])
    }

    func testWithinThrottleIsSuppressed() {
        let due = NotificationPolicy.due(
            active: [.chargingWhileHot],
            lastSent: [.chargingWhileHot: at(11)],
            now: at(12),
            calendar: cal
        )
        XCTAssertTrue(due.isEmpty) // 1h < 2h throttle
    }

    func testBeyondThrottleIsDueAgain() {
        let due = NotificationPolicy.due(
            active: [.chargingWhileHot],
            lastSent: [.chargingWhileHot: at(9)],
            now: at(12),
            calendar: cal
        )
        XCTAssertEqual(due, [.chargingWhileHot]) // 3h >= 2h
    }

    func testQuietHoursSuppressAll() {
        let due = NotificationPolicy.due(
            active: [.chargingWhileHot, .lowStorage],
            lastSent: [:],
            now: at(2),
            quietHours: QuietHours(startHour: 22, endHour: 7),
            calendar: cal
        )
        XCTAssertTrue(due.isEmpty)
    }

    func testOutsideQuietHoursAllowed() {
        let due = NotificationPolicy.due(
            active: [.chargingWhileHot],
            lastSent: [:],
            now: at(12),
            quietHours: QuietHours(startHour: 22, endHour: 7),
            calendar: cal
        )
        XCTAssertEqual(due, [.chargingWhileHot])
    }

    func testMultipleActiveReturnedDeterministically() {
        let due = NotificationPolicy.due(
            active: [.lowStorage, .chargingWhileHot, .highSoCDwell],
            lastSent: [:],
            now: at(12),
            calendar: cal
        )
        XCTAssertEqual(due, due.sorted { $0.rawValue < $1.rawValue })
        XCTAssertEqual(due.count, 3)
    }

    func testQuietHoursWrapAroundMidnight() {
        let qh = QuietHours(startHour: 22, endHour: 7)
        XCTAssertTrue(qh.contains(hour: 23))
        XCTAssertTrue(qh.contains(hour: 3))
        XCTAssertFalse(qh.contains(hour: 7))
        XCTAssertFalse(qh.contains(hour: 12))
    }

    // MARK: - activeNotifications

    func testActiveSustainedHotCPUAtThreshold() {
        var cpu = CPUExposureSummary.empty
        cpu.today.secondsAbove95 = 30 * 60
        let active = NotificationPolicy.activeNotifications(
            snapshot: .placeholder, todayChargeExposure: .empty, todayCPUExposure: cpu, batteryLongevity: nil
        )
        XCTAssertTrue(active.contains(.sustainedHotCPU))
    }

    func testActiveSustainedHotCPUBelowThreshold() {
        var cpu = CPUExposureSummary.empty
        cpu.today.secondsAbove95 = 30 * 60 - 1
        let active = NotificationPolicy.activeNotifications(
            snapshot: .placeholder, todayChargeExposure: .empty, todayCPUExposure: cpu, batteryLongevity: nil
        )
        XCTAssertFalse(active.contains(.sustainedHotCPU))
    }

    func testActiveHighCycleRateFromLongevityAlert() {
        let report = BatteryLongevityReport(
            score: 80, healthPercent: 90, cycleCount: 100,
            healthDropPerWeek: nil, cyclesPerWeek: 16, projectedMonthsTo80: nil,
            alerts: [.highCycleRate]
        )
        let active = NotificationPolicy.activeNotifications(
            snapshot: .placeholder, todayChargeExposure: .empty, todayCPUExposure: .empty, batteryLongevity: report
        )
        XCTAssertTrue(active.contains(.highCycleRate))
    }

    func testActiveNoHighCycleRateWithoutAlert() {
        let report = BatteryLongevityReport(
            score: 95, healthPercent: 98, cycleCount: 20,
            healthDropPerWeek: nil, cyclesPerWeek: 3, projectedMonthsTo80: nil,
            alerts: []
        )
        let active = NotificationPolicy.activeNotifications(
            snapshot: .placeholder, todayChargeExposure: .empty, todayCPUExposure: .empty, batteryLongevity: report
        )
        XCTAssertFalse(active.contains(.highCycleRate))
    }

    func testActiveLowStorageWhenNearlyFull() {
        var snap = SystemSnapshot.placeholder
        snap.disk.usedPercent = 95
        let active = NotificationPolicy.activeNotifications(
            snapshot: snap, todayChargeExposure: .empty, todayCPUExposure: .empty, batteryLongevity: nil
        )
        XCTAssertTrue(active.contains(.lowStorage))
    }
}
