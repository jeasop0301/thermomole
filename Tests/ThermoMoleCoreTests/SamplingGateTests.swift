import Foundation
import XCTest
@testable import ThermoMoleCore

final class SamplingGateTests: XCTestCase {
    func testSamplingGateBlocksOverlappingFreshSamples() {
        var gate = SamplingGate(timeout: 5)
        let now = Date(timeIntervalSince1970: 100)

        XCTAssertTrue(gate.begin(now: now))
        XCTAssertFalse(gate.begin(now: now.addingTimeInterval(2)))
    }

    func testSamplingGateAllowsRetryAfterStaleSample() {
        var gate = SamplingGate(timeout: 5)
        let now = Date(timeIntervalSince1970: 100)

        XCTAssertTrue(gate.begin(now: now))
        XCTAssertTrue(gate.begin(now: now.addingTimeInterval(6)))
    }

    func testSamplingGateAllowsNextSampleAfterFinish() {
        var gate = SamplingGate(timeout: 5)
        let now = Date(timeIntervalSince1970: 100)

        XCTAssertTrue(gate.begin(now: now))
        gate.finish()
        XCTAssertTrue(gate.begin(now: now.addingTimeInterval(1)))
    }

    func testSamplingGateIgnoresFinishFromStaleSampleAfterRetryStarted() {
        var gate = SamplingGate(timeout: 5)
        let first = Date(timeIntervalSince1970: 100)
        let second = Date(timeIntervalSince1970: 106)

        XCTAssertTrue(gate.begin(now: first))
        XCTAssertTrue(gate.begin(now: second))
        gate.finish(startedAt: first)

        XCTAssertFalse(gate.begin(now: second.addingTimeInterval(1)))
    }
}
