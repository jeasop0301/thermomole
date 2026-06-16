import Foundation

/// Pure mapping of a battery temperature onto a ring gauge: a 0...1 fill fraction across a
/// fixed display scale, plus the warning level. UI-framework-free and unit-tested.
public struct BatteryRingScale: Equatable, Sendable {
    public static let minC = 20.0
    public static let maxC = 45.0

    public let fraction: Double
    public let level: TemperatureWarningLevel

    public init(temperatureC: Double?) {
        let t = temperatureC ?? Self.minC
        fraction = min(1, max(0, (t - Self.minC) / (Self.maxC - Self.minC)))
        level = TemperatureWarningLevel.batteryLevel(for: temperatureC)
    }
}
