import XCTest
@testable import ThermoMoleCore

final class StatusBriefChargingTests: XCTestCase {
    private func snapshot(charging: Bool, level: TemperatureWarningLevel) -> SystemSnapshot {
        var snap = SystemSnapshot.placeholder
        snap.battery.isCharging = charging
        snap.battery.isOnACPower = charging   // charging implies AC is connected
        snap.thermal.batteryWarningLevel = level
        return snap
    }

    func testChargingWhileCautionIsTrue() {
        XCTAssertTrue(StatusBrief(snapshot: snapshot(charging: true, level: .caution)).isChargingWhileHot)
    }

    func testChargingWhileHotIsTrue() {
        XCTAssertTrue(StatusBrief(snapshot: snapshot(charging: true, level: .hot)).isChargingWhileHot)
    }

    func testChargingWhileNormalIsFalse() {
        XCTAssertFalse(StatusBrief(snapshot: snapshot(charging: true, level: .normal)).isChargingWhileHot)
    }

    func testHotButNotChargingIsFalse() {
        XCTAssertFalse(StatusBrief(snapshot: snapshot(charging: false, level: .hot)).isChargingWhileHot)
    }

    func testOnACPowerAtFullChargeWhileHotIsTrue() {
        var snap = SystemSnapshot.placeholder
        snap.battery.isCharging = false       // battery topped off / charge hold
        snap.battery.isOnACPower = true
        snap.thermal.batteryWarningLevel = .hot
        XCTAssertTrue(StatusBrief(snapshot: snap).isChargingWhileHot)
    }
}
