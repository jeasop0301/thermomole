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
    /// `true` when on AC power with the battery at caution level or above (≥35°C). Keyed off AC
    /// power rather than `isCharging`, so it still fires when the pack is topped off / holding at
    /// 100% on AC — the worst aging case. Fires earlier than `.hot` (≥40°C); the banner reads this.
    public var isChargingWhileHot: Bool

    public var prioritySignal: StatusBriefSignal? {
        guard let prioritySignalID else { return nil }
        return signals.first { $0.id == prioritySignalID }
    }

    public init(snapshot: SystemSnapshot) {
        isChargingWhileHot = snapshot.battery.isOnACPower && snapshot.thermal.batteryWarningLevel != .normal
        signals = [
            StatusBriefSignal(
                id: "battery",
                title: NSLocalizedString("Battery", comment: ""),
                value: StatusBrief.formatTemperature(snapshot.thermal.batteryDisplayC),
                detail: snapshot.thermal.batteryTemperatureSource == .ioregTemperature ? NSLocalizedString("Physical pack", comment: "") : NSLocalizedString("Thermal sensor", comment: "")
            ),
            StatusBriefSignal(
                id: "cpu",
                title: NSLocalizedString("CPU", comment: ""),
                value: StatusBrief.formatTemperature(snapshot.thermal.cpuDisplayC),
                detail: snapshot.thermal.cpuTemperatureSource == .cpuDieHotspot ? NSLocalizedString("Die hotspot", comment: "") : NSLocalizedString("Average sensor", comment: "")
            ),
            StatusBriefSignal(
                id: "memory",
                title: NSLocalizedString("Memory", comment: ""),
                value: "\(snapshot.memory.usedPercent)%",
                detail: StatusBrief.localizedPressure(snapshot.memory.pressure)
            )
        ]

        if snapshot.memory.pressure == .critical {
            mood = .hot
            title = NSLocalizedString("Memory pressure is critical", comment: "")
            detail = String(format: NSLocalizedString("%d%% memory used. Review top processes before cleanup actions.", comment: ""), snapshot.memory.usedPercent)
            prioritySignalID = "memory"
            return
        }

        if snapshot.thermal.batteryWarningLevel == .hot {
            mood = .hot
            title = NSLocalizedString("Battery needs a cooldown", comment: "")
            detail = String(format: NSLocalizedString("Physical battery temperature is at %@. Reduce charging heat and workload.", comment: ""), StatusBrief.formatTemperature(snapshot.thermal.batteryDisplayC))
            prioritySignalID = "battery"
            return
        }

        if let cpu = snapshot.thermal.cpuDisplayC, cpu >= ThermalThresholds.cpuHotC {
            mood = .hot
            title = NSLocalizedString("CPU is running hot", comment: "")
            detail = String(format: NSLocalizedString("CPU hotspot is at %@. Let sustained work settle.", comment: ""), StatusBrief.formatTemperature(snapshot.thermal.cpuDisplayC))
            prioritySignalID = "cpu"
            return
        }

        if snapshot.memory.pressure == .warning {
            mood = .watch
            title = NSLocalizedString("Memory is getting tight", comment: "")
            detail = String(format: NSLocalizedString("%d%% memory used. Watch top processes before taking action.", comment: ""), snapshot.memory.usedPercent)
            prioritySignalID = "memory"
            return
        }

        if snapshot.thermal.batteryWarningLevel == .caution {
            mood = .watch
            title = NSLocalizedString("Battery is warming", comment: "")
            detail = String(format: NSLocalizedString("Physical battery crossed the %d° caution line. Keep airflow clear and avoid extra charging heat.", comment: ""), Int(ThermalThresholds.batteryCautionC))
            prioritySignalID = "battery"
            return
        }

        if let cpu = snapshot.thermal.cpuDisplayC, cpu >= ThermalThresholds.cpuWarmC {
            mood = .watch
            title = NSLocalizedString("CPU warmth is elevated", comment: "")
            detail = String(format: NSLocalizedString("CPU hotspot is at %@. Sustained load may keep it warm.", comment: ""), StatusBrief.formatTemperature(snapshot.thermal.cpuDisplayC))
            prioritySignalID = "cpu"
            return
        }

        mood = .steady
        title = NSLocalizedString("Everything is steady", comment: "")
        detail = String(format: NSLocalizedString("%@ battery, %@ CPU, %d%% memory.", comment: ""), StatusBrief.formatTemperature(snapshot.thermal.batteryDisplayC), StatusBrief.formatTemperature(snapshot.thermal.cpuDisplayC), snapshot.memory.usedPercent)
        prioritySignalID = nil
    }

    private static func localizedPressure(_ pressure: MemoryPressure) -> String {
        switch pressure {
        case .normal:
            return NSLocalizedString("Normal", comment: "")
        case .warning:
            return NSLocalizedString("Warning", comment: "")
        case .critical:
            return NSLocalizedString("Critical", comment: "")
        }
    }

    private static func formatTemperature(_ value: Double?) -> String {
        guard let value else { return "--°" }
        return String(format: "%.1f°", value)
    }
}
