import XCTest
@testable import ThermoMoleCore

final class StatusHistoryTests: XCTestCase {
    func testHistoryTrimsOldestSamplesAtLimit() {
        var history = BoundedStatusHistory(limit: 3)

        history.append(StatusHistorySample(sampledAt: Date(timeIntervalSince1970: 1), cpuTemperatureC: 41, batteryTemperatureC: 31, memoryPercent: 40, cpuUsagePercent: 10))
        history.append(StatusHistorySample(sampledAt: Date(timeIntervalSince1970: 2), cpuTemperatureC: 42, batteryTemperatureC: 32, memoryPercent: 50, cpuUsagePercent: 20))
        history.append(StatusHistorySample(sampledAt: Date(timeIntervalSince1970: 3), cpuTemperatureC: 43, batteryTemperatureC: 33, memoryPercent: 60, cpuUsagePercent: 30))
        history.append(StatusHistorySample(sampledAt: Date(timeIntervalSince1970: 4), cpuTemperatureC: 44, batteryTemperatureC: 34, memoryPercent: 70, cpuUsagePercent: 40))

        XCTAssertEqual(history.samples.map(\.sampledAt.timeIntervalSince1970), [2, 3, 4])
        XCTAssertEqual(history.cpuTemperatureSeries, [42, 43, 44])
        XCTAssertEqual(history.batteryTemperatureSeries, [32, 33, 34])
        XCTAssertEqual(history.memoryPercentSeries, [50, 60, 70])
    }

    func testHistoryCanAppendSystemSnapshots() {
        var snapshot = SystemSnapshot.placeholder
        snapshot.sampledAt = Date(timeIntervalSince1970: 99)
        snapshot.thermal.cpuDisplayC = 45.5
        snapshot.thermal.batteryDisplayC = 31.5
        snapshot.memory.usedPercent = 63
        snapshot.cpu.usagePercent = 12.4

        var history = BoundedStatusHistory(limit: 10)
        history.append(snapshot)

        XCTAssertEqual(history.samples, [
            StatusHistorySample(sampledAt: Date(timeIntervalSince1970: 99), cpuTemperatureC: 45.5, batteryTemperatureC: 31.5, memoryPercent: 63, cpuUsagePercent: 12.4)
        ])
    }
}
