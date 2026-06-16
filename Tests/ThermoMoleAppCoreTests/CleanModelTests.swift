import XCTest
import ThermoMoleCore
@testable import ThermoMoleAppCore

@MainActor
final class CleanModelTests: XCTestCase {
    private func item(_ id: String, _ bytes: UInt64, preselected: Bool = false) -> CleanupItem {
        CleanupItem(category: .appCaches, url: URL(fileURLWithPath: "/tmp/\(id)"), sizeBytes: bytes, isPreselected: preselected)
    }

    func testRunScanPopulatesResultAndFinishes() async {
        let result = CleanupScanResult(items: [item("a", 10), item("b", 20)], skipped: [])
        let model = CleanModel(scan: { _ in result }, execute: { _, _ in CleanupExecutionResult(entries: []) }, logOperation: { _ in }, onCleaned: {})
        await model.runScan()
        XCTAssertEqual(model.result.items.count, 2)
        XCTAssertEqual(model.selection.selectedIDs.count, 0)
        XCTAssertFalse(model.state.isRunning)
        XCTAssertEqual(model.state.phase, .finished)
    }

    func testPrepareSmartCleanupSetsPlanWhenRecommended() async {
        let result = CleanupScanResult(items: [item("a", 10, preselected: true)], skipped: [])
        let model = CleanModel(scan: { _ in result }, execute: { _, _ in CleanupExecutionResult(entries: []) }, logOperation: { _ in }, onCleaned: {})
        await model.prepareSmartCleanup()
        XCTAssertNotNil(model.smartPlan)
        XCTAssertFalse(model.state.isRunning)
    }

    func testPrepareSmartCleanupNothingSafe() async {
        let result = CleanupScanResult(items: [item("a", 10, preselected: false)], skipped: [])
        let model = CleanModel(scan: { _ in result }, execute: { _, _ in CleanupExecutionResult(entries: []) }, logOperation: { _ in }, onCleaned: {})
        await model.prepareSmartCleanup()
        XCTAssertNil(model.smartPlan)
        XCTAssertEqual(model.state.message, "Nothing safe to clean")
    }

    func testSelectionMath() async {
        let a = item("a", 10), b = item("b", 20)
        let model = CleanModel(scan: { _ in CleanupScanResult(items: [a, b], skipped: []) }, execute: { _, _ in CleanupExecutionResult(entries: []) }, logOperation: { _ in }, onCleaned: {})
        await model.runScan()
        model.setSelected(a, true)
        XCTAssertEqual(model.selectedBytes(), 10)
        model.setSelected([a, b], true)
        XCTAssertEqual(model.selectedBytes(), 30)
        model.setSelected(a, false)
        XCTAssertEqual(model.selectedBytes(), 20)
    }

    func testExecuteSelectedLogsAndDropsSucceeded() async {
        let a = item("a", 10), b = item("b", 20)
        let entry = CleanupOperationLogEntry(item: a, mode: .trash, status: .succeeded, message: "Moved to Trash")
        var logged = 0
        var cleaned = 0
        let model = CleanModel(
            scan: { _ in CleanupScanResult(items: [a, b], skipped: []) },
            execute: { _, _ in CleanupExecutionResult(entries: [entry]) },
            logOperation: { _ in logged += 1 },
            onCleaned: { cleaned += 1 }
        )
        await model.runScan()
        model.setSelected(a, true)
        await model.executeSelected()
        XCTAssertEqual(model.log.count, 1)
        XCTAssertEqual(logged, 1)
        XCTAssertEqual(cleaned, 1)
        XCTAssertFalse(model.result.items.contains { $0.id == a.id })
        XCTAssertTrue(model.result.items.contains { $0.id == b.id })
    }

    func testExecuteNoopWhenSelectionEmpty() async {
        let a = item("a", 10)
        var logged = 0
        let model = CleanModel(
            scan: { _ in CleanupScanResult(items: [a], skipped: []) },
            execute: { _, _ in CleanupExecutionResult(entries: []) },
            logOperation: { _ in logged += 1 },
            onCleaned: {}
        )
        await model.runScan()
        await model.executeSelected()
        XCTAssertEqual(logged, 0)
        XCTAssertTrue(model.log.isEmpty)
    }

    func testRunScanClearsPriorSmartPlan() async {
        let a = item("a", 10, preselected: true)
        let model = CleanModel(
            scan: { _ in CleanupScanResult(items: [a], skipped: []) },
            execute: { _, _ in CleanupExecutionResult(entries: []) },
            logOperation: { _ in }, onCleaned: {}
        )
        await model.prepareSmartCleanup()
        XCTAssertNotNil(model.smartPlan)
        await model.runScan()
        XCTAssertNil(model.smartPlan)
    }

    func testDismissSmartPlanClearsPlan() async {
        let a = item("a", 10, preselected: true)
        let model = CleanModel(
            scan: { _ in CleanupScanResult(items: [a], skipped: []) },
            execute: { _, _ in CleanupExecutionResult(entries: []) },
            logOperation: { _ in }, onCleaned: {}
        )
        await model.prepareSmartCleanup()
        XCTAssertNotNil(model.smartPlan)
        model.dismissSmartPlan()
        XCTAssertNil(model.smartPlan)
    }

    func testExecuteDropsOnlySucceededKeepsFailed() async {
        let a = item("a", 10), b = item("b", 20)
        let okA = CleanupOperationLogEntry(item: a, mode: .trash, status: .succeeded, message: "Moved to Trash")
        let failB = CleanupOperationLogEntry(item: b, mode: .trash, status: .failed, message: "Failed")
        let model = CleanModel(
            scan: { _ in CleanupScanResult(items: [a, b], skipped: []) },
            execute: { _, _ in CleanupExecutionResult(entries: [okA, failB]) },
            logOperation: { _ in }, onCleaned: {}
        )
        await model.runScan()
        model.setSelected([a, b], true)
        await model.executeSelected()
        XCTAssertFalse(model.result.items.contains { $0.id == a.id })  // succeeded -> dropped
        XCTAssertTrue(model.result.items.contains { $0.id == b.id })   // failed -> kept
    }
}
