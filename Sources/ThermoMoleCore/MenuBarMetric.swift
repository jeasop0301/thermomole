import Foundation

public enum MenuBarMetric: String, CaseIterable, Codable, Identifiable, Sendable {
    case cpuTemperature
    case batteryTemperature
    case memoryPercent
    case cpuUsage
    case diskActivity
    case networkActivity

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .cpuTemperature: "CPU Temp"
        case .batteryTemperature: "Battery Temp"
        case .memoryPercent: "RAM"
        case .cpuUsage: "CPU"
        case .diskActivity: "Disk"
        case .networkActivity: "Network"
        }
    }

    public static let defaultMetrics: [MenuBarMetric] = [
        .cpuTemperature,
        .batteryTemperature,
        .memoryPercent
    ]

    public static func sanitized(_ metrics: [MenuBarMetric]) -> [MenuBarMetric] {
        var unique = [MenuBarMetric]()
        for metric in metrics where !unique.contains(metric) {
            unique.append(metric)
            if unique.count == 5 { break }
        }
        return unique.isEmpty ? defaultMetrics : unique
    }

    public static func move(
        _ metric: MenuBarMetric,
        in metrics: [MenuBarMetric],
        direction: MenuBarMetricMoveDirection
    ) -> [MenuBarMetric] {
        var next = metrics
        guard let index = next.firstIndex(of: metric) else { return metrics }
        let targetIndex = switch direction {
        case .up: index - 1
        case .down: index + 1
        }
        guard next.indices.contains(targetIndex) else { return metrics }
        next.swapAt(index, targetIndex)
        return next
    }
}

public enum MenuBarMetricMoveDirection: Sendable {
    case up
    case down
}

public enum MenuBarMetricStorage {
    public static func decode(_ rawValues: [String]) -> [MenuBarMetric] {
        MenuBarMetric.sanitized(rawValues.compactMap(MenuBarMetric.init(rawValue:)))
    }

    public static func encode(_ metrics: [MenuBarMetric]) -> [String] {
        MenuBarMetric.sanitized(metrics).map(\.rawValue)
    }

    public static func normalizedRawValues(from rawValues: [String]) -> [String] {
        encode(decode(rawValues))
    }

    public static func needsRewrite(rawValues: [String], normalizedMetrics: [MenuBarMetric]) -> Bool {
        rawValues != encode(normalizedMetrics)
    }
}

public enum MenuBarTitleFormatter {
    public static func title(for snapshot: SystemSnapshot, metrics: [MenuBarMetric]) -> String {
        MenuBarMetric.sanitized(metrics).map { metric in
            switch metric {
            case .cpuTemperature:
                return "CPU \(formatTemperature(snapshot.thermal.cpuDisplayC))"
            case .batteryTemperature:
                return "BAT \(formatTemperature(snapshot.thermal.batteryDisplayC))"
            case .memoryPercent:
                return "RAM \(snapshot.memory.usedPercent)%"
            case .cpuUsage:
                return "CPU \(Int(snapshot.cpu.usagePercent.rounded()))%"
            case .diskActivity:
                return "DSK \(Int(snapshot.disk.usedPercent.rounded()))%"
            case .networkActivity:
                return "NET \(formatBytes(snapshot.network.receivedBytesPerSecond))/s"
            }
        }.joined(separator: " · ")
    }

    private static func formatTemperature(_ value: Double?) -> String {
        guard let value else { return "--°" }
        return String(format: "%.1f°", value)
    }

    private static func formatBytes(_ value: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var amount = Double(value)
        var index = 0
        while amount >= 1024, index < units.count - 1 {
            amount /= 1024
            index += 1
        }
        return index == 0 ? "\(Int(amount)) \(units[index])" : String(format: "%.1f %@", amount, units[index])
    }
}

public struct MenuBarPresentation: Equatable, Sendable {
    public var title: String
    public var visibleTitle: String
    public var toolTip: String
    public var accessibilityLabel: String
    public var freshnessLevel: StatusFreshnessLevel

    public init(snapshot: SystemSnapshot, metrics: [MenuBarMetric], now: Date = Date()) {
        title = MenuBarTitleFormatter.title(for: snapshot, metrics: metrics)
        let freshness = StatusFreshness(sampledAt: snapshot.sampledAt, now: now)
        freshnessLevel = freshness.level
        visibleTitle = "\(Self.statusPrefix(for: freshness.level)) \(title)"
        let batterySource = Self.batterySourceLabel(snapshot.thermal.batteryTemperatureSource)
        let cpuSource = Self.cpuSourceLabel(snapshot.thermal.cpuTemperatureSource)
        let sampledAt = ISO8601DateFormatter().string(from: snapshot.sampledAt)

        toolTip = [
            "ThermoMole",
            title,
            "Freshness: \(freshness.title) · \(freshness.detail)",
            "Battery: \(batterySource)",
            "CPU: \(cpuSource)",
            "Updated: \(sampledAt)"
        ].joined(separator: "\n")

        accessibilityLabel = [
            "ThermoMole status",
            freshness.title.lowercased(),
            "CPU \(Self.accessibleTemperature(snapshot.thermal.cpuDisplayC)), \(cpuSource.lowercased())",
            "battery \(Self.accessibleTemperature(snapshot.thermal.batteryDisplayC)), \(batterySource.lowercased())",
            "memory \(snapshot.memory.usedPercent) percent, \(snapshot.memory.pressure.rawValue) pressure"
        ].joined(separator: ", ")
    }

    private static func accessibleTemperature(_ value: Double?) -> String {
        guard let value else { return "unavailable" }
        return String(format: "%.1f degrees", value)
    }

    private static func statusPrefix(for level: StatusFreshnessLevel) -> String {
        switch level {
        case .live, .updating: "●"
        case .stale: "!"
        }
    }

    private static func batterySourceLabel(_ source: BatteryTemperatureSource) -> String {
        switch source {
        case .unavailable: "Unavailable"
        case .smcCellMax: "SMC cell max"
        case .ioregTemperature: "Physical pack"
        }
    }

    private static func cpuSourceLabel(_ source: CPUTemperatureSource) -> String {
        switch source {
        case .unavailable: "Unavailable"
        case .cpuDieHotspot: "Die hotspot"
        case .cpuAverage: "Average sensor"
        }
    }
}
