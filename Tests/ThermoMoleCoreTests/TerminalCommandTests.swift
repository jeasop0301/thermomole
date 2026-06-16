import XCTest
@testable import ThermoMoleCore

final class TerminalCommandTests: XCTestCase {
    func testTerminalCommandParserDefaultsToStatus() throws {
        XCTAssertEqual(try TerminalCommandParser.parse([]), .status)
        XCTAssertEqual(try TerminalCommandParser.parse(["status"]), .status)
    }

    func testTerminalCommandParserKeepsCleanAndOptimizeOneClickByDefault() throws {
        XCTAssertEqual(try TerminalCommandParser.parse(["clean"]), .clean(mode: .plan))
        XCTAssertEqual(try TerminalCommandParser.parse(["clean", "--execute"]), .clean(mode: .execute))
        XCTAssertEqual(try TerminalCommandParser.parse(["optimize"]), .optimize(mode: .plan))
        XCTAssertEqual(try TerminalCommandParser.parse(["optimize", "--execute"]), .optimize(mode: .execute))
        XCTAssertEqual(try TerminalCommandParser.parse(["installer"]), .installer(mode: .plan))
        XCTAssertEqual(try TerminalCommandParser.parse(["installer", "--execute"]), .installer(mode: .execute))
    }

    func testTerminalCommandParserSupportsGlobalJSONOutputMode() throws {
        XCTAssertEqual(
            try TerminalCommandParser.parseRequest(["status", "--json"]),
            TerminalCommandRequest(command: .status, outputFormat: .json)
        )
        XCTAssertEqual(
            try TerminalCommandParser.parseRequest(["clean", "--execute", "--json"]),
            TerminalCommandRequest(command: .clean(mode: .execute), outputFormat: .json)
        )
        XCTAssertEqual(
            try TerminalCommandParser.parseRequest(["installer", "--json", "--execute"]),
            TerminalCommandRequest(command: .installer(mode: .execute), outputFormat: .json)
        )
        XCTAssertEqual(
            try TerminalCommandParser.parseRequest(["uninstall", "ChatGPT", "--json", "--execute"]),
            TerminalCommandRequest(command: .uninstall(query: "ChatGPT", mode: .execute), outputFormat: .json)
        )
    }

    func testTerminalCommandParserSupportsUninstallQueryAndMode() throws {
        XCTAssertEqual(
            try TerminalCommandParser.parse(["uninstall", "ChatGPT"]),
            .uninstall(query: "ChatGPT", mode: .plan)
        )
        XCTAssertEqual(
            try TerminalCommandParser.parse(["uninstall", "Visual", "Studio", "Code", "--execute"]),
            .uninstall(query: "Visual Studio Code", mode: .execute)
        )
        XCTAssertThrowsError(try TerminalCommandParser.parse(["uninstall"])) { error in
            XCTAssertEqual(error as? TerminalCommandError, .missingArgument("uninstall <app name>"))
        }
    }

    func testTerminalCommandParserSupportsMemoryResearchCommand() throws {
        XCTAssertEqual(try TerminalCommandParser.parse(["memory"]), .memory)
        XCTAssertEqual(try TerminalCommandParser.parse(["memory", "--purge"]), .memoryPurge(mode: .plan))
        XCTAssertEqual(try TerminalCommandParser.parse(["memory", "--purge", "--execute"]), .memoryPurge(mode: .execute))
    }

    func testTerminalCommandParserRejectsUnknownCommands() {
        XCTAssertThrowsError(try TerminalCommandParser.parse(["unknown"])) { error in
            XCTAssertEqual(error as? TerminalCommandError, .unknownCommand("unknown"))
        }
    }

    func testTerminalFormatterRendersStatusWithFreshnessAndSensorSources() {
        var snapshot = SystemSnapshot.placeholder
        snapshot.sampledAt = Date(timeIntervalSince1970: 100)
        snapshot.thermal = ThermalSnapshot(
            cpuDisplayC: 58.1,
            cpuTemperatureSource: .cpuDieHotspot,
            cpuDieHotspotC: 58.1,
            cpuAverageC: 49.3,
            batteryDisplayC: 30.6,
            batteryTemperatureSource: .ioregTemperature,
            batteryCellMaxC: 42.1,
            batteryIORegC: 30.6,
            batteryWarningLevel: .normal,
            hasBatterySensorMismatch: true
        )
        snapshot.memory.usedPercent = 55
        snapshot.memory.pressure = .normal
        snapshot.health = HealthScore(value: 91, band: .excellent, issues: [])

        let output = TerminalOutputFormatter.status(
            snapshot,
            now: Date(timeIntervalSince1970: 104)
        )

        XCTAssertTrue(output.contains("Status"))
        XCTAssertTrue(output.contains("Live · 4s ago"))
        XCTAssertTrue(output.contains("CPU 58.1° · Die hotspot"))
        XCTAssertTrue(output.contains("Battery 30.6° · Physical pack"))
        XCTAssertTrue(output.contains("RAM 55% · Normal"))
        XCTAssertTrue(output.contains("Health 91 · Excellent"))
        XCTAssertTrue(output.contains("AppleSmartBattery 30.6°"))
        XCTAssertTrue(output.contains("SMC TB max 42.1°"))
    }

