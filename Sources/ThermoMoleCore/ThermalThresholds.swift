import Foundation

/// Single source of truth for thermal warning thresholds (°C).
/// Replaces literals previously duplicated across ThermalPolicy, HealthScorer,
/// StatusBrief, and SystemConditionPolicy. Not user-configurable.
public enum ThermalThresholds {
    public static let batteryCautionC: Double = 35.0
    public static let batteryHotC: Double = 40.0
    public static let cpuWarmC: Double = 85.0
    public static let cpuHotC: Double = 95.0
}
