import XCTest
import ThermoMoleCore
@testable import ThermoMoleAppCore

@MainActor
final class MemoryModelTests: XCTestCase {
    private func criticalSnapshot() -> SystemSnapshot {
        var snap = SystemSnapshot.placeholder
        snap.memory.pressure = .critical
        return snap
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("timeout waiting for condition"); return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testPurgeBelowCriticalFailsAndDoesNotRun() async {
        let model = MemoryModel(
            currentSnapshot: { .placeholder },
            purge: { _ in MemoryPurgeResult(status: .succeeded, message: "should not run") },
            logOperation: { _ in },
            onChanged: {}
        )
        model.runMemoryPurge()
        XCTAssertEqual(model.memoryPurgeState.phase, .failed)
        XCTAssertEqual(model.memoryPurgeState.message, "Requires critical memory pressure")
        XCTAssertTrue(model.memoryPurgeLog.isEmpty)
    }

    func testPurgeCriticalSucceedsAndNotifies() async {
        let snap = criticalSnapshot()
        var logged = 0
        var changed = 0
        let model = MemoryModel(
            currentSnapshot: { snap },
            purge: { _ in MemoryPurgeResult(status: .succeeded, message: "Purged") },
            logOperation: { _ in logged += 1 },
            onChanged: { changed += 1 }
        )
        model.runMemoryPurge()
        await waitUntil { !model.memoryPurgeState.isRunning && model.memoryPurgeLog.count == 1 }

        XCTAssertEqual(model.memoryPurgeLog.count, 1)
        XCTAssertEqual(logged, 1)
        XCTAssertEqual(changed, 1)
        XCTAssertEqual(model.memoryPurgeState.phase, .finished)
    }

    func testPurgeCriticalFailedReportsFailure() async {
        let snap = criticalSnapshot()
        let model = MemoryModel(
            currentSnapshot: { snap },
            purge: { _ in MemoryPurgeResult(status: .failed, message: "purge failed") },
            logOperation: { _ in },
            onChanged: {}
        )
        model.runMemoryPurge()
        await waitUntil { !model.memoryPurgeState.isRunning && model.memoryPurgeLog.count == 1 }

        XCTAssertEqual(model.memoryPurgeState.phase, .failed)
        XCTAssertEqual(model.memoryPurgeState.message, "purge failed")
    }
}
