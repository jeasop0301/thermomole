import XCTest
@testable import ThermoMoleCore

final class RatedCycleContextTests: XCTestCase {

    func testBuildsWhenRatedPresentAndPositive() {
        let ctx = RatedCycleContext.make(cycleCount: 8, ratedCycleCount: 1000)
        XCTAssertEqual(ctx?.cycleCount, 8)
        XCTAssertEqual(ctx?.ratedCycleCount, 1000)
        XCTAssertEqual(ctx?.percentThrough, 0)   // 8 * 100 / 1000 = 0 (floored)
    }

    func testPercentThroughFloors() {
        XCTAssertEqual(RatedCycleContext.make(cycleCount: 500, ratedCycleCount: 1000)?.percentThrough, 50)
        XCTAssertEqual(RatedCycleContext.make(cycleCount: 999, ratedCycleCount: 1000)?.percentThrough, 99)
        XCTAssertEqual(RatedCycleContext.make(cycleCount: 1000, ratedCycleCount: 1000)?.percentThrough, 100)
    }

    /// Past the rated count the battery still works — percent is honest (>100), not clamped.
    func testPercentThroughCanExceed100() {
        XCTAssertEqual(RatedCycleContext.make(cycleCount: 1200, ratedCycleCount: 1000)?.percentThrough, 120)
    }

    func testNilWhenRatedMissing() {
        XCTAssertNil(RatedCycleContext.make(cycleCount: 8, ratedCycleCount: nil))
    }

    func testNilWhenRatedZeroOrNegative() {
        XCTAssertNil(RatedCycleContext.make(cycleCount: 8, ratedCycleCount: 0))
        XCTAssertNil(RatedCycleContext.make(cycleCount: 8, ratedCycleCount: -1))
    }

    func testNilWhenCycleCountNegative() {
        XCTAssertNil(RatedCycleContext.make(cycleCount: -1, ratedCycleCount: 1000))
    }

    func testZeroCyclesIsValid() {
        let ctx = RatedCycleContext.make(cycleCount: 0, ratedCycleCount: 1000)
        XCTAssertEqual(ctx?.percentThrough, 0)
    }
}
