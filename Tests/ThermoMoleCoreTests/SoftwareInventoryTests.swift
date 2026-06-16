import Foundation
import XCTest
@testable import ThermoMoleCore

final class SoftwareInventoryTests: XCTestCase {
    func testStartupItemParsesLaunchAgentPlist() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let agents = root.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let plist = agents.appendingPathComponent("com.example.agent.plist")
        let data: [String: Any] = [
            "Label": "com.example.agent",
            "Program": "/Applications/Example.app/Contents/MacOS/Example",
            "RunAtLoad": true
        ]
        try (data as NSDictionary).write(to: plist)

        let inventory = SoftwareInventory(homeDirectory: root, appRoots: [], startupRoots: [agents])
        let items = inventory.startupItems()

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.label, "com.example.agent")
        XCTAssertEqual(items.first?.program, "/Applications/Example.app/Contents/MacOS/Example")
        XCTAssertEqual(items.first?.domain, .userLaunchAgent)
        XCTAssertTrue(items.first?.isEnabled ?? false)
    }

    func testSoftwareInventoryReadsAppVersions() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Example.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = contents.appendingPathComponent("Info.plist")
        let data: [String: Any] = [
            "CFBundleName": "Example",
            "CFBundleIdentifier": "com.example.app",
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "45"
        ]
        try (data as NSDictionary).write(to: plist)

        let inventory = SoftwareInventory(homeDirectory: root, appRoots: [root], startupRoots: [])
        let apps = inventory.installedApps()

        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps.first?.name, "Example")
        XCTAssertEqual(apps.first?.version, "1.2.3")
        XCTAssertEqual(apps.first?.build, "45")
    }

    func testSoftwareInventoryFilterMatchesAppsAcrossNameIdentifierVersionAndPath() {
        let apps = [
            InstalledApp(
                name: "ChatGPT",
                bundleIdentifier: "com.openai.chat",
                bundlePath: "/Applications/ChatGPT.app",
                version: "1.2026.153",
                build: "153"
            ),
            InstalledApp(
                name: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode",
                bundlePath: "/Applications/Xcode.app",
                version: "26.4.1",
                build: "26E1"
            )
        ]

        XCTAssertEqual(SoftwareInventoryFilter(query: "openai").filter(apps).map(\.name), ["ChatGPT"])
        XCTAssertEqual(SoftwareInventoryFilter(query: "26.4").filter(apps).map(\.name), ["Xcode"])
        XCTAssertEqual(SoftwareInventoryFilter(query: "/applications/chatgpt").filter(apps).map(\.name), ["ChatGPT"])
        XCTAssertEqual(SoftwareInventoryFilter(query: "  ").filter(apps).map(\.name), ["ChatGPT", "Xcode"])
    }

    func testSoftwareInventoryFilterMatchesStartupItemsAcrossLabelProgramDomainAndPath() {
        let items = [
            StartupItem(
                label: "com.openai.chat.helper",
                program: "/Applications/ChatGPT.app/Contents/MacOS/helper",
                domain: .userLaunchAgent,
                isEnabled: true,
                plistPath: "/Users/test/Library/LaunchAgents/com.openai.chat.helper.plist"
            ),
            StartupItem(
                label: "com.example.daemon",
                program: "/usr/local/bin/exampled",
                domain: .localLaunchDaemon,
                isEnabled: false,
                plistPath: "/Library/LaunchDaemons/com.example.daemon.plist"
            )
        ]

        XCTAssertEqual(SoftwareInventoryFilter(query: "chatgpt").filter(items).map(\.label), ["com.openai.chat.helper"])
        XCTAssertEqual(SoftwareInventoryFilter(query: "launchdaemon").filter(items).map(\.label), ["com.example.daemon"])
        XCTAssertEqual(SoftwareInventoryFilter(query: "disabled").filter(items).map(\.label), ["com.example.daemon"])
        XCTAssertEqual(SoftwareInventoryFilter(query: "").filter(items).map(\.label), ["com.openai.chat.helper", "com.example.daemon"])
    }

    func testAppUninstallExecutorMovesAppBundleToTrash() throws {
        // Resolve symlinks up front so /var vs /private/var does not defeat the app-root check.
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .resolvingSymlinksInPath()
        let appsDir = root.appendingPathComponent("Applications", isDirectory: true)
        let trash = root.appendingPathComponent("Trash", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let appURL = appsDir.appendingPathComponent("Example.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        let app = InstalledApp(name: "Example", bundleIdentifier: "com.example.app", bundlePath: appURL.path, version: "1.0", build: "1")
        let executor = AppUninstallExecutor(validator: ProtectedPathValidator(homeDirectory: root)) { url in
            let destination = trash.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }

        let result = executor.moveToTrash(app)

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: appURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.appendingPathComponent("Example.app").path))
    }

    func testAppUninstallPlanRequiresSingleSafeMatch() {
        let apps = [
            InstalledApp(name: "ChatGPT", bundleIdentifier: "com.openai.chat", bundlePath: "/Applications/ChatGPT.app", version: "1.0", build: "1"),
            InstalledApp(name: "ChatGPT Beta", bundleIdentifier: "com.openai.chat.beta", bundlePath: "/Applications/ChatGPT Beta.app", version: "1.0", build: "1"),
            InstalledApp(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", bundlePath: "/Applications/Xcode.app", version: "26.4.1", build: "26E1")
        ]

        let exact = AppUninstallPlan(query: "ChatGPT", apps: apps)
        XCTAssertEqual(exact.status, .ready)
        XCTAssertTrue(exact.canExecute)
        XCTAssertEqual(exact.selectedApp?.bundleIdentifier, "com.openai.chat")

        let ambiguous = AppUninstallPlan(query: "chat", apps: apps)
        XCTAssertEqual(ambiguous.status, .ambiguous)
        XCTAssertFalse(ambiguous.canExecute)
        XCTAssertNil(ambiguous.selectedApp)

        let missing = AppUninstallPlan(query: "  ", apps: apps)
        XCTAssertEqual(missing.status, .missingQuery)
        XCTAssertFalse(missing.canExecute)

        let notFound = AppUninstallPlan(query: "Definitely Missing", apps: apps)
        XCTAssertEqual(notFound.status, .notFound)
        XCTAssertFalse(notFound.canExecute)
    }

    func testAppUninstallConfirmationSummaryDescribesSystemAppRisk() {
        let app = InstalledApp(
            name: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            bundlePath: "/Applications/Xcode.app",
            version: "26.4.1",
            build: "26E1"
        )

        let summary = AppUninstallConfirmationSummary(app: app)

        XCTAssertEqual(summary.title, "Move Xcode to Trash?")
        XCTAssertEqual(summary.appName, "Xcode")
        XCTAssertEqual(summary.versionLine, "Version: 26.4.1 (26E1)")
        XCTAssertTrue(summary.requiresAdministratorApproval)
        XCTAssertTrue(summary.confirmationMessage.contains("Bundle ID: com.apple.dt.Xcode"))
        XCTAssertTrue(summary.confirmationMessage.contains("Version: 26.4.1 (26E1)"))
        XCTAssertTrue(summary.confirmationMessage.contains("Path: /Applications/Xcode.app"))
        XCTAssertTrue(summary.confirmationMessage.contains("Mode: Move to Trash"))
        XCTAssertTrue(summary.confirmationMessage.contains("Administrator approval may be required."))
    }

    func testAppUninstallConfirmationSummaryTreatsUserApplicationsAsNormalTrash() {
        let app = InstalledApp(
            name: "Local Tool",
            bundleIdentifier: "com.example.local",
            bundlePath: "/Users/test/Applications/Local Tool.app",
            version: "unknown",
            build: "unknown"
        )

        let summary = AppUninstallConfirmationSummary(app: app)

        XCTAssertEqual(summary.versionLine, "Version: unknown")
        XCTAssertFalse(summary.requiresAdministratorApproval)
        XCTAssertFalse(summary.confirmationMessage.contains("Administrator approval may be required."))
    }
}
