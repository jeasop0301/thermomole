import Foundation
import XCTest
@testable import ThermoMoleCore

final class StatusFreshnessTests: XCTestCase {
    func testFreshnessIsLiveForRecentSamples() {
        let now = Date(timeIntervalSince1970: 1_000)

        let freshness = StatusFreshness(
            sampledAt: now.addingTimeInterval(-4),
            now: now
        )

        XCTAssertEqual(freshness.level, .live)
        XCTAssertEqual(freshness.title, "Live")
        XCTAssertEqual(freshness.detail, "4s ago")
        XCTAssertEqual(freshness.accessibilityLabel, "Live, last updated 4 seconds ago")
    }

    func testFreshnessIsUpdatingForDelayedSamples() {
        let now = Date(timeIntervalSince1970: 1_000)

        let freshness = StatusFreshness(
            sampledAt: now.addingTimeInterval(-15),
            now: now
        )

        XCTAssertEqual(freshness.level, .updating)
        XCTAssertEqual(freshness.title, "Updating")
        XCTAssertEqual(freshness.detail, "15s ago")
    }

    func testFreshnessIsStaleForOldSamples() {
        let now = Date(timeIntervalSince1970: 1_000)

        let freshness = StatusFreshness(
            sampledAt: now.addingTimeInterval(-35),
            now: now
        )

        XCTAssertEqual(freshness.level, .stale)
        XCTAssertEqual(freshness.title, "Stale")
        XCTAssertEqual(freshness.detail, "35s ago")
    }

    func testFreshnessClampsFutureSamplesToNow() {
        let now = Date(timeIntervalSince1970: 1_000)

        let freshness = StatusFreshness(
            sampledAt: now.addingTimeInterval(5),
            now: now
        )

        XCTAssertEqual(freshness.level, .live)
        XCTAssertEqual(freshness.detail, "now")
        XCTAssertEqual(freshness.accessibilityLabel, "Live, last updated now")
    }
}
