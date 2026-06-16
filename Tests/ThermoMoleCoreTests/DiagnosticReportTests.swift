import XCTest
@testable import ThermoMoleCore

final class DiagnosticReportTests: XCTestCase {
    func testDiagnosticReportStoreEncodesAndDecodesReport() throws {
        let entry = OperationHistoryEntry(
            kind: .clean,
            title: "Smart Clean",
            status: .succeeded,
            itemCount: 2,
            bytes: 384,
            message: "2 moved",
            executedAt: Date(timeIntervalSince1970: 200)
        )
        let report = DiagnosticReport(
            generatedAt: Date(timeIntervalSince1970: 100),
            appVersion: "1.0-test",
            snapshot: SystemSnapshot.placeholder,
            doctorReport: DoctorReport.make(inputs: .placeholder),
            recentOperations: [entry]
        )

        let data = try DiagnosticReportStore.encode(report)
        let decoded = try JSONDecoder.thermoMole.decode(DiagnosticReport.self, from: data)

        XCTAssertEqual(decoded, report)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.recentOperations.first?.title, "Smart Clean")
    }

    func testDiagnosticReportStoreWritesJSONFile() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("diagnostic.json")
        let report = DiagnosticReport(
            generatedAt: Date(timeIntervalSince1970: 100),
            appVersion: "1.0-test",
            snapshot: SystemSnapshot.placeholder,
            doctorReport: DoctorReport.make(inputs: .placeholder),
            recentOperations: []
        )

        try DiagnosticReportStore().write(report, to: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let decoded = try JSONDecoder.thermoMole.decode(DiagnosticReport.self, from: Data(contentsOf: url))
        XCTAssertEqual(decoded.appVersion, "1.0-test")
    }

    func testDiagnosticReportStoreReadsImportedReportAndBuildsSummary() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("imported-diagnostic.json")
        let entry = OperationHistoryEntry(
            kind: .optimize,
            title: "Default Optimize",
            status: .mixed,
            itemCount: 3,
            bytes: 0,
            message: "2 succeeded · 1 skipped",
            executedAt: Date(timeIntervalSince1970: 250)
        )
        let report = DiagnosticReport(
            generatedAt: Date(timeIntervalSince1970: 300),
            appVersion: "2.0-imported",
            snapshot: .placeholder,
            doctorReport: DoctorReport.make(inputs: DoctorInputs(
                hasFullDiskAccess: true,
                memoryPressure: .normal,
                diskUsedPercent: 42,
                batteryHealthPercent: 96,
                operationLogWritable: true,
                recentOperationFailures: 0
            )),
            recentOperations: [entry]
        )
        try DiagnosticReportStore().write(report, to: url)

        let imported = try DiagnosticReportStore().read(from: url)
        let summary = DiagnosticReportSummary(report: imported)

        XCTAssertEqual(imported, report)
        XCTAssertEqual(summary.appVersion, "2.0-imported")
        XCTAssertEqual(summary.schemaVersion, 1)
        XCTAssertEqual(summary.healthScore, SystemSnapshot.placeholder.health.value)
        XCTAssertEqual(summary.doctorSummary, "All clear")
        XCTAssertEqual(summary.recentOperationCount, 1)
        XCTAssertEqual(summary.machine, "\(SystemSnapshot.placeholder.chipName) · \(SystemSnapshot.placeholder.modelIdentifier)")
    }
}
