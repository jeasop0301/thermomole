import XCTest
@testable import ThermoMoleCore

final class DoctorReportTests: XCTestCase {
    func testDoctorReportIsAllClearWhenInputsAreHealthy() {
        let report = DoctorReport.make(
            inputs: DoctorInputs(
                hasFullDiskAccess: true,
                memoryPressure: .normal,
                diskUsedPercent: 42,
                batteryHealthPercent: 96,
                operationLogWritable: true,
                recentOperationFailures: 0
            )
        )

        XCTAssertTrue(report.isAllClear)
        XCTAssertEqual(report.summary, "All clear")
        XCTAssertEqual(report.checks.map(\.severity), [.ok])
    }

    func testDoctorReportFlagsMissingFullDiskAccessAndPressure() {
        let report = DoctorReport.make(
            inputs: DoctorInputs(
                hasFullDiskAccess: false,
                memoryPressure: .critical,
                diskUsedPercent: 91,
                batteryHealthPercent: 79,
                operationLogWritable: false,
                recentOperationFailures: 2
            )
        )

        XCTAssertFalse(report.isAllClear)
        XCTAssertEqual(report.summary, "6 items need attention")
        XCTAssertEqual(report.checks.map(\.action), [
            .openFullDiskAccess,
            .reduceMemoryLoad,
            .reviewStorage,
            .reviewBatteryHealth,
            .repairOperationLog,
            .reviewRecentFailures
        ])
        XCTAssertEqual(report.checks.filter { $0.severity == .warning }.count, 6)
    }

    func testDoctorReportFlagsStaleStatusSnapshot() {
        let report = DoctorReport.make(
            inputs: DoctorInputs(
                hasFullDiskAccess: true,
                memoryPressure: .normal,
                diskUsedPercent: 42,
                batteryHealthPercent: 96,
                operationLogWritable: true,
                recentOperationFailures: 0,
                statusFreshnessLevel: .stale
            )
        )

        XCTAssertFalse(report.isAllClear)
        XCTAssertEqual(report.summary, "1 item needs attention")
        XCTAssertEqual(report.checks.map(\.title), ["Status freshness"])
        XCTAssertEqual(report.checks.map(\.action), [.refreshStatusSnapshot])
        XCTAssertTrue(report.checks[0].message.contains("stale"))
    }

    func testDoctorInputsDerivesFreshnessFromSnapshotAge() {
        var snapshot = SystemSnapshot.placeholder
        snapshot.sampledAt = Date(timeIntervalSince1970: 100)
        snapshot.memory.pressure = .normal
        snapshot.disk.usedPercent = 42
        snapshot.battery.healthPercent = 96

        let live = DoctorInputs.make(
            snapshot: snapshot,
            hasFullDiskAccess: true,
            operationLogWritable: true,
            recentOperationFailures: 0,
            now: Date(timeIntervalSince1970: 104)
        )
        let stale = DoctorInputs.make(
            snapshot: snapshot,
            hasFullDiskAccess: true,
            operationLogWritable: true,
            recentOperationFailures: 0,
            now: Date(timeIntervalSince1970: 135)
        )

        XCTAssertEqual(live.statusFreshnessLevel, .live)
        XCTAssertEqual(stale.statusFreshnessLevel, .stale)
        XCTAssertEqual(stale.memoryPressure, .normal)
        XCTAssertEqual(stale.diskUsedPercent, 42)
        XCTAssertEqual(stale.batteryHealthPercent, 96)
    }

    func testDoctorGuidanceExplainsMissingFullDiskAccessAndDiagnosticScope() {
        let report = DoctorReport.make(
            inputs: DoctorInputs(
                hasFullDiskAccess: false,
                memoryPressure: .normal,
                diskUsedPercent: 42,
                batteryHealthPercent: 96,
                operationLogWritable: true,
                recentOperationFailures: 0
            )
        )

        let guidance = DoctorGuidanceSummary(report: report)

        XCTAssertEqual(guidance.fullDiskAccessStatus, "Missing or unknown")
        XCTAssertTrue(guidance.fullDiskAccessDetail.contains("optional"))
        XCTAssertTrue(guidance.fullDiskAccessDetail.contains("deeper cache and app-support scan coverage"))
        XCTAssertEqual(guidance.diagnosticScopeTitle, "Local JSON")
        XCTAssertTrue(guidance.diagnosticIncludedLines.contains("Last status snapshot"))
        XCTAssertTrue(guidance.diagnosticIncludedLines.contains("Doctor checks"))
        XCTAssertTrue(guidance.diagnosticIncludedLines.contains("Recent operation history"))
        XCTAssertTrue(guidance.diagnosticExcludedLines.contains("File contents"))
        XCTAssertTrue(guidance.sharingNote.contains("local paths"))
    }

    func testDoctorGuidanceMarksFullDiskAccessGranted() {
        let report = DoctorReport.make(
            inputs: DoctorInputs(
                hasFullDiskAccess: true,
                memoryPressure: .normal,
                diskUsedPercent: 42,
                batteryHealthPercent: 96,
                operationLogWritable: true,
                recentOperationFailures: 0
            )
        )

        let guidance = DoctorGuidanceSummary(report: report)

        XCTAssertEqual(guidance.fullDiskAccessStatus, "Granted")
        XCTAssertTrue(guidance.fullDiskAccessDetail.contains("Deeper scans can cover more local cache and app-support paths."))
        XCTAssertFalse(guidance.fullDiskAccessDetail.contains("Missing"))
    }
}
