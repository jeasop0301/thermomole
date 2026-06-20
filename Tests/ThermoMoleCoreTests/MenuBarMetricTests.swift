import XCTest
@testable import ThermoMoleCore

final class MenuBarMetricTests: XCTestCase {
    func testDefaultsContainRequiredMetrics() {
        XCTAssertEqual(MenuBarMetric.defaultMetrics, [.cpuTemperature, .batteryTemperature, .memoryPercent])
    }

    func testSanitizesEmptySelection() {
        XCTAssertEqual(MenuBarMetric.sanitized([]), MenuBarMetric.defaultMetrics)
    }

    func testSanitizesDuplicateSelectionBeforeLimiting() {
        XCTAssertEqual(
            MenuBarMetric.sanitized([
                .cpuTemperature,
                .cpuTemperature,
                .batteryTemperature,
                .memoryPercent,
                .cpuTemperature,
                .cpuUsage
            ]),
            [.cpuTemperature, .batteryTemperature, .memoryPercent, .cpuUsage]
        )
    }

    func testStorageCodecNormalizesPersistedRawValues() {
        // Stale persisted values (diskActivity, networkActivity) are unknown → filtered by compactMap(init(rawValue:))
        let raw = [
            "cpuTemperature",
            "unknownMetric",
            "cpuTemperature",
            "batteryTemperature",
            "memoryPercent",
            "diskActivity",
            "networkActivity"
        ]

        XCTAssertEqual(
            MenuBarMetricStorage.decode(raw),
            [.cpuTemperature, .batteryTemperature, .memoryPercent]
        )
        XCTAssertEqual(
            MenuBarMetricStorage.normalizedRawValues(from: raw),
            ["cpuTemperature", "batteryTemperature", "memoryPercent"]
        )
        XCTAssertEqual(
            MenuBarMetricStorage.normalizedRawValues(from: ["unknownMetric"]),
            ["cpuTemperature", "batteryTemperature", "memoryPercent"]
        )
    }

    func testStorageCodecDetectsWhenPersistedPayloadNeedsRewrite() {
        XCTAssertTrue(MenuBarMetricStorage.needsRewrite(
            rawValues: ["cpuTemperature", "cpuTemperature", "unknownMetric"],
            normalizedMetrics: [.cpuTemperature]
        ))
        XCTAssertFalse(MenuBarMetricStorage.needsRewrite(
            rawValues: ["cpuTemperature", "batteryTemperature", "memoryPercent"],
            normalizedMetrics: [.cpuTemperature, .batteryTemperature, .memoryPercent]
        ))
    }

    func testMovesMetricEarlierAndLater() {
        let metrics: [MenuBarMetric] = [.cpuTemperature, .batteryTemperature, .memoryPercent]

        XCTAssertEqual(MenuBarMetric.move(.memoryPercent, in: metrics, direction: .up), [
            .cpuTemperature,
            .memoryPercent,
            .batteryTemperature
        ])
        XCTAssertEqual(MenuBarMetric.move(.cpuTemperature, in: metrics, direction: .down), [
            .batteryTemperature,
            .cpuTemperature,
            .memoryPercent
        ])
    }

    func testMoveKeepsEdgeItemsInPlace() {
        let metrics: [MenuBarMetric] = [.cpuTemperature, .batteryTemperature, .memoryPercent]

        XCTAssertEqual(MenuBarMetric.move(.cpuTemperature, in: metrics, direction: .up), metrics)
        XCTAssertEqual(MenuBarMetric.move(.memoryPercent, in: metrics, direction: .down), metrics)
    }

    func testMenuBarTitleFormatterReflectsSnapshotValues() {
        var snapshot = SystemSnapshot.placeholder
        snapshot.thermal.cpuDisplayC = 53.4
        snapshot.thermal.batteryDisplayC = 30.6
        snapshot.memory.usedPercent = 54

        let title = MenuBarTitleFormatter.title(
            for: snapshot,
            metrics: [.cpuTemperature, .batteryTemperature, .memoryPercent]
        )

        XCTAssertEqual(title, "CPU 53.4° · BAT 30.6° · RAM 54%")
    }

