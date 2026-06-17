import XCTest
import ThermoMoleCore
@testable import ThermoMoleAppCore

@MainActor
final class OptimizeModelTests: XCTestCase {
    private func waitUntil(timeout: TimeInterval = 2, _ condition: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("timeout waiting for condition"); return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func makeModel(
        hasExternalDisplay: Bool = false,
        probe: OptimizeSafetyProbe = OptimizeSafetyProbe(hasActiveVPN: false, hasExternalAudio: false, hasBluetoothHID: false, hasBluetoothAudio: false),
        execute: @escaping OptimizeModel.Execute = { OptimizeExecutionResult(task: $0.task, status: .succeeded, entries: []) },
        executeBatch: @escaping OptimizeModel.ExecuteBatch = { $0.plans.map { OptimizeExecutionResult(task: $0.task, status: .succeeded, entries: []) } },
        logOperation: @escaping (OperationHistoryEntry) -> Void = { _ in },
        onChanged: @escaping () -> Void = {}
    ) -> OptimizeModel {
        OptimizeModel(
            currentSnapshot: { .placeholder },
            hasExternalDisplay: { hasExternalDisplay },
            probeSafety: { probe },
            execute: execute,
            executeBatch: executeBatch,
            logOperation: logOperation,
            onChanged: onChanged
        )
    }

    func testRunOptimizeTaskSucceedsLogsAndFinishes() async {
        var logged = 0
        var changed = 0
        let model = makeModel(
            execute: { OptimizeExecutionResult(task: $0.task, status: .succeeded, entries: []) },
            logOperation: { _ in logged += 1 },
            onChanged: { changed += 1 }
        )
        model.runOptimizeTask(.quickLook)  // quickLook은 안전(skip 없음)
        await waitUntil { !model.optimizeState.isRunning && model.optimizeLog.count == 1 }

        XCTAssertEqual(model.optimizeLog.count, 1)
        XCTAssertEqual(logged, 1)
        XCTAssertEqual(changed, 1)
        XCTAssertEqual(model.optimizeState.phase, .finished)
    }

    func testRunOptimizeTaskFailed() async {
        let model = makeModel(
            execute: { OptimizeExecutionResult(task: $0.task, status: .failed, entries: []) }
        )
        model.runOptimizeTask(.quickLook)
        await waitUntil { !model.optimizeState.isRunning && model.optimizeLog.count == 1 }

        XCTAssertEqual(model.optimizeState.phase, .failed)
    }

    func testRunOptimizeTaskStagedSkipsExecution() async {
        var logged = 0
        let model = makeModel(logOperation: { _ in logged += 1 })
        // savedApplicationState는 항상 staged → 동기 반환, execute 미호출
        model.runOptimizeTask(.savedApplicationState)

        XCTAssertEqual(model.optimizeState.phase, .finished)
        XCTAssertTrue(model.optimizeState.message.contains("staged"))
        XCTAssertTrue(model.optimizeLog.isEmpty)
        XCTAssertEqual(logged, 0)
    }

    func testRunDefaultOptimizeSucceeds() async {
        let model = makeModel(
            executeBatch: { $0.plans.map { OptimizeExecutionResult(task: $0.task, status: .succeeded, entries: []) } }
        )
        model.runDefaultOptimize()
        await waitUntil { !model.optimizeState.isRunning && !model.optimizeLog.isEmpty }

        XCTAssertEqual(model.optimizeState.phase, .finished)
    }

    func testRunDefaultOptimizeReportsFailure() async {
        let model = makeModel(
            executeBatch: { $0.plans.map { OptimizeExecutionResult(task: $0.task, status: .failed, entries: []) } }
        )
        model.runDefaultOptimize()
        await waitUntil { !model.optimizeState.isRunning && !model.optimizeLog.isEmpty }

        XCTAssertEqual(model.optimizeState.phase, .failed)
    }

    func testRefreshSafetyContextReflectsProbe() async {
        let probe = OptimizeSafetyProbe(hasActiveVPN: true, hasExternalAudio: true, hasBluetoothHID: false, hasBluetoothAudio: true)
        let model = makeModel(hasExternalDisplay: true, probe: probe)
        model.refreshOptimizeSafetyContext()
        await waitUntil { model.optimizeSafetyContext.hasActiveVPN }

        XCTAssertTrue(model.optimizeSafetyContext.hasActiveVPN)
        XCTAssertTrue(model.optimizeSafetyContext.hasExternalDisplay)
        XCTAssertTrue(model.optimizeSafetyContext.hasExternalAudio)
        XCTAssertTrue(model.optimizeSafetyContext.hasBluetoothAudio)
        XCTAssertFalse(model.optimizeSafetyContext.hasBluetoothHID)
    }
}
