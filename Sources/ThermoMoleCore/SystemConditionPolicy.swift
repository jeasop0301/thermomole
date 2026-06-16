import Foundation

public enum SystemConditionLevel: String, Codable, Sendable {
    case normal
    case caution
    case hot
}

public enum SystemConditionPolicy {
    public static func resolve(
        cpuTemperatureC: Double?,
        batteryWarningLevel: TemperatureWarningLevel,
        memoryPressure: MemoryPressure,
        healthBand: HealthBand
    ) -> SystemConditionLevel {
        if batteryWarningLevel == .hot || memoryPressure == .critical || healthBand == .needsAttention {
            return .hot
        }

        if let cpuTemperatureC, cpuTemperatureC >= 95 {
            return .hot
        }

        if batteryWarningLevel == .caution || memoryPressure == .warning || healthBand == .fair {
            return .caution
        }

        if let cpuTemperatureC, cpuTemperatureC >= 85 {
            return .caution
        }

        return .normal
    }
}
