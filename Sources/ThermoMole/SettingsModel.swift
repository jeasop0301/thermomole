import Foundation
import Observation
import AppKit
import ServiceManagement
import ThermoMoleCore

@MainActor
@Observable
final class SettingsModel {
    private(set) var diagnosticExportState = OperationState.idle
    private(set) var diagnosticImportState = OperationState.idle
    private(set) var importedDiagnosticSummary: DiagnosticReportSummary?
    private(set) var showsDockIcon = false
    private(set) var launchAtLoginEnabled = false
    private(set) var launchAtLoginStatusText = "Off"

    private let currentSnapshot: () -> SystemSnapshot
    private let currentDoctorReport: () -> DoctorReport
    private let currentHistory: () -> [OperationHistoryEntry]
    private let reportError: (String?) -> Void

    init(
        currentSnapshot: @escaping () -> SystemSnapshot,
        currentDoctorReport: @escaping () -> DoctorReport,
        currentHistory: @escaping () -> [OperationHistoryEntry],
        reportError: @escaping (String?) -> Void
    ) {
        self.currentSnapshot = currentSnapshot
        self.currentDoctorReport = currentDoctorReport
        self.currentHistory = currentHistory
        self.reportError = reportError
        showsDockIcon = UserDefaults.standard.bool(forKey: "showsDockIcon")
        refreshLaunchAtLoginStatus()
    }

    func setDockIconVisible(_ visible: Bool) {
        showsDockIcon = visible
        UserDefaults.standard.set(visible, forKey: "showsDockIcon")
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
        if visible {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            reportError(nil)
        } catch {
            reportError("Launch at Login: \(error.localizedDescription)")
        }
        refreshLaunchAtLoginStatus()
    }

    func refreshLaunchAtLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLoginEnabled = status == .enabled
        launchAtLoginStatusText = switch status {
        case .enabled: "On"
        case .notRegistered: "Off"
        case .notFound: "Install to /Applications"
        case .requiresApproval: "Needs Approval"
        @unknown default: "Unknown"
        }
    }

    func exportDiagnosticReport(to url: URL) {
        let report = DiagnosticReport(
            appVersion: Self.appVersionString(),
            snapshot: currentSnapshot(),
            doctorReport: currentDoctorReport(),
            recentOperations: currentHistory()
        )
        do {
            try DiagnosticReportStore().write(report, to: url)
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

    func importDiagnosticReport(from url: URL) {
        do {
            let report = try DiagnosticReportStore().read(from: url)
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
