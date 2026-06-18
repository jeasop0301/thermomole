import XCTest
@testable import ThermoMoleCore

final class HealthScoreTests: XCTestCase {
    func testExcellentForCoolSystem() {
        let score = HealthScorer.score(
            cpuUsagePercent: 12,
            memoryUsedPercent: 42,
            diskUsedPercent: 40,
            batteryTemperatureC: 31,
            uptimeSeconds: 1_800
        )

        XCTAssertEqual(score.value, 100)
        XCTAssertEqual(score.band, .excellent)
        XCTAssertTrue(score.issues.isEmpty)
    }

    // batteryCautionC is now 42; 36° is below → no battery penalty
    func testBelowNewCautionThresholdNoWarning() {
        let score = HealthScorer.score(
            cpuUsagePercent: 15,
            memoryUsedPercent: 40,
            diskUsedPercent: 50,
            batteryTemperatureC: 36,
            uptimeSeconds: 1_800
        )

        XCTAssertFalse(score.issues.contains(.batteryWarm))
        XCTAssertFalse(score.issues.contains(.batteryHot))
    }

    // 43° ≥ batteryCautionC (42) → batteryWarm
    func testWarnsAtFortyThreeDegrees() {
        let score = HealthScorer.score(
            cpuUsagePercent: 15,
            memoryUsedPercent: 40,
            diskUsedPercent: 50,
            batteryTemperatureC: ThermalThresholds.batteryCautionC,
            uptimeSeconds: 1_800
        )

        XCTAssertLessThan(score.value, 100)
        XCTAssertTrue(score.issues.contains(.batteryWarm))
    }

    // 49° ≥ batteryHotC (48) → batteryHot
    func testHotAtFortyNineDegrees() {
        let score = HealthScorer.score(
            cpuUsagePercent: 15,
            memoryUsedPercent: 40,
            diskUsedPercent: 50,
            batteryTemperatureC: ThermalThresholds.batteryHotC,
            uptimeSeconds: 1_800
        )

        XCTAssertTrue(score.issues.contains(.batteryHot))
        XCTAssertNotEqual(score.band, .excellent)
    }

    func testCPUHotspotReducesHealthScore() {
        let score = HealthScorer.score(
            cpuUsagePercent: 15,
            memoryUsedPercent: 40,
            diskUsedPercent: 50,
            batteryTemperatureC: 31,
            cpuTemperatureC: 95,
            uptimeSeconds: 1_800
        )

        XCTAssertTrue(score.issues.contains(.cpuHot))
        XCTAssertNotEqual(score.band, .excellent)
    }
}
