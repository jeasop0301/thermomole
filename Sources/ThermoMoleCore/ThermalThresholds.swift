import Foundation

/// Single source of truth for thermal warning thresholds (°C).
/// Replaces literals previously duplicated across ThermalPolicy, HealthScorer,
/// StatusBrief, and SystemConditionPolicy. Not user-configurable.
public enum ThermalThresholds {
    public static let batteryCautionC: Double = 42.0   // was 35 — instantaneous warning
    public static let batteryHotC: Double = 48.0       // was 40
    public static let batteryExposureWarmC: Double = 40.0  // dwell tracking band
    public static let batteryExposureHotC: Double = 45.0
    public static let cpuWarmC: Double = 85.0
    public static let cpuHotC: Double = 95.0
}
