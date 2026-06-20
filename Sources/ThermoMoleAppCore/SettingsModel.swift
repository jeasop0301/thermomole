import Foundation
import Observation
import ThermoMoleCore

@MainActor
@Observable
public final class SettingsModel {
    public private(set) var showsDockIcon = false
    public private(set) var launchAtLoginEnabled = false
    public private(set) var launchAtLoginStatusText = "Off"

    private let reportError: (String?) -> Void
    private let launchStatus: () -> LaunchAgentStatus
    private let registerLaunch: () throws -> Void
    private let unregisterLaunch: () throws -> Void
    private let applyDockVisibility: (Bool) -> Void

    public init(
        reportError: @escaping (String?) -> Void,
        launchStatus: @escaping () -> LaunchAgentStatus,
        registerLaunch: @escaping () throws -> Void,
        unregisterLaunch: @escaping () throws -> Void,
        applyDockVisibility: @escaping (Bool) -> Void
    ) {
        self.reportError = reportError
        self.launchStatus = launchStatus
        self.registerLaunch = registerLaunch
        self.unregisterLaunch = unregisterLaunch
        self.applyDockVisibility = applyDockVisibility
        showsDockIcon = UserDefaults.standard.bool(forKey: "showsDockIcon")
        refreshLaunchAtLoginStatus()
    }

    public func setDockIconVisible(_ visible: Bool) {
        showsDockIcon = visible
        UserDefaults.standard.set(visible, forKey: "showsDockIcon")
        applyDockVisibility(visible)
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if launchStatus() != .enabled {
                    try registerLaunch()
                }
            } else if launchStatus() == .enabled {
                try unregisterLaunch()
            }
            reportError(nil)
        } catch {
            reportError(String(format: NSLocalizedString("Launch at Login: %@", comment: ""), error.localizedDescription))
        }
        refreshLaunchAtLoginStatus()
    }

    public func refreshLaunchAtLoginStatus() {
        let status = launchStatus()
        launchAtLoginEnabled = status == .enabled
        launchAtLoginStatusText = switch status {
        case .enabled: NSLocalizedString("On", comment: "")
        case .notRegistered: NSLocalizedString("Off", comment: "")
        case .notFound: NSLocalizedString("Install to /Applications", comment: "")
        case .requiresApproval: NSLocalizedString("Needs Approval", comment: "")
        case .unknown: NSLocalizedString("Unknown", comment: "")
        }
    }
}