    func testTerminalFormatterRendersStatusTrustFieldsAsJSON() throws {
        var snapshot = SystemSnapshot.placeholder
        snapshot.sampledAt = Date(timeIntervalSince1970: 100)
        snapshot.thermal = ThermalSnapshot(
            cpuDisplayC: 58.1,
            cpuTemperatureSource: .cpuDieHotspot,
            cpuDieHotspotC: 58.1,
            cpuAverageC: 49.3,
            batteryDisplayC: 30.6,
            batteryTemperatureSource: .ioregTemperature,
            batteryCellMaxC: 42.1,
            batteryIORegC: 30.6,
            batteryWarningLevel: .normal,
            hasBatterySensorMismatch: true
        )

        let output = try TerminalOutputFormatter.jsonStatus(
            snapshot,
            now: Date(timeIntervalSince1970: 135)
        )
        let object = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]

        XCTAssertEqual(object?["command"] as? String, "status")
        XCTAssertEqual(object?["freshnessLevel"] as? String, "stale")
        XCTAssertEqual(object?["freshnessDetail"] as? String, "35s ago")
        XCTAssertEqual(object?["cpuTemperatureSource"] as? String, "cpuDieHotspot")
        XCTAssertEqual(object?["batteryTemperatureSource"] as? String, "ioregTemperature")
        XCTAssertEqual(object?["batterySensorMismatch"] as? Bool, true)
        XCTAssertEqual(object?["batteryIORegTemperatureC"] as? Double, 30.6)
        XCTAssertEqual(object?["batteryCellMaxTemperatureC"] as? Double, 42.1)
        XCTAssertEqual(object?["cpuDieHotspotTemperatureC"] as? Double, 58.1)
        XCTAssertEqual(object?["cpuAverageTemperatureC"] as? Double, 49.3)
    }

    func testTerminalFormatterSummarizesSmartCleanPlanWithoutSelectionPrompts() {
        let root = URL(fileURLWithPath: "/tmp/thermomole-tests", isDirectory: true)
        let result = CleanupScanResult(items: [
            CleanupItem(category: .appCaches, url: root.appendingPathComponent("cache"), sizeBytes: 128, isPreselected: true),
            CleanupItem(category: .logs, url: root.appendingPathComponent("log"), sizeBytes: 256, isPreselected: true)
        ], skipped: ["/System"])
        let output = TerminalOutputFormatter.smartCleanPlan(SmartCleanupReviewPlan(result))

        XCTAssertTrue(output.contains("Smart Clean"))
        XCTAssertTrue(output.contains("2 items"))
        XCTAssertTrue(output.contains("384 B"))
        XCTAssertTrue(output.contains("1 skipped"))
        XCTAssertFalse(output.localizedCaseInsensitiveContains("select"))
    }

    func testTerminalFormatterRendersSmartCleanPlanAsJSON() throws {
        let root = URL(fileURLWithPath: "/tmp/thermomole-tests", isDirectory: true)
        let result = CleanupScanResult(items: [
            CleanupItem(category: .appCaches, url: root.appendingPathComponent("cache"), sizeBytes: 128, isPreselected: true)
        ], skipped: ["/System"])
        let output = try TerminalOutputFormatter.jsonSmartCleanPlan(SmartCleanupReviewPlan(result))
        let object = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]

        XCTAssertEqual(object?["command"] as? String, "clean")
        XCTAssertEqual(object?["selectedItemCount"] as? Int, 1)
        XCTAssertEqual(object?["selectedBytes"] as? Int, 128)
        XCTAssertEqual(object?["skippedCount"] as? Int, 1)
    }

    func testTerminalFormatterSummarizesDefaultOptimizeBatch() {
        let batch = OptimizeBatchPlan.defaultMaintenance(tasks: [.quickLook, .savedApplicationState])
        let output = TerminalOutputFormatter.optimizeBatch(batch)

        XCTAssertTrue(output.contains("Default Optimize"))
        XCTAssertTrue(output.contains("1 runnable"))
        XCTAssertTrue(output.contains("1 staged"))
        XCTAssertTrue(output.contains("Rebuild Quick Look"))
    }

    func testTerminalFormatterRendersHistoryAsJSON() throws {
        let entry = OperationHistoryEntry(
            kind: .installer,
            title: "Installer Cleanup",
            status: .succeeded,
            itemCount: 2,
            bytes: 384,
            message: "2 moved",
            executedAt: Date(timeIntervalSince1970: 100)
        )
        let output = try TerminalOutputFormatter.jsonHistory([entry])
        let object = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]
        let entries = object?["entries"] as? [[String: Any]]

        XCTAssertEqual(object?["command"] as? String, "history")
        XCTAssertEqual(entries?.first?["title"] as? String, "Installer Cleanup")
        XCTAssertEqual(entries?.first?["bytes"] as? Int, 384)
    }

    func testTerminalFormatterSummarizesInstallerCleanupWithoutSelectionPrompts() {
        let root = URL(fileURLWithPath: "/tmp/thermomole-tests", isDirectory: true)
        let result = CleanupScanResult(items: [
            CleanupItem(category: .installers, url: root.appendingPathComponent("App.dmg"), sizeBytes: 128, isPreselected: true),
            CleanupItem(category: .installers, url: root.appendingPathComponent("Tool.pkg"), sizeBytes: 256, isPreselected: true)
        ], skipped: [])
        let output = TerminalOutputFormatter.installerPlan(SmartCleanupReviewPlan(result))

        XCTAssertTrue(output.contains("Installer Cleanup"))
        XCTAssertTrue(output.contains("2 files"))
        XCTAssertTrue(output.contains("384 B"))
        XCTAssertTrue(output.contains("installer --execute"))
        XCTAssertFalse(output.localizedCaseInsensitiveContains("select"))
    }

    func testDiskAnalysisSummaryHighlightsLargestEntriesWithoutPromptingForChoices() {
        let root = URL(fileURLWithPath: "/tmp/thermomole-tests", isDirectory: true)
        let summary = DiskAnalysisSummary(
            scopeURL: root,
            entries: [
                DiskEntry(url: root.appendingPathComponent("Big"), sizeBytes: 900, isDirectory: true),
                DiskEntry(url: root.appendingPathComponent("Small"), sizeBytes: 100, isDirectory: false)
            ]
        )
        let output = TerminalOutputFormatter.diskAnalysis(summary)

        XCTAssertEqual(summary.entryCount, 2)
        XCTAssertEqual(summary.totalBytes, 1_000)
        XCTAssertEqual(summary.largestEntry?.url.lastPathComponent, "Big")
        XCTAssertTrue(output.contains("Analyze"))
        XCTAssertTrue(output.contains("2 entries"))
        XCTAssertTrue(output.contains("1000 B"))
        XCTAssertTrue(output.contains("Big"))
        XCTAssertFalse(output.localizedCaseInsensitiveContains("choose"))
    }

    func testSoftwareSummaryHighlightsAppsStartupItemsAndCandidates() {
        let apps = [
            InstalledApp(name: "Example", bundleIdentifier: "com.example.app", bundlePath: "/Applications/Example.app", version: "1.0", build: "1"),
            InstalledApp(name: "Old Tool", bundleIdentifier: "com.example.old", bundlePath: "/Applications/Old Tool.app", version: "unknown", build: "unknown")
        ]
        let startupItems = [
            StartupItem(label: "com.example.enabled", program: "/bin/true", domain: .userLaunchAgent, isEnabled: true, plistPath: "/tmp/enabled.plist"),
            StartupItem(label: "com.example.disabled", program: "/bin/false", domain: .userLaunchAgent, isEnabled: false, plistPath: "/tmp/disabled.plist")
        ]

        let summary = SoftwareSummary(apps: apps, startupItems: startupItems)
        let output = TerminalOutputFormatter.software(summary)

        XCTAssertEqual(summary.appCount, 2)
        XCTAssertEqual(summary.startupItemCount, 2)
        XCTAssertEqual(summary.enabledStartupItemCount, 1)
        XCTAssertEqual(summary.uninstallCandidateCount, 1)
        XCTAssertTrue(output.contains("Software"))
        XCTAssertTrue(output.contains("2 apps"))
        XCTAssertTrue(output.contains("1 enabled startup"))
        XCTAssertTrue(output.contains("1 uninstall candidate"))
        XCTAssertFalse(output.localizedCaseInsensitiveContains("select"))
    }

    func testTerminalFormatterSummarizesUninstallPlanWithoutSelectionPrompts() throws {
        let apps = [
            InstalledApp(name: "ChatGPT", bundleIdentifier: "com.openai.chat", bundlePath: "/Applications/ChatGPT.app", version: "1.2026.153", build: "153"),
            InstalledApp(name: "ChatGPT Beta", bundleIdentifier: "com.openai.chat.beta", bundlePath: "/Applications/ChatGPT Beta.app", version: "1.0", build: "1")
        ]
        let plan = AppUninstallPlan(query: "ChatGPT", apps: apps)
        let output = TerminalOutputFormatter.appUninstallPlan(plan)

        XCTAssertEqual(plan.status, .ready)
        XCTAssertEqual(plan.selectedApp?.name, "ChatGPT")
        XCTAssertTrue(output.contains("Uninstall"))
        XCTAssertTrue(output.contains("ChatGPT"))
        XCTAssertTrue(output.contains("uninstall \"ChatGPT\" --execute"))
        XCTAssertFalse(output.localizedCaseInsensitiveContains("select"))

        let json = try TerminalOutputFormatter.jsonAppUninstallPlan(plan)
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        XCTAssertEqual(object?["command"] as? String, "uninstall")
        XCTAssertEqual(object?["query"] as? String, "ChatGPT")
        XCTAssertEqual(object?["status"] as? String, "ready")
        XCTAssertEqual(object?["canExecute"] as? Bool, true)
    }
}
