import XCTest
import ThermoMoleCore
@testable import ThermoMoleAppCore

@MainActor
final class SettingsModelTests: XCTestCase {
    private enum TestError: Error { case boom }

    private func makeModel(
        status: LaunchAgentStatus = .notRegistered,
        registerLaunch: @escaping () throws -> Void = {},
        unregisterLaunch: @escaping () throws -> Void = {},
        applyDockVisibility: @escaping (Bool) -> Void = { _ in },
        reportError: @escaping (String?) -> Void = { _ in }
    ) -> SettingsModel {
        SettingsModel(
            reportError: reportError,
            launchStatus: { status },
            registerLaunch: registerLaunch,
            unregisterLaunch: unregisterLaunch,
            applyDockVisibility: applyDockVisibility
        )
    }

    func testSetLaunchAtLoginEnableRegistersWhenNotRegistered() {
        var registered = 0
        let model = makeModel(status: .notRegistered, registerLaunch: { registered += 1 })
        model.setLaunchAtLogin(true)
        XCTAssertEqual(registered, 1)
    }

    func testSetLaunchAtLoginDisableUnregistersWhenEnabled() {
        var unregistered = 0
        let model = makeModel(status: .enabled, unregisterLaunch: { unregistered += 1 })
        model.setLaunchAtLogin(false)
        XCTAssertEqual(unregistered, 1)
    }

    func testSetLaunchAtLoginEnableNoopWhenAlreadyEnabled() {
        var registered = 0
        let model = makeModel(status: .enabled, registerLaunch: { registered += 1 })
        model.setLaunchAtLogin(true)
        XCTAssertEqual(registered, 0)
    }

    func testSetLaunchAtLoginReportsErrorOnThrow() {
        var errors = [String?]()
        let model = makeModel(status: .notRegistered, registerLaunch: { throw TestError.boom }, reportError: { errors.append($0) })
        model.setLaunchAtLogin(true)
        XCTAssertTrue(errors.contains { ($0 ?? "").hasPrefix("Launch at Login:") })
    }

    func testRefreshLaunchAtLoginStatusMapping() {
        let cases: [(LaunchAgentStatus, Bool, String)] = [
            (.enabled, true, "On"),
            (.notRegistered, false, "Off"),
            (.notFound, false, "Install to /Applications"),
            (.requiresApproval, false, "Needs Approval"),
            (.unknown, false, "Unknown"),
        ]
        for (status, enabled, text) in cases {
            let model = makeModel(status: status)  // init이 refreshLaunchAtLoginStatus 호출
            XCTAssertEqual(model.launchAtLoginEnabled, enabled, "status \(status)")
            XCTAssertEqual(model.launchAtLoginStatusText, text, "status \(status)")
        }
    }

    func testSetDockIconVisibleAppliesAndPersists() {
        var applied: Bool?
        let model = makeModel(applyDockVisibility: { applied = $0 })
        model.setDockIconVisible(true)
        XCTAssertTrue(model.showsDockIcon)
        XCTAssertEqual(applied, true)
        UserDefaults.standard.removeObject(forKey: "showsDockIcon")
    }
}
