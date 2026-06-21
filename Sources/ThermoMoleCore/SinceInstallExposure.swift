import Foundation

/// "Since install" cumulative exposure totals, assembled from the two forward-only cumulatives
/// (thermal + charge). Seconds are converted to hours for display. `sinceDay` is the earliest
/// firstDay of the two cumulatives — nil when nothing has been counted yet (no completed days),
/// which the UI uses to hide the panel.
///
/// Honest by construction: only totals we can actually sum (no time-weighted average SoC — there
/// is no dt denominator to divide by, so we don't fake one). Label is "since install", not
/// "lifetime": we only measure since the app first started recording.
public struct SinceInstallExposure: Equatable, Sendable {
    public var sinceDay: String?
    public var hoursAbove40: Double
    public var hoursAbove45: Double
    public var hoursAbove80OnAC: Double
    public var hoursAbove95OnAC: Double

    public init(
        sinceDay: String? = nil,
        hoursAbove40: Double = 0,
        hoursAbove45: Double = 0,
        hoursAbove80OnAC: Double = 0,
        hoursAbove95OnAC: Double = 0
    ) {
        self.sinceDay = sinceDay
        self.hoursAbove40 = hoursAbove40
        self.hoursAbove45 = hoursAbove45
        self.hoursAbove80OnAC = hoursAbove80OnAC
        self.hoursAbove95OnAC = hoursAbove95OnAC
    }

    public static let empty = SinceInstallExposure()

    public static func from(
        thermal: CumulativeThermalExposure,
        charge: CumulativeChargeExposure
    ) -> SinceInstallExposure {
        let earliest = [thermal.firstDay, charge.firstDay].compactMap { $0 }.min()
        return SinceInstallExposure(
            sinceDay: earliest,
            hoursAbove40: thermal.secondsAbove40 / 3600.0,
            hoursAbove45: thermal.secondsAbove45 / 3600.0,
            hoursAbove80OnAC: charge.secondsAbove80OnAC / 3600.0,
            hoursAbove95OnAC: charge.secondsAbove95OnAC / 3600.0
        )
    }
}
