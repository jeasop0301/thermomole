// Tests/ThermoMoleCoreTests/HeatPatternInsightTests.swift
import XCTest
@testable import ThermoMoleCore

final class HeatPatternInsightTests: XCTestCase {
    private func dayWith(_ day: String, _ pairs: [(hour: Int, temp: Double)]) -> DailyHourlyHeat {
        var hh = DailyHourlyHeat.empty(day: day)
        for p in pairs { hh.hours[p.hour] = HourHeatCell(sumC: p.temp, count: 1, peakC: p.temp) }
        return hh
    }

    func testInsufficientWhenFewerThanThreeDays() {
        let grid = [dayWith("2026-06-16", [(14, 38)]), dayWith("2026-06-17", [(14, 39)])]
        let insight = HeatPatternInsight.build(grid)
        XCTAssertFalse(insight.hasEnoughData)
        XCTAssertNil(insight.hottestWindow)
    }

    func testHottestWindowDetectedAndExpanded() throws {
        // peak hour 14 (39°). hour 15 (38.4°, Δ0.6 ≤ 1.0) included; hour 13 (36.5°, Δ2.5 > 1.0) excluded.
        let grid = (16...20).map { d -> DailyHourlyHeat in
            dayWith(String(format: "2026-06-%02d", d), [(13, 36.5), (14, 39), (15, 38.4), (3, 25)])
        }
        let insight = HeatPatternInsight.build(grid)
        XCTAssertTrue(insight.hasEnoughData)
        let w = try XCTUnwrap(insight.hottestWindow)
        XCTAssertEqual(w.startHour, 14)
        XCTAssertEqual(w.endHour, 15)
    }

    func testProfileWeightedMean() {
        let grid = [
            dayWith("2026-06-16", [(14, 30)]),
            dayWith("2026-06-17", [(14, 40)]),
            dayWith("2026-06-18", [(14, 38)]),
        ]
        let insight = HeatPatternInsight.build(grid)
        XCTAssertEqual(insight.hourlyProfile[14] ?? 0, 36, accuracy: 0.0001)
        XCTAssertNil(insight.hourlyProfile[2])
    }

    func testCellsMirrorGrid() {
        let grid = [dayWith("2026-06-16", [(14, 38)]), dayWith("2026-06-17", []), dayWith("2026-06-18", [(14, 39)])]
        let insight = HeatPatternInsight.build(grid)
        XCTAssertEqual(insight.cells.count, 3)
        XCTAssertEqual(insight.cells[0].count, 24)
        XCTAssertEqual(insight.cells[0][14] ?? 0, 38, accuracy: 0.0001)
        XCTAssertNil(insight.cells[1][14])
    }
}
