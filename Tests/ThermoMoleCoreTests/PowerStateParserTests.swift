import XCTest
@testable import ThermoMoleCore

final class PowerStateParserTests: XCTestCase {
    func testDischargingOnBattery() {
        let output = """
        Now drawing from 'Battery Power'
         -InternalBattery-0 (id=12345)\t80%; discharging; 3:45 remaining present: true
        """
        let state = PowerStateParser.parse(pmsetOutput: output)

        XCTAssertEqual(state.percent, 80)
        XCTAssertFalse(state.isOnACPower)
        XCTAssertFalse(state.isCharging)
        XCTAssertFalse(state.isCharged)
        XCTAssertEqual(state.timeRemaining, "3:45")
    }

    func testCharging() {
        let output = """
        Now drawing from 'AC Power'
         -InternalBattery-0 (id=12345)\t55%; charging; 1:23 remaining present: true
        """
        let state = PowerStateParser.parse(pmsetOutput: output)

        XCTAssertEqual(state.percent, 55)
        XCTAssertTrue(state.isOnACPower)
        XCTAssertTrue(state.isCharging)
        XCTAssertFalse(state.isCharged)
        XCTAssertEqual(state.timeRemaining, "1:23")
    }

    // The bug: "not charging" (optimized-charging hold at 80%) must NOT read as charging,
    // because the string "not charging" contains the substring "charging".
    func testACHoldNotChargingIsNotCharging() {
        let output = """
        Now drawing from 'AC Power'
         -InternalBattery-0 (id=12345)\t80%; AC attached; not charging present: true
        """
        let state = PowerStateParser.parse(pmsetOutput: output)

        XCTAssertEqual(state.percent, 80)
        XCTAssertTrue(state.isOnACPower)
        XCTAssertFalse(state.isCharging)
        XCTAssertFalse(state.isCharged)
        XCTAssertEqual(state.timeRemaining, "--:--")
    }

    func testCharged() {
        let output = """
        Now drawing from 'AC Power'
         -InternalBattery-0 (id=12345)\t100%; charged; 0:00 remaining present: true
        """
        let state = PowerStateParser.parse(pmsetOutput: output)

        XCTAssertEqual(state.percent, 100)
        XCTAssertTrue(state.isOnACPower)
        XCTAssertFalse(state.isCharging)
        XCTAssertTrue(state.isCharged)
    }

    func testFinishingChargeCountsAsCharged() {
        let output = """
        Now drawing from 'AC Power'
         -InternalBattery-0 (id=12345)\t95%; finishing charge; 0:05 remaining present: true
        """
        let state = PowerStateParser.parse(pmsetOutput: output)

        XCTAssertFalse(state.isCharging)
        XCTAssertTrue(state.isCharged)
    }

    func testFallsBackToProvidedPercentWhenUnparsable() {
        let state = PowerStateParser.parse(pmsetOutput: "", fallbackPercent: 42)

        XCTAssertEqual(state.percent, 42)
        XCTAssertFalse(state.isOnACPower)
        XCTAssertFalse(state.isCharging)
        XCTAssertFalse(state.isCharged)
        XCTAssertEqual(state.timeRemaining, "--:--")
    }
}
