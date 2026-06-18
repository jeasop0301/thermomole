import Foundation

public enum MenuBarMetric: String, CaseIterable, Codable, Identifiable, Sendable {
    case cpuTemperature
    case batteryTemperature
    case memoryPercent
    case cpuUsage

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .cpuTemperature: "CPU Temp"
        case .batteryTemperature: "Battery Temp"
        case .memoryPercent: "RAM"
        case .cpuUsage: "CPU"
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

public struct MenuBarSegment: Equatable, Sendable {
    public let metric: MenuBarMetric
    public let text: String
    public let range: NSRange

    public init(metric: MenuBarMetric, text: String, range: NSRange) {
        self.metric = metric
        self.text = text
        self.range = range
    }
}

public enum MenuBarTitleFormatter {
    /// Inter-token separator used in the joined title; segment NSRange offsets account for its length.
    public static let separator = " · "

    public static func title(for snapshot: SystemSnapshot, metrics: [MenuBarMetric]) -> String {
        segments(for: snapshot, metrics: metrics).map(\.text).joined(separator: separator)
    }

    public static func segments(for snapshot: SystemSnapshot, metrics: [MenuBarMetric]) -> [MenuBarSegment] {
        let sanitized = MenuBarMetric.sanitized(metrics)
        let sepLength = (separator as NSString).length
        var result: [MenuBarSegment] = []
        var location = 0
        for (index, metric) in sanitized.enumerated() {
            let text = tokenText(for: metric, snapshot: snapshot)
            let length = (text as NSString).length
            result.append(MenuBarSegment(metric: metric, text: text, range: NSRange(location: location, length: length)))
            location += length
            if index < sanitized.count - 1 { location += sepLength }
        }
        return result
    }

    private static func tokenText(for metric: MenuBarMetric, snapshot: SystemSnapshot) -> String {
        switch metric {
        case .cpuTemperature: return "CPU \(formatTemperature(snapshot.thermal.cpuDisplayC))"
        case .batteryTemperature: return "BAT \(formatTemperature(snapshot.thermal.batteryDisplayC))"
        case .memoryPercent: return "RAM \(snapshot.memory.usedPercent)%"
        case .cpuUsage: return "CPU \(Int(snapshot.cpu.usagePercent.rounded()))%"
        }
    }

    private static func formatTemperature(_ value: Double?) -> String {
        guard let value else { return "--°" }
        return String(format: "%.1f°", value)
    }
}

public struct MenuBarPresentation: Equatable, Sendable {
    public var title: String
    public var visibleTitle: String
    public var toolTip: String
    public var accessibilityLabel: String
    public var freshnessLevel: StatusFreshnessLevel
    public var segments: [MenuBarSegment]

    public init(snapshot: SystemSnapshot, metrics: [MenuBarMetric], now: Date = Date()) {
        segments = MenuBarTitleFormatter.segments(for: snapshot, metrics: metrics)
        title = segments.map(\.text).joined(separator: MenuBarTitleFormatter.separator)
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

    public var batterySegment: MenuBarSegment? {
        segments.first { $0.metric == .batteryTemperature }
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
