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

    func testWarnsAtThirtyFiveDegrees() {
        let score = HealthScorer.score(
            cpuUsagePercent: 15,
            memoryUsedPercent: 40,
            diskUsedPercent: 50,
            batteryTemperatureC: 35.0,
            uptimeSeconds: 1_800
        )

        XCTAssertLessThan(score.value, 100)
        XCTAssertTrue(score.issues.contains(.batteryWarm))
    }

    func testHotAtFortyDegrees() {
        let score = HealthScorer.score(
            cpuUsagePercent: 15,
            memoryUsedPercent: 40,
            diskUsedPercent: 50,
            batteryTemperatureC: 40.0,
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
