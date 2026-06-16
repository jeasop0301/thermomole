import XCTest
@testable import ThermoMoleCore

final class OperationStateTests: XCTestCase {
    func testOperationStateTracksRunningAndCompletionMessages() {
        let startedAt = Date(timeIntervalSince1970: 10)
        let finishedAt = Date(timeIntervalSince1970: 20)

        let running = OperationState.idle.started(message: "Scanning", at: startedAt)
        XCTAssertEqual(running.phase, .running)
        XCTAssertTrue(running.isRunning)
        XCTAssertEqual(running.message, "Scanning")
        XCTAssertEqual(running.lastUpdatedAt, startedAt)

        let finished = running.finished(message: "12 items found", at: finishedAt)
        XCTAssertEqual(finished.phase, .finished)
        XCTAssertFalse(finished.isRunning)
        XCTAssertEqual(finished.message, "12 items found")
        XCTAssertEqual(finished.lastUpdatedAt, finishedAt)
    }

    func testOperationStateTracksFailures() {
        let failed = OperationState.idle.failed(message: "Access denied", at: Date(timeIntervalSince1970: 30))

        XCTAssertEqual(failed.phase, .failed)
        XCTAssertFalse(failed.isRunning)
        XCTAssertEqual(failed.message, "Access denied")
    }
}
