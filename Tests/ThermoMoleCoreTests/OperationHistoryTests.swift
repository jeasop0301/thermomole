import Foundation
import XCTest
@testable import ThermoMoleCore

final class OperationHistoryTests: XCTestCase {
    func testOperationHistoryStoreAppendsAndReadsRecentEntries() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OperationHistoryStore(logURL: root.appendingPathComponent("operations.jsonl"))

        let older = OperationHistoryEntry(
            kind: .clean,
            title: "Smart Clean",
            status: .succeeded,
            itemCount: 1,
            bytes: 128,
            message: "1 moved",
            executedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = OperationHistoryEntry(
            kind: .optimize,
            title: "Default Optimize",
            status: .failed,
            itemCount: 2,
            bytes: 0,
            message: "1 failed",
            executedAt: Date(timeIntervalSince1970: 200)
        )

        try store.append(older)
        try store.append(newer)

        XCTAssertEqual(try store.readRecent(limit: 1), [newer])
        XCTAssertEqual(try store.readRecent(limit: 10), [newer, older])
    }

    func testOperationHistoryEntrySummarizesCleanupExecution() {
        let root = URL(fileURLWithPath: "/tmp/thermomole-tests", isDirectory: true)
        let succeeded = CleanupItem(category: .appCaches, url: root.appendingPathComponent("cache"), sizeBytes: 128, isPreselected: true)
        let skipped = CleanupItem(category: .logs, url: root.appendingPathComponent("log"), sizeBytes: 256, isPreselected: true)
        let result = CleanupExecutionResult(entries: [
            CleanupOperationLogEntry(item: succeeded, mode: .trash, status: .succeeded, message: "Moved", executedAt: Date(timeIntervalSince1970: 100)),
            CleanupOperationLogEntry(item: skipped, mode: .trash, status: .skipped, message: "Skipped", executedAt: Date(timeIntervalSince1970: 100))
        ])

        let entry = OperationHistoryEntry.cleanup(
            kind: .clean,
            title: "Smart Clean",
            result: result,
            executedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(entry.kind, .clean)
        XCTAssertEqual(entry.status, .mixed)
        XCTAssertEqual(entry.itemCount, 2)
        XCTAssertEqual(entry.bytes, 128)
        XCTAssertTrue(entry.message.contains("1 moved"))
        XCTAssertTrue(entry.message.contains("1 skipped"))
    }

    func testTerminalCommandParserAndFormatterSupportHistory() throws {
        XCTAssertEqual(try TerminalCommandParser.parse(["history"]), .history)

        let entry = OperationHistoryEntry(
            kind: .installer,
            title: "Installer Cleanup",
            status: .succeeded,
            itemCount: 2,
            bytes: 384,
            message: "2 moved",
            executedAt: Date(timeIntervalSince1970: 100)
        )
        let output = TerminalOutputFormatter.history([entry])

        XCTAssertTrue(output.contains("History"))
        XCTAssertTrue(output.contains("Installer Cleanup"))
        XCTAssertTrue(output.contains("2 moved"))
        XCTAssertTrue(output.contains("384 B"))
        XCTAssertFalse(output.localizedCaseInsensitiveContains("select"))
    }
}
