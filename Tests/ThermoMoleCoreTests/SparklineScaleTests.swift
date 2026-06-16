import XCTest
@testable import ThermoMoleCore

final class SparklineScaleTests: XCTestCase {
    func testVaryingSeriesMapsToFullRange() {
        let f = SparklineScale.fractions([0, 5, 10])
        XCTAssertEqual(f[0], 0, accuracy: 0.0001)
        XCTAssertEqual(f[1], 0.5, accuracy: 0.0001)
        XCTAssertEqual(f[2], 1, accuracy: 0.0001)
    }

    func testFlatSeriesCentersAtHalf() {
        // A constant series (e.g. battery held at 30.4) must not pin to the bottom edge.
        XCTAssertEqual(SparklineScale.fractions([30.4, 30.4, 30.4]), [0.5, 0.5, 0.5])
    }

    func testSingleSampleCentersAtHalf() {
        XCTAssertEqual(SparklineScale.fractions([42]), [0.5])
    }

    func testEmptySeriesReturnsEmpty() {
        XCTAssertEqual(SparklineScale.fractions([Double]()), [])
    }

    func testNearlyFlatWithinEpsilonCenters() {
        // Differences below the epsilon are treated as flat to avoid noise amplification.
        XCTAssertEqual(SparklineScale.fractions([30.0, 30.00005]), [0.5, 0.5])
    }
}
