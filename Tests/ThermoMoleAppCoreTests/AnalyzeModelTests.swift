import XCTest
import ThermoMoleCore
@testable import ThermoMoleAppCore

@MainActor
final class AnalyzeModelTests: XCTestCase {
    private func entry(_ name: String, _ bytes: UInt64, dir: Bool = false) -> DiskEntry {
        DiskEntry(url: URL(fileURLWithPath: "/tmp/\(name)"), sizeBytes: bytes, isDirectory: dir)
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("timeout waiting for condition"); return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testAnalyzeFolderPopulatesEntriesAndFinishes() async {
        let entries = [entry("a", 30, dir: true), entry("b", 10)]
        let model = AnalyzeModel(
            analyze: { _, _ in entries },
            trash: { DiskEntryTrashResult(entry: $0, status: .succeeded, message: "ok") },
            logOperation: { _ in },
            onChanged: {}
        )
        model.analyzeFolder(URL(fileURLWithPath: "/tmp/root"))
        await waitUntil { !model.analyzeState.isRunning && model.diskEntries.count == 2 }
        XCTAssertEqual(model.diskEntries.count, 2)
        XCTAssertEqual(model.analyzeState.phase, .finished)
        XCTAssertEqual(model.diskAnalysisPath.currentURL.path, "/tmp/root")
    }

    func testTrashSucceededRemovesEntryAndNotifies() async {
        let target = entry("a", 30)
        let entries = [target, entry("b", 10)]
        var logged = 0
        var changed = 0
        let model = AnalyzeModel(
            analyze: { _, _ in entries },
            trash: { DiskEntryTrashResult(entry: $0, status: .succeeded, message: "Moved") },
            logOperation: { _ in logged += 1 },
            onChanged: { changed += 1 }
        )
        model.analyzeFolder(URL(fileURLWithPath: "/tmp/root"))
        await waitUntil { model.diskEntries.count == 2 }

        model.trashDiskEntry(target)
        await waitUntil { !model.analyzeState.isRunning && model.diskEntries.count == 1 }

        XCTAssertEqual(model.diskTrashLog.count, 1)
        XCTAssertEqual(logged, 1)
        XCTAssertEqual(changed, 1)
        XCTAssertFalse(model.diskEntries.contains { $0.id == target.id })
        XCTAssertEqual(model.analyzeState.message, "Moved to Trash")
    }

    func testTrashFailedKeepsEntry() async {
        let target = entry("a", 30)
        var changed = 0
        let model = AnalyzeModel(
            analyze: { _, _ in [target] },
            trash: { DiskEntryTrashResult(entry: $0, status: .failed, message: "nope") },
            logOperation: { _ in },
            onChanged: { changed += 1 }
        )
        model.analyzeFolder(URL(fileURLWithPath: "/tmp/root"))
        await waitUntil { model.diskEntries.count == 1 }

        model.trashDiskEntry(target)
        await waitUntil { !model.analyzeState.isRunning && model.diskTrashLog.count == 1 }

        XCTAssertTrue(model.diskEntries.contains { $0.id == target.id })
        XCTAssertEqual(changed, 0)
        XCTAssertEqual(model.analyzeState.phase, .failed)
    }
}
