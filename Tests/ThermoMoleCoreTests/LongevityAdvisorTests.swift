import XCTest
@testable import ThermoMoleCore

final class LongevityAdvisorTests: XCTestCase {
    private func batteryExposure(min40: Double = 0, min45: Double = 0) -> ThermalExposureSummary {
        ThermalExposureSummary(today: DailyThermalExposure(day: "2026-06-17", secondsAbove40: min40 * 60, secondsAbove45: min45 * 60), recent: [])
    }
    private func cpuExposure(min85: Double = 0, min95: Double = 0) -> CPUExposureSummary {
        CPUExposureSummary(today: DailyCPUExposure(day: "2026-06-17", secondsAbove85: min85 * 60, secondsAbove95: min95 * 60), recent: [])
    }
    private func chargeExposure(min80: Double = 0, min95: Double = 0) -> ChargeExposureSummary {
        ChargeExposureSummary(today: DailyChargeExposure(day: "2026-06-17", secondsAbove80OnAC: min80 * 60, secondsAbove95OnAC: min95 * 60), recent: [])
    }

    private func pristine() -> LongevitySignals {
        LongevitySignals(
            batteryLongevity: BatteryLongevityReport(score: 100, healthPercent: 100, cycleCount: 5, healthDropPerWeek: nil, cyclesPerWeek: nil, projectedMonthsTo80: nil, alerts: []),
            batteryExposure: batteryExposure(),
            cpuExposure: cpuExposure(),
            chargeExposure: chargeExposure(),
            diskFreePercent: 45,
            diskUsedPercent: 55,
            memoryPressure: "normal",
            isChargingWhileHot: false,
            batteryTempC: 30,
            ssdTempC: 35
        )
    }

    func testPristineScoresHighAllGoodNoUrgent() {
        let a = LongevityAdvisor.assess(pristine())
        XCTAssertGreaterThanOrEqual(a.score, 90)
        XCTAssertTrue(a.factors.allSatisfy { $0.status == .good })
        XCTAssertFalse(a.actions.contains { $0.severity == .urgent })
    }

    func testChargingWhileHotRaisesUrgentHeatAction() {
        var s = pristine()
        s.isChargingWhileHot = true
        let a = LongevityAdvisor.assess(s)
        XCTAssertTrue(a.actions.contains { $0.severity == .urgent })
        XCTAssertEqual(a.factors.first { $0.id == "heat" }?.status, .poor)
    }

    func testLowDiskFreeRaisesStoragePoorAndUrgentAction() {
        var s = pristine()
        s.diskFreePercent = 5
        s.diskUsedPercent = 95
        let a = LongevityAdvisor.assess(s)
        XCTAssertEqual(a.factors.first { $0.id == "storage" }?.status, .poor)
        XCTAssertTrue(a.actions.contains { $0.id == "free-storage" && $0.severity == .urgent })
    }

    func testBatteryFastFadeLowersScoreAndFlagsBattery() {
        var s = pristine()
        s.batteryLongevity = BatteryLongevityReport(score: 60, healthPercent: 82, cycleCount: 400, healthDropPerWeek: 7, cyclesPerWeek: 5, projectedMonthsTo80: 1, alerts: [.fastFade])
        let a = LongevityAdvisor.assess(s)
        XCTAssertLessThan(a.score, LongevityAdvisor.assess(pristine()).score)
        XCTAssertEqual(a.factors.first { $0.id == "battery" }?.status, .poor)
        XCTAssertTrue(a.actions.contains { $0.id == "battery-fade" })
    }

    func testCriticalMemoryFlagsMemory() {
        var s = pristine()
        s.memoryPressure = "critical"
        let a = LongevityAdvisor.assess(s)
        XCTAssertNotEqual(a.factors.first { $0.id == "memory" }?.status, .good)
    }

    func testSustainedHighSoCOnACSuggestsUnplug() {
        var s = pristine()
        s.chargeExposure = chargeExposure(min80: 300, min95: 180) // 5h / 3h
        let a = LongevityAdvisor.assess(s)
        XCTAssertTrue(a.actions.contains { $0.id == "high-soc" })
        XCTAssertNotEqual(a.factors.first { $0.id == "charging" }?.status, .good)
    }

    func testActionsSortedBySeverityDescending() {
        var s = pristine()
        s.isChargingWhileHot = true       // urgent
        s.chargeExposure = chargeExposure(min80: 300, min95: 180) // suggest
        let a = LongevityAdvisor.assess(s)
        let sev = a.actions.map { $0.severity.rawValue }
        XCTAssertEqual(sev, sev.sorted(by: >))
    }

    func testHasFiveFactors() {
        let a = LongevityAdvisor.assess(pristine())
        XCTAssertEqual(Set(a.factors.map { $0.id }), ["battery", "heat", "charging", "storage", "memory"])
    }
}
