import XCTest
@testable import ThermoMoleCore

final class StatusBriefTests: XCTestCase {
    func testStatusBriefDescribesCalmSystemWithPhysicalBatteryTemperature() {
        var snapshot = Self.snapshot(
            cpuTemperatureC: 52.4,
            batteryTemperatureC: 30.4,
            memoryUsedPercent: 54,
            memoryPressure: .normal
        )

        snapshot.health = HealthScore(value: 100, band: .excellent, issues: [])

        let brief = StatusBrief(snapshot: snapshot)

        XCTAssertEqual(brief.mood, .steady)
        XCTAssertEqual(brief.title, "Everything is steady")
        XCTAssertTrue(brief.detail.contains("30.4° battery"))
        XCTAssertEqual(brief.signals.map(\.title), ["Battery", "CPU", "Memory"])
        XCTAssertEqual(brief.signals.first?.value, "30.4°")
    }

    func testStatusBriefPrioritizesWarmBatteryWarning() {
        var snapshot = Self.snapshot(
            cpuTemperatureC: 61.2,
            batteryTemperatureC: 43.0,   // ≥ batteryCautionC(42) → caution
            memoryUsedPercent: 58,
            memoryPressure: .normal
        )

        snapshot.health = HealthScore(value: 91, band: .excellent, issues: [.batteryWarm])

        let brief = StatusBrief(snapshot: snapshot)

        XCTAssertEqual(brief.mood, .watch)
        XCTAssertEqual(brief.title, "Battery is warming")
        XCTAssertTrue(brief.detail.contains("\(Int(ThermalThresholds.batteryCautionC))° caution line"))
        XCTAssertEqual(brief.prioritySignal?.title, "Battery")
        XCTAssertEqual(brief.prioritySignal?.value, "43.0°")
    }

    func testStatusBriefPrioritizesCriticalMemoryPressure() {
        var snapshot = Self.snapshot(
            cpuTemperatureC: 64.0,
            batteryTemperatureC: 31.0,
            memoryUsedPercent: 92,
            memoryPressure: .critical
        )

        snapshot.health = HealthScore(value: 63, band: .fair, issues: [.highMemory])

        let brief = StatusBrief(snapshot: snapshot)

        XCTAssertEqual(brief.mood, .hot)
        XCTAssertEqual(brief.title, "Memory pressure is critical")
        XCTAssertTrue(brief.detail.contains("92%"))
        XCTAssertEqual(brief.prioritySignal?.title, "Memory")
    }

    private static func snapshot(
        cpuTemperatureC: Double,
        batteryTemperatureC: Double,
        memoryUsedPercent: Int,
        memoryPressure: MemoryPressure
    ) -> SystemSnapshot {
        var snapshot = SystemSnapshot.placeholder
        snapshot.cpu = CPUStatus(
            usagePercent: 12,
            perCorePercent: [],
            logicalCoreCount: 10,
            performanceCoreCount: 4,
            efficiencyCoreCount: 6,
            loadAverage: [1.0, 1.1, 1.2]
        )
        snapshot.memory = MemorySnapshot(
            usedBytes: UInt64(memoryUsedPercent) * 100,
            totalBytes: 10_000,
            usedPercent: memoryUsedPercent,
            pressure: memoryPressure,
            activeBytes: 0,
            wiredBytes: 0,
            compressedBytes: 0,
            freeBytes: 0
        )
        snapshot.thermal = ThermalSnapshot(
            cpuDisplayC: cpuTemperatureC,
            cpuTemperatureSource: .cpuDieHotspot,
            cpuDieHotspotC: cpuTemperatureC,
            cpuAverageC: cpuTemperatureC - 5,
            batteryDisplayC: batteryTemperatureC,
            batteryTemperatureSource: .ioregTemperature,
            batteryCellMaxC: batteryTemperatureC + 0.2,
            batteryIORegC: batteryTemperatureC,
            batteryWarningLevel: TemperatureWarningLevel.batteryLevel(for: batteryTemperatureC),
            hasBatterySensorMismatch: false
        )
        return snapshot
    }
}
