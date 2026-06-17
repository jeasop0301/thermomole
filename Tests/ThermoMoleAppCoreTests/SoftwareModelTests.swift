import XCTest
import ThermoMoleCore
@testable import ThermoMoleAppCore

@MainActor
final class SoftwareModelTests: XCTestCase {
    private func app(_ name: String) -> InstalledApp {
        InstalledApp(name: name, bundleIdentifier: "com.test.\(name)", bundlePath: "/Applications/\(name).app")
    }

    private func startup(_ label: String) -> StartupItem {
        StartupItem(label: label, program: "/usr/bin/\(label)", domain: .userLaunchAgent, isEnabled: true, plistPath: "/tmp/\(label).plist")
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("timeout waiting for condition"); return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testLoadSoftwarePopulatesAndFinishes() async {
        let apps = [app("Alpha"), app("Beta")]
        let items = [startup("agent")]
        let model = SoftwareModel(
            loadInventory: { (apps, items) },
            uninstall: { AppUninstallResult(app: $0, status: .succeeded, message: "ok") },
            logOperation: { _ in },
            onChanged: {}
        )
        model.loadSoftware()
        await waitUntil { !model.softwareState.isRunning && model.installedApps.count == 2 }
        XCTAssertEqual(model.installedApps.count, 2)
        XCTAssertEqual(model.startupItems.count, 1)
        XCTAssertEqual(model.softwareState.phase, .finished)
    }

    func testUninstallSucceededRemovesAppAndNotifies() async {
        let target = app("Alpha")
        let apps = [target, app("Beta")]
        var logged = 0
        var changed = 0
        let model = SoftwareModel(
            loadInventory: { (apps, []) },
            uninstall: { AppUninstallResult(app: $0, status: .succeeded, message: "Moved") },
            logOperation: { _ in logged += 1 },
            onChanged: { changed += 1 }
        )
        model.loadSoftware()
        await waitUntil { model.installedApps.count == 2 }

        model.uninstallApp(target)
        await waitUntil { !model.softwareState.isRunning && model.installedApps.count == 1 }

        XCTAssertEqual(model.appUninstallLog.count, 1)
        XCTAssertEqual(logged, 1)
        XCTAssertEqual(changed, 1)
        XCTAssertFalse(model.installedApps.contains { $0.id == target.id })
        XCTAssertEqual(model.softwareState.phase, .finished)
    }

    func testUninstallFailedKeepsApp() async {
        let target = app("Alpha")
        let apps = [target]
        var changed = 0
        let model = SoftwareModel(
            loadInventory: { (apps, []) },
            uninstall: { AppUninstallResult(app: $0, status: .failed, message: "nope") },
            logOperation: { _ in },
            onChanged: { changed += 1 }
        )
        model.loadSoftware()
        await waitUntil { model.installedApps.count == 1 }

        model.uninstallApp(target)
        await waitUntil { !model.softwareState.isRunning && model.appUninstallLog.count == 1 }

        XCTAssertTrue(model.installedApps.contains { $0.id == target.id })
        XCTAssertEqual(changed, 1)
        XCTAssertEqual(model.softwareState.phase, .failed)
    }
}
