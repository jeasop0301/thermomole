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

        if let cpuTemperatureC, cpuTemperatureC >= ThermalThresholds.cpuHotC {
            return .hot
        }

        if batteryWarningLevel == .caution || memoryPressure == .warning || healthBand == .fair {
            return .caution
        }

        if let cpuTemperatureC, cpuTemperatureC >= ThermalThresholds.cpuWarmC {
            return .caution
        }

        return .normal
    }
}

extension SystemConditionPolicy {
    public static func batteryTint(for level: TemperatureWarningLevel) -> SystemConditionLevel {
        switch level {
        case .normal: .normal
        case .caution: .caution
        case .hot: .hot
        }
    }
}
