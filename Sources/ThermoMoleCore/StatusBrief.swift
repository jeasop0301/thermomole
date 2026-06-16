import Foundation

public enum StatusBriefMood: String, Codable, Sendable {
    case steady
    case watch
    case hot
}

public struct StatusBriefSignal: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var value: String
    public var detail: String

    public init(id: String, title: String, value: String, detail: String) {
        self.id = id
        self.title = title
        self.value = value
        self.detail = detail
    }
}

public struct StatusBrief: Equatable, Sendable {
    public var mood: StatusBriefMood
    public var title: String
    public var detail: String
    public var signals: [StatusBriefSignal]
    public var prioritySignalID: String?

    public var prioritySignal: StatusBriefSignal? {
        guard let prioritySignalID else { return nil }
        return signals.first { $0.id == prioritySignalID }
    }

    public init(snapshot: SystemSnapshot) {
        signals = [
            StatusBriefSignal(
                id: "battery",
                title: "Battery",
                value: StatusBrief.formatTemperature(snapshot.thermal.batteryDisplayC),
                detail: snapshot.thermal.batteryTemperatureSource == .ioregTemperature ? "Physical pack" : "Thermal sensor"
            ),
            StatusBriefSignal(
                id: "cpu",
                title: "CPU",
                value: StatusBrief.formatTemperature(snapshot.thermal.cpuDisplayC),
                detail: snapshot.thermal.cpuTemperatureSource == .cpuDieHotspot ? "Die hotspot" : "Average sensor"
            ),
            StatusBriefSignal(
                id: "memory",
                title: "Memory",
                value: "\(snapshot.memory.usedPercent)%",
                detail: snapshot.memory.pressure.rawValue.capitalized
            )
        ]

        if snapshot.memory.pressure == .critical {
            mood = .hot
            title = "Memory pressure is critical"
            detail = "\(snapshot.memory.usedPercent)% memory used. Review top processes before cleanup actions."
            prioritySignalID = "memory"
            return
        }

        if snapshot.thermal.batteryWarningLevel == .hot {
            mood = .hot
            title = "Battery needs a cooldown"
            detail = "Physical battery temperature is at \(StatusBrief.formatTemperature(snapshot.thermal.batteryDisplayC)). Reduce charging heat and workload."
            prioritySignalID = "battery"
            return
        }

        if let cpu = snapshot.thermal.cpuDisplayC, cpu >= 95 {
            mood = .hot
            title = "CPU is running hot"
            detail = "CPU hotspot is at \(StatusBrief.formatTemperature(snapshot.thermal.cpuDisplayC)). Let sustained work settle."
            prioritySignalID = "cpu"
            return
        }

        if snapshot.memory.pressure == .warning {
            mood = .watch
            title = "Memory is getting tight"
            detail = "\(snapshot.memory.usedPercent)% memory used. Watch top processes before taking action."
            prioritySignalID = "memory"
            return
        }

        if snapshot.thermal.batteryWarningLevel == .caution {
            mood = .watch
            title = "Battery is warming"
            detail = "Physical battery crossed the 35° caution line. Keep airflow clear and avoid extra charging heat."
            prioritySignalID = "battery"
            return
        }

        if let cpu = snapshot.thermal.cpuDisplayC, cpu >= 85 {
            mood = .watch
            title = "CPU warmth is elevated"
            detail = "CPU hotspot is at \(StatusBrief.formatTemperature(snapshot.thermal.cpuDisplayC)). Sustained load may keep it warm."
            prioritySignalID = "cpu"
            return
        }

        mood = .steady
        title = "Everything is steady"
        detail = "\(StatusBrief.formatTemperature(snapshot.thermal.batteryDisplayC)) battery, \(StatusBrief.formatTemperature(snapshot.thermal.cpuDisplayC)) CPU, \(snapshot.memory.usedPercent)% memory."
        prioritySignalID = nil
    }

    private static func formatTemperature(_ value: Double?) -> String {
        guard let value else { return "--°" }
        return String(format: "%.1f°", value)
    }
}
