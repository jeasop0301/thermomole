import XCTest
@testable import ThermoMoleCore

final class FleetMetricsExportTests: XCTestCase {

    // Fixed timestamp so encoding is fully deterministic.
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeBattery(
        healthPercent: Int = 92,
        cycleCount: Int = 211,
        dailyMaxSoc: Int? = 96,
        dailyMinSoc: Int? = 74
    ) -> BatteryStatus {
        BatteryStatus(
            percent: 96,
            isCharging: false,
            isCharged: true,
            isOnACPower: true,
            timeRemaining: "--:--",
            cycleCount: cycleCount,
            healthPercent: healthPercent,
            currentCapacityMAh: 4800,
            maxCapacityMAh: 4900,
            designCapacityMAh: 5300,
            instantPowerW: 0,
            dailyMaxSoc: dailyMaxSoc,
            dailyMinSoc: dailyMinSoc
        )
    }

    private func makeExport(
        dailyMaxSoc: Int? = 96,
        dailyMinSoc: Int? = 74,
        calibration: BatteryCalibrationResult = BatteryCalibrationResult(status: .calibrated, band: .faster, k: 1.42, windowDays: 90)
    ) -> FleetMetricsExport {
        let aging = BatteryAgingRate(
            multiplier: 1.8, rawMultiplier: 1.8, band: .moderate,
            dominantDriver: .charge, coldChargeCaution: false
        )
        let exposure = ChargeExposureSummary(
            today: DailyChargeExposure(
                day: "2026-06-21",
                secondsAbove80OnAC: 12_345.0,
                secondsAbove95OnAC: 678.0,
                peakPercentOnAC: 96
            ),
            recent: []
        )
        return FleetMetricsExport.from(
            battery: makeBattery(dailyMaxSoc: dailyMaxSoc, dailyMinSoc: dailyMinSoc),
            agingRate: aging,
            calibration: calibration,
            chargeExposure: exposure,
            dailyMaxSoc: dailyMaxSoc,
            dailyMinSoc: dailyMinSoc,
            batteryTempC: 31.4,
            nativeChargeLimitAvailable: true,
            appVersion: "0.2.0",
            generatedAt: fixedDate
        )
    }

    private func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    // MARK: - Builder field derivation

    func testBuilderPopulatesPrimitiveFields() {
        let export = makeExport()
        XCTAssertEqual(export.schemaVersion, 1)
        XCTAssertEqual(export.appVersion, "0.2.0")
        XCTAssertEqual(export.generatedAt, fixedDate)
        XCTAssertEqual(export.batteryHealthPercent, 92)
        XCTAssertEqual(export.cycleCount, 211)
        XCTAssertEqual(export.agingMultiplier, 1.8, accuracy: 1e-9)
        XCTAssertEqual(export.agingBand, "elevated")          // shown 1.8 → elevated
        XCTAssertEqual(export.dominantDriver, "charge")
        XCTAssertEqual(export.batteryTempC, 31.4)
        XCTAssertEqual(export.dailyMaxSoc, 96)
        XCTAssertEqual(export.dailyMinSoc, 74)
        XCTAssertTrue(export.nativeChargeLimitAvailable)
        XCTAssertEqual(export.secondsAbove80OnACToday, 12_345.0, accuracy: 1e-9)
        XCTAssertEqual(export.secondsAbove95OnACToday, 678.0, accuracy: 1e-9)
    }

    func testCalibrationBandAndStatusPresent_butRawKNotAField() {
        let export = makeExport()
        XCTAssertEqual(export.calibrationStatus, "calibrated")
        XCTAssertEqual(export.calibrationBand, "faster")
    }

    func testModeledCalibrationHasNilBand() {
        let export = makeExport(calibration: .modeled)
        XCTAssertEqual(export.calibrationStatus, "modeled")
        XCTAssertNil(export.calibrationBand)
    }

    func testNoAgingRateDefaultsToOneTimesLowBand() {
        let exposure = ChargeExposureSummary(today: .empty(day: "2026-06-21"), recent: [])
        let export = FleetMetricsExport.from(
            battery: makeBattery(),
            agingRate: nil,
            calibration: .modeled,
            chargeExposure: exposure,
            dailyMaxSoc: nil,
            dailyMinSoc: nil,
            batteryTempC: nil,
            nativeChargeLimitAvailable: false,
            appVersion: "0.2.0",
            generatedAt: fixedDate
        )
        XCTAssertEqual(export.agingMultiplier, 1.0, accuracy: 1e-9)
        XCTAssertEqual(export.agingBand, "low")
        XCTAssertNil(export.dominantDriver)
        XCTAssertNil(export.batteryTempC)
        XCTAssertEqual(export.chargeLimitState, "normal")
        XCTAssertNil(export.cappingAt80ReductionPct)
    }

