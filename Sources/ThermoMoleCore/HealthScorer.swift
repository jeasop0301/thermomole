import Foundation

public enum HealthBand: String, Codable, Sendable {
    case excellent
    case good
    case fair
    case needsAttention
}

public enum HealthIssue: String, Codable, Hashable, Sendable {
    case highCPU
    case cpuWarm
    case cpuHot
    case highMemory
    case diskAlmostFull
    case batteryWarm
    case batteryHot
    case restartRecommended
}

public struct HealthScore: Codable, Equatable, Sendable {
    public var value: Int
    public var band: HealthBand
    public var issues: Set<HealthIssue>
}

public enum HealthScorer {
    public static func score(
        cpuUsagePercent: Double,
        memoryUsedPercent: Int,
        diskUsedPercent: Double,
        batteryTemperatureC: Double?,
        cpuTemperatureC: Double? = nil,
        uptimeSeconds: UInt64
    ) -> HealthScore {
        var raw = 100.0
        var issues = Set<HealthIssue>()

        if cpuUsagePercent > 85 {
            raw -= 18
            issues.insert(.highCPU)
        } else if cpuUsagePercent > 60 {
            raw -= 8
        }

        if memoryUsedPercent >= 88 {
            raw -= 18
            issues.insert(.highMemory)
        } else if memoryUsedPercent >= 71 {
            raw -= 8
        }

        if diskUsedPercent >= 93 {
            raw -= 16
            issues.insert(.diskAlmostFull)
        } else if diskUsedPercent >= 80 {
            raw -= 7
        }

        if let batteryTemperatureC {
            if batteryTemperatureC >= ThermalThresholds.batteryHotC {
                raw -= 18
                issues.insert(.batteryHot)
            } else if batteryTemperatureC >= ThermalThresholds.batteryCautionC {
                raw -= 7
                issues.insert(.batteryWarm)
            }
        }

        if let cpuTemperatureC {
            if cpuTemperatureC >= ThermalThresholds.cpuHotC {
                raw -= 18
                issues.insert(.cpuHot)
            } else if cpuTemperatureC >= ThermalThresholds.cpuWarmC {
                raw -= 7
                issues.insert(.cpuWarm)
            }
        }

        if uptimeSeconds > 14 * 86_400 {
            raw -= 3
            issues.insert(.restartRecommended)
        } else if uptimeSeconds > 7 * 86_400 {
            raw -= 1
        }

        let value = max(0, min(100, Int(raw.rounded())))
        return HealthScore(value: value, band: band(for: value), issues: issues)
    }

    private static func band(for value: Int) -> HealthBand {
        if value >= 85 { return .excellent }
        if value >= 65 { return .good }
        if value >= 45 { return .fair }
        return .needsAttention
    }
}
