import Foundation

/// Machine-readable, versioned snapshot of Patina's longevity metrics, written to a stable
/// JSON file so always-plugged remote Macs can be polled (scp/rsync/monitoring) without ever
/// opening the popover.
///
/// Intentionally a FLAT DTO of primitives — NOT the internal engine types made `Codable`.
/// A flat schema keeps the public contract stable across refactors and prevents leaking
/// internal gauge artifacts. In particular the raw Theil–Sen calibration slope `k` is a gated
/// debug-only number and is NEVER exported: only the coarse band + status are honest to publish.
public struct FleetMetricsExport: Codable, Equatable, Sendable {
    /// Bump when the field layout changes incompatibly. Consumers should reject unknown majors.
    public var schemaVersion: Int
    /// The sample time these metrics were derived from (passed in; Core never reads the clock).
    public var generatedAt: Date
    /// App marketing version, e.g. "0.2.0" (CFBundleShortVersionString; passed in).
    public var appVersion: String

    // Battery facts (BMS-reported)
    public var batteryHealthPercent: Int
    public var cycleCount: Int

    // Calendar-aging model (relative reaction-rate multiplier vs ideal idle)
    public var agingMultiplier: Double
    /// "low" / "elevated" / "high" — derived from the displayed multiplier the SAME way the card
    /// band does, so the exported word can never disagree with what the UI shows.
    public var agingBand: String
    /// "temperature" / "charge" / "balanced" — nil when no aging rate is available yet.
    public var dominantDriver: String?

    // Measured-fade calibration (band/status only — raw slope k deliberately omitted)
    public var calibrationStatus: String       // "modeled" / "calibrated"
    public var calibrationBand: String?        // "slower" / "about" / "faster"; nil while modeled

    // State-of-charge habit (from the BMS daily extremes)
    public var dailyMaxSoc: Int?
    public var dailyMinSoc: Int?

    // Native charge-limit insight
    public var chargeLimitState: String        // "limitActive" / "highExposure" / "normal"
    public var cappingAt80ReductionPct: Int?   // only set when highExposure
    public var nativeChargeLimitAvailable: Bool

    // Thermal
    public var batteryTempC: Double?

    // Today's high-charge dwell on AC (seconds)
    public var secondsAbove80OnACToday: Double
    public var secondsAbove95OnACToday: Double

    public init(
        schemaVersion: Int = FleetMetricsExport.currentSchemaVersion,
        generatedAt: Date,
        appVersion: String,
        batteryHealthPercent: Int,
        cycleCount: Int,
        agingMultiplier: Double,
        agingBand: String,
        dominantDriver: String?,
        calibrationStatus: String,
        calibrationBand: String?,
        dailyMaxSoc: Int?,
        dailyMinSoc: Int?,
        chargeLimitState: String,
        cappingAt80ReductionPct: Int?,
        nativeChargeLimitAvailable: Bool,
        batteryTempC: Double?,
        secondsAbove80OnACToday: Double,
        secondsAbove95OnACToday: Double
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.appVersion = appVersion
        self.batteryHealthPercent = batteryHealthPercent
        self.cycleCount = cycleCount
        self.agingMultiplier = agingMultiplier
        self.agingBand = agingBand
        self.dominantDriver = dominantDriver
        self.calibrationStatus = calibrationStatus
        self.calibrationBand = calibrationBand
        self.dailyMaxSoc = dailyMaxSoc
        self.dailyMinSoc = dailyMinSoc
        self.chargeLimitState = chargeLimitState
        self.cappingAt80ReductionPct = cappingAt80ReductionPct
        self.nativeChargeLimitAvailable = nativeChargeLimitAvailable
        self.batteryTempC = batteryTempC
        self.secondsAbove80OnACToday = secondsAbove80OnACToday
        self.secondsAbove95OnACToday = secondsAbove95OnACToday
    }

    public static let currentSchemaVersion = 1

    /// Mirror of `AgingHeroSection`'s band logic: round the multiplier to one decimal (what the
    /// user sees) before banding, so the exported word matches the card at rounding boundaries.
    /// Returns "low" / "elevated" / "high".
    public static func agingBand(forMultiplier multiplier: Double) -> String {
        let shown = (multiplier * 10).rounded() / 10
        if shown >= 3.0 { return "high" }
        if shown >= 1.5 { return "elevated" }
        return "low"
    }

    /// Map a `ChargeLimitInsight.State` to the flat (state string, reductionPct?) pair.
    public static func chargeLimit(from state: ChargeLimitInsight.State) -> (state: String, reductionPct: Int?) {
        switch state {
        case .limitActive: return ("limitActive", nil)
        case .highExposure(let pct): return ("highExposure", pct)
        case .normal: return ("normal", nil)
        }
    }

    /// Pure assembly from the app's already-computed values. No IO, no wall-clock — the timestamp
    /// is passed in. Keeps field derivation honest and matching what the UI shows.
    ///
    /// - Parameters:
    ///   - battery: the current BMS battery facts (health, cycles, SoC extremes).
    ///   - agingRate: the calendar-aging multiplier (nil while still collecting).
    ///   - calibration: the measured-fade calibration result (band/status; raw k is NOT exported).
    ///   - chargeExposure: today's high-charge dwell summary.
    ///   - dailyMaxSoc / dailyMinSoc: BMS daily SoC extremes (drive the charge-limit insight).
    ///   - batteryTempC: canonical BMS pack temperature (batteryDisplayC), or nil.
    ///   - nativeChargeLimitAvailable: whether macOS exposes the native charge-limit toggle.
    ///   - appVersion: CFBundleShortVersionString, e.g. "0.2.0".
    ///   - generatedAt: the snapshot's sampledAt — Core does not call Date().
    public static func from(
        battery: BatteryStatus,
        agingRate: BatteryAgingRate?,
        calibration: BatteryCalibrationResult,
        chargeExposure: ChargeExposureSummary,
        dailyMaxSoc: Int?,
        dailyMinSoc: Int?,
        batteryTempC: Double?,
        nativeChargeLimitAvailable: Bool,
        appVersion: String,
        generatedAt: Date
    ) -> FleetMetricsExport {
        let multiplier = agingRate?.multiplier ?? 1.0
        let limit = chargeLimit(from: ChargeLimitInsight.classify(
            dailyMaxSoc: dailyMaxSoc,
            nativeLimitHolding: battery.nativeLimitHolding))
        let today = chargeExposure.today
        return FleetMetricsExport(
            generatedAt: generatedAt,
            appVersion: appVersion,
            batteryHealthPercent: battery.healthPercent,
            cycleCount: battery.cycleCount,
            agingMultiplier: multiplier,
            agingBand: agingBand(forMultiplier: multiplier),
            dominantDriver: agingRate?.dominantDriver.rawValue,
            calibrationStatus: calibration.status.rawValue,
            calibrationBand: calibration.band?.rawValue,
            dailyMaxSoc: dailyMaxSoc,
            dailyMinSoc: dailyMinSoc,
            chargeLimitState: limit.state,
            cappingAt80ReductionPct: limit.reductionPct,
            nativeChargeLimitAvailable: nativeChargeLimitAvailable,
            batteryTempC: batteryTempC,
            secondsAbove80OnACToday: today.secondsAbove80OnAC,
            secondsAbove95OnACToday: today.secondsAbove95OnAC
        )
    }
}
