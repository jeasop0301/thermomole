import XCTest
@testable import ThermoMoleCore

final class MenuBarSegmentTests: XCTestCase {
    private func snapshot() -> SystemSnapshot {
        var snap = SystemSnapshot.placeholder
        snap.thermal.cpuDisplayC = 58.1
        snap.thermal.batteryDisplayC = 30.6
        snap.memory.usedPercent = 55
        return snap
    }

    func testBatterySegmentRangeMatchesToken() {
        let pres = MenuBarPresentation(
            snapshot: snapshot(),
            metrics: [.cpuTemperature, .batteryTemperature, .memoryPercent]
        )
        let title = pres.title as NSString
        guard let seg = pres.batterySegment else { return XCTFail("expected battery segment") }
        XCTAssertEqual(seg.text, "BAT 30.6°")
        XCTAssertEqual(seg.range.location, ("CPU 58.1° · " as NSString).length)
        XCTAssertEqual(seg.range.length, ("BAT 30.6°" as NSString).length)
        XCTAssertEqual(title.substring(with: seg.range), "BAT 30.6°")
    }

    func testBatterySegmentNilWhenAbsent() {
        let pres = MenuBarPresentation(snapshot: snapshot(), metrics: [.cpuTemperature, .memoryPercent])
        XCTAssertNil(pres.batterySegment)
    }

    func testBatterySegmentCorrectAfterReorder() {
        let first = MenuBarPresentation(
            snapshot: snapshot(),
            metrics: [.batteryTemperature, .cpuTemperature, .memoryPercent]
        )
        XCTAssertEqual(first.batterySegment?.range.location, 0)
        let last = MenuBarPresentation(
            snapshot: snapshot(),
            metrics: [.memoryPercent, .cpuTemperature, .batteryTemperature]
        )
        XCTAssertEqual((last.title as NSString).substring(with: last.batterySegment!.range), "BAT 30.6°")
    }

    func testSegmentsCoverEveryMetricInOrder() {
        let pres = MenuBarPresentation(
            snapshot: snapshot(),
            metrics: [.cpuTemperature, .batteryTemperature, .memoryPercent]
        )
        XCTAssertEqual(pres.segments.map(\.metric), [.cpuTemperature, .batteryTemperature, .memoryPercent])
        XCTAssertEqual(pres.segments.map(\.text), ["CPU 58.1°", "BAT 30.6°", "RAM 55%"])
        XCTAssertEqual(pres.segments[0].range, NSRange(location: 0, length: 9))   // "CPU 58.1°"
        XCTAssertEqual(pres.segments[1].range, NSRange(location: 12, length: 9))  // "BAT 30.6°"
        XCTAssertEqual(pres.segments[2].range, NSRange(location: 24, length: 7))  // "RAM 55%"
    }

    func testBatteryTintMapping() {
        XCTAssertEqual(SystemConditionPolicy.batteryTint(for: .normal), .normal)
        XCTAssertEqual(SystemConditionPolicy.batteryTint(for: .caution), .caution)
        XCTAssertEqual(SystemConditionPolicy.batteryTint(for: .hot), .hot)
    }
}
