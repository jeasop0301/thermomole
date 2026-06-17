import Foundation
import Observation
import ThermoMoleCore

@MainActor
@Observable
public final class SettingsModel {
    public private(set) var diagnosticExportState = OperationState.idle
    public private(set) var diagnosticImportState = OperationState.idle
    public private(set) var importedDiagnosticSummary: DiagnosticReportSummary?
    public private(set) var showsDockIcon = false
    public private(set) var launchAtLoginEnabled = false
    public private(set) var launchAtLoginStatusText = "Off"

    public typealias WriteReport = (DiagnosticReport, URL) throws -> Void
    public typealias ReadReport = (URL) throws -> DiagnosticReport

    private let currentSnapshot: () -> SystemSnapshot
    private let currentDoctorReport: () -> DoctorReport
    private let currentHistory: () -> [OperationHistoryEntry]
    private let reportError: (String?) -> Void
    private let launchStatus: () -> LaunchAgentStatus
    private let registerLaunch: () throws -> Void
    private let unregisterLaunch: () throws -> Void
    private let applyDockVisibility: (Bool) -> Void
    private let writeReport: WriteReport
    private let readReport: ReadReport

    public init(
        currentSnapshot: @escaping () -> SystemSnapshot,
        currentDoctorReport: @escaping () -> DoctorReport,
        currentHistory: @escaping () -> [OperationHistoryEntry],
        reportError: @escaping (String?) -> Void,
        launchStatus: @escaping () -> LaunchAgentStatus,
        registerLaunch: @escaping () throws -> Void,
        unregisterLaunch: @escaping () throws -> Void,
        applyDockVisibility: @escaping (Bool) -> Void,
        writeReport: @escaping WriteReport,
        readReport: @escaping ReadReport
    ) {
        self.currentSnapshot = currentSnapshot
        self.currentDoctorReport = currentDoctorReport
        self.currentHistory = currentHistory
        self.reportError = reportError
        self.launchStatus = launchStatus
        self.registerLaunch = registerLaunch
        self.unregisterLaunch = unregisterLaunch
        self.applyDockVisibility = applyDockVisibility
        self.writeReport = writeReport
        self.readReport = readReport
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
            reportError("Launch at Login: \(error.localizedDescription)")
        }
        refreshLaunchAtLoginStatus()
    }

    public func refreshLaunchAtLoginStatus() {
        let status = launchStatus()
        launchAtLoginEnabled = status == .enabled
        launchAtLoginStatusText = switch status {
        case .enabled: "On"
        case .notRegistered: "Off"
        case .notFound: "Install to /Applications"
        case .requiresApproval: "Needs Approval"
        case .unknown: "Unknown"
        }
    }

    public func exportDiagnosticReport(to url: URL) {
        let report = DiagnosticReport(
            appVersion: Self.appVersionString(),
            snapshot: currentSnapshot(),
            doctorReport: currentDoctorReport(),
            recentOperations: currentHistory()
        )
        do {
            try writeReport(report, url)
            diagnosticExportState = diagnosticExportState.finished(
                message: "Diagnostic report exported",
                at: Date()
            )
            reportError(nil)
        } catch {
            diagnosticExportState = diagnosticExportState.failed(
                message: "Diagnostic export failed",
                at: Date()
            )
            reportError("Diagnostic report: \(error.localizedDescription)")
        }
    }

    public func importDiagnosticReport(from url: URL) {
        do {
            let report = try readReport(url)
            importedDiagnosticSummary = DiagnosticReportSummary(report: report)
            diagnosticImportState = diagnosticImportState.finished(
                message: "Diagnostic report imported",
                at: Date()
            )
            reportError(nil)
        } catch {
            importedDiagnosticSummary = nil
            diagnosticImportState = diagnosticImportState.failed(
                message: "Diagnostic import failed",
                at: Date()
            )
            reportError("Diagnostic report: \(error.localizedDescription)")
        }
    }

    private static func appVersionString() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let joined = [version, build]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return joined.isEmpty ? "debug" : joined
    }
}