    // MARK: - Aging band mirrors the card

    func testAgingBandThresholdsMatchCard() {
        XCTAssertEqual(FleetMetricsExport.agingBand(forMultiplier: 1.0), "low")
        XCTAssertEqual(FleetMetricsExport.agingBand(forMultiplier: 1.44), "low")     // shown 1.4 → low
        XCTAssertEqual(FleetMetricsExport.agingBand(forMultiplier: 1.49), "elevated") // shown 1.5 → elevated
        XCTAssertEqual(FleetMetricsExport.agingBand(forMultiplier: 1.5), "elevated")
        XCTAssertEqual(FleetMetricsExport.agingBand(forMultiplier: 2.9), "elevated")
        XCTAssertEqual(FleetMetricsExport.agingBand(forMultiplier: 2.96), "high")    // shown 3.0 → high
        XCTAssertEqual(FleetMetricsExport.agingBand(forMultiplier: 3.0), "high")
        XCTAssertEqual(FleetMetricsExport.agingBand(forMultiplier: 4.2), "high")
    }

    // MARK: - chargeLimitState matches ChargeLimitInsight.classify

    func testChargeLimitStateMatchesClassify_limitActive() {
        let export = makeExport(dailyMaxSoc: 80)
        XCTAssertEqual(ChargeLimitInsight.classify(dailyMaxSoc: 80), .limitActive)
        XCTAssertEqual(export.chargeLimitState, "limitActive")
        XCTAssertNil(export.cappingAt80ReductionPct)
    }

    func testChargeLimitStateMatchesClassify_highExposure() {
        let export = makeExport(dailyMaxSoc: 96)
        guard case .highExposure(let pct) = ChargeLimitInsight.classify(dailyMaxSoc: 96) else {
            return XCTFail("expected highExposure")
        }
        XCTAssertEqual(export.chargeLimitState, "highExposure")
        XCTAssertEqual(export.cappingAt80ReductionPct, pct)
    }

    func testChargeLimitStateMatchesClassify_normal() {
        let export = makeExport(dailyMaxSoc: 85)
        XCTAssertEqual(ChargeLimitInsight.classify(dailyMaxSoc: 85), .normal)
        XCTAssertEqual(export.chargeLimitState, "normal")
        XCTAssertNil(export.cappingAt80ReductionPct)
    }

    func testChargeLimitStateMatchesClassify_nilSoc() {
        let export = makeExport(dailyMaxSoc: nil)
        XCTAssertEqual(export.chargeLimitState, "normal")
        XCTAssertNil(export.cappingAt80ReductionPct)
    }

    // MARK: - Encoding

    func testSchemaVersionPresentAndIsOne() throws {
        let json = try String(data: encoder().encode(makeExport()), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"schemaVersion\":1"), json)
    }

    func testEncodingIsDeterministic() throws {
        let export = makeExport()
        let a = try encoder().encode(export)
        let b = try encoder().encode(export)
        XCTAssertEqual(a, b)
    }

    func testRawSlopeKIsNotInOutput() throws {
        // calibration.k = 1.42 is set above; it must NOT leak.
        let json = try String(data: encoder().encode(makeExport()), encoding: .utf8)!
        XCTAssertFalse(json.contains("\"k\""), "raw Theil–Sen slope must not be exported: \(json)")
        XCTAssertFalse(json.contains("1.42"), "raw slope value leaked: \(json)")
        XCTAssertFalse(json.lowercased().contains("slope"), json)
        XCTAssertFalse(json.contains("\"rawMultiplier\""), "internal gauge artifact leaked: \(json)")
    }

    func testRoundTripDecodeEqualsOriginal() throws {
        let original = makeExport()
        let data = try encoder().encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FleetMetricsExport.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testRoundTripModeledVariant() throws {
        let original = makeExport(dailyMaxSoc: 80, calibration: .modeled)
        let data = try encoder().encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FleetMetricsExport.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded.calibrationBand)
    }
}
