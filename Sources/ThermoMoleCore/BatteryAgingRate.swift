import Foundation

/// Fact-based real-time CALENDAR aging-rate multiplier vs an ideal idle baseline (25°C, 50% SoC).
/// multiplier = g(T)·f(SoC): Arrhenius temperature factor (Ea=0.55 eV) × literature SoC factor.
/// It is a relative reaction-RATE ratio under published kinetics — NOT a capacity measurement,
/// not lifetime total loss, not cycle aging.
public struct BatteryAgingRate: Equatable, Sendable {
    public enum Band: String, Sendable { case low, moderate, high }
    public enum Driver: String, Sendable { case temperature, charge, balanced }

    public var multiplier: Double
    public var rawMultiplier: Double
    public var band: Band
    public var dominantDriver: Driver
    public var coldChargeCaution: Bool

    public init(multiplier: Double, rawMultiplier: Double, band: Band, dominantDriver: Driver, coldChargeCaution: Bool) {
        self.multiplier = multiplier; self.rawMultiplier = rawMultiplier
        self.band = band; self.dominantDriver = dominantDriver; self.coldChargeCaution = coldChargeCaution
    }

    // Arrhenius instantaneous rate ratio. Ea=0.55 eV=53067 J/mol, R=8.314462618, Ea/R=6382.485, Tref=298.15K.
    public static func tempFactor(_ tC: Double) -> Double {
        exp(6382.485 * (1.0 / 298.15 - 1.0 / (tC + 273.15)))
    }

    // Piecewise-linear SoC factor, normalized 50%→1.0. Anchors 20→0.65,50→1.0,80→1.55,90→1.75,100→1.95.
    public static func socFactor(_ socPercent: Double) -> Double {
        let pts: [(Double, Double)] = [(20, 0.65), (50, 1.00), (80, 1.55), (90, 1.75), (100, 1.95)]
        if socPercent <= pts.first!.0 { return pts.first!.1 }
        if socPercent >= pts.last!.0 { return pts.last!.1 }
        for i in 1..<pts.count where socPercent <= pts[i].0 {
            let (x0, y0) = pts[i-1]; let (x1, y1) = pts[i]
            return y0 + (y1 - y0) * (socPercent - x0) / (x1 - x0)
        }
        return pts.last!.1
    }

    public static func evaluate(cellTempC: Double?, socPercent: Double?, isCharging: Bool) -> BatteryAgingRate? {
        guard let t = cellTempC, let soc = socPercent else { return nil }
        let raw = tempFactor(t) * socFactor(soc)
        let coldCaution = t < 20 && isCharging
        var display = t < 20 ? max(1.0, raw) : raw
        display = min(10.0, max(0.3, display))
        if display >= 0.9 && display <= 1.1 { display = 1.0 }
        let band: Band = display > 3.0 ? .high : (display >= 1.5 ? .moderate : .low)
        let tf = tempFactor(t), sf = socFactor(soc)
        let driver: Driver
        if tf >= 1.3 && sf >= 1.3 { driver = .balanced }
        else if tf >= sf { driver = .temperature } else { driver = .charge }
        return BatteryAgingRate(multiplier: display, rawMultiplier: raw, band: band, dominantDriver: driver, coldChargeCaution: coldCaution)
    }
}