    func testMenuBarTitleFormatterKeepsSubDegreeTemperatureChangesVisible() {
        var first = SystemSnapshot.placeholder
        first.thermal.cpuDisplayC = 60.4
        first.thermal.batteryDisplayC = 30.6
        first.memory.usedPercent = 54

        var second = first
        second.thermal.cpuDisplayC = 60.5
        second.thermal.batteryDisplayC = 30.7

        let metrics: [MenuBarMetric] = [.cpuTemperature, .batteryTemperature, .memoryPercent]

        XCTAssertEqual(
            MenuBarTitleFormatter.title(for: first, metrics: metrics),
            "CPU 60.4° · BAT 30.6° · RAM 54%"
        )
        XCTAssertEqual(
            MenuBarTitleFormatter.title(for: second, metrics: metrics),
            "CPU 60.5° · BAT 30.7° · RAM 54%"
        )
    }

    func testMenuBarTitleFormatterReflectsMetricConfigurationImmediately() {
        var snapshot = SystemSnapshot.placeholder
        snapshot.cpu.usagePercent = 12.4
        snapshot.memory.usedPercent = 42

        let title = MenuBarTitleFormatter.title(
            for: snapshot,
            metrics: [.cpuUsage, .memoryPercent]
        )

        XCTAssertEqual(title, "CPU 12% · RAM 42%")
    }

    func testMenuBarPresentationBuildsTooltipAndAccessibilityLabel() {
        var snapshot = SystemSnapshot.placeholder
        snapshot.sampledAt = Date(timeIntervalSince1970: 1_725_000_000)
        snapshot.thermal.cpuDisplayC = 58.1
        snapshot.thermal.cpuTemperatureSource = .cpuDieHotspot
        snapshot.thermal.batteryDisplayC = 30.6
        snapshot.thermal.batteryTemperatureSource = .ioregTemperature
        snapshot.memory.usedPercent = 55
        snapshot.memory.pressure = .normal

        let presentation = MenuBarPresentation(
            snapshot: snapshot,
            metrics: [.cpuTemperature, .batteryTemperature, .memoryPercent],
            now: Date(timeIntervalSince1970: 1_725_000_004)
        )

        XCTAssertEqual(presentation.title, "CPU 58.1° · BAT 30.6° · RAM 55%")
        XCTAssertEqual(presentation.visibleTitle, "● CPU 58.1° · BAT 30.6° · RAM 55%")
        XCTAssertTrue(presentation.toolTip.contains("Patina"))
        XCTAssertTrue(presentation.toolTip.contains("CPU 58.1° · BAT 30.6° · RAM 55%"))
        XCTAssertTrue(presentation.toolTip.contains("Battery: Physical pack"))
        XCTAssertTrue(presentation.toolTip.contains("CPU: Die hotspot"))
        XCTAssertTrue(presentation.accessibilityLabel.contains("Patina status"))
        XCTAssertTrue(presentation.accessibilityLabel.contains("battery 30.6 degrees, physical pack"))
        XCTAssertTrue(presentation.accessibilityLabel.contains("memory 55 percent, normal pressure"))
    }

    func testMenuBarPresentationMarksStaleSnapshot() {
        var snapshot = SystemSnapshot.placeholder
        snapshot.sampledAt = Date(timeIntervalSince1970: 100)
        snapshot.thermal.cpuDisplayC = 58.1
        snapshot.thermal.batteryDisplayC = 30.6
        snapshot.memory.usedPercent = 55

        let presentation = MenuBarPresentation(
            snapshot: snapshot,
            metrics: [.cpuTemperature, .batteryTemperature, .memoryPercent],
            now: Date(timeIntervalSince1970: 135)
        )

        XCTAssertEqual(presentation.freshnessLevel, .stale)
        XCTAssertEqual(presentation.visibleTitle, "! CPU 58.1° · BAT 30.6° · RAM 55%")
        XCTAssertTrue(presentation.toolTip.contains("Freshness: Stale · 35s ago"))
        XCTAssertTrue(presentation.accessibilityLabel.contains("stale"))
    }
}
