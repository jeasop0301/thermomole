import XCTest
import ThermoMoleCore
@testable import ThermoMoleAppCore

@MainActor
final class SettingsModelTests: XCTestCase {
    private enum TestError: Error { case boom }

    private func sampleReport() -> DiagnosticReport {
        DiagnosticReport(
            appVersion: "test",
            snapshot: .placeholder,
            doctorReport: DoctorReport.make(inputs: .placeholder),
            recentOperations: []
        )
    }

    private func makeModel(
        status: LaunchAgentStatus = .notRegistered,
        registerLaunch: @escaping () throws -> Void = {},
        unregisterLaunch: @escaping () throws -> Void = {},
        applyDockVisibility: @escaping (Bool) -> Void = { _ in },
        writeReport: @escaping SettingsModel.WriteReport = { _, _ in },
        readReport: SettingsModel.ReadReport? = nil,
        reportError: @escaping (String?) -> Void = { _ in }
    ) -> SettingsModel {
        let report = sampleReport()
        return SettingsModel(
            currentSnapshot: { .placeholder },
            currentDoctorReport: { DoctorReport.make(inputs: .placeholder) },
            currentHistory: { [] },
            reportError: reportError,
            launchStatus: { status },
            registerLaunch: registerLaunch,
            unregisterLaunch: unregisterLaunch,
            applyDockVisibility: applyDockVisibility,
            writeReport: writeReport,
            readReport: readReport ?? { _ in report }
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

    func testExportSucceeds() {
        var wrote = 0
        var lastError: String?? = "sentinel"
        let model = makeModel(writeReport: { _, _ in wrote += 1 }, reportError: { lastError = $0 })
        model.exportDiagnosticReport(to: URL(fileURLWithPath: "/tmp/diag.json"))
        XCTAssertEqual(wrote, 1)
        XCTAssertEqual(model.diagnosticExportState.phase, .finished)
        XCTAssertEqual(lastError, .some(nil))
    }

    func testExportFailureReportsError() {
        var errors = [String?]()
        let model = makeModel(writeReport: { _, _ in throw TestError.boom }, reportError: { errors.append($0) })
        model.exportDiagnosticReport(to: URL(fileURLWithPath: "/tmp/diag.json"))
        XCTAssertEqual(model.diagnosticExportState.phase, .failed)
        XCTAssertTrue(errors.contains { ($0 ?? "").hasPrefix("Diagnostic report:") })
    }

    func testImportSucceedsSetsSummary() {
        let model = makeModel(readReport: { _ in self.sampleReport() })
        model.importDiagnosticReport(from: URL(fileURLWithPath: "/tmp/diag.json"))
        XCTAssertNotNil(model.importedDiagnosticSummary)
        XCTAssertEqual(model.diagnosticImportState.phase, .finished)
    }

    func testImportFailureClearsSummary() {
        let model = makeModel(readReport: { _ in throw TestError.boom })
        model.importDiagnosticReport(from: URL(fileURLWithPath: "/tmp/diag.json"))
        XCTAssertNil(model.importedDiagnosticSummary)
        XCTAssertEqual(model.diagnosticImportState.phase, .failed)
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
