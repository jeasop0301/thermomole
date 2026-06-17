import Foundation

public enum LongevityNotification: String, Codable, Equatable, Sendable, CaseIterable {
    case chargingWhileHot
    case sustainedHotBattery
    case highSoCDwell
    case lowStorage
    case sustainedHotCPU
    case highCycleRate

    public var title: String {
        switch self {
        case .chargingWhileHot: "Charging while hot"
        case .sustainedHotBattery: "Battery running hot"
        case .highSoCDwell: "Held at high charge"
        case .lowStorage: "Storage almost full"
        case .sustainedHotCPU: "CPU running hot"
        case .highCycleRate: "High charge cycles"
        }
    }

    public var body: String {
        switch self {
        case .chargingWhileHot: "Unplug to let the battery cool — heat plus charging ages it fastest."
        case .sustainedHotBattery: "The battery has been hot for a while. Ease the load to cool it down."
        case .highSoCDwell: "It's been near full on AC for hours. Unplug around 80% when you can."
        case .lowStorage: "Low free space forces swap to the SSD. Free up some room."
        case .sustainedHotCPU: "CPU has been very hot. Ease the load to cool it down."
        case .highCycleRate: "Charge cycles are climbing fast. Fewer full charge/discharge swings help."
        }
    }
}

/// Quiet-hours window by hour-of-day; wraps midnight when start > end (e.g. 22→7).
public struct QuietHours: Equatable, Sendable {
    public var startHour: Int
    public var endHour: Int

    public init(startHour: Int, endHour: Int) {
        self.startHour = startHour
        self.endHour = endHour
    }

    public func contains(hour h: Int) -> Bool {
        if startHour <= endHour { return h >= startHour && h < endHour }
        return h >= startHour || h < endHour
    }
}

/// Pure decision for which longevity notifications to fire now: de-spams with a per-kind
/// throttle and honours quiet hours, so alerts stay rare and trustworthy.
public enum NotificationPolicy {
    public static let defaultThrottle: TimeInterval = 2 * 3600  // 2 hours

    public static func due(
        active: Set<LongevityNotification>,
        lastSent: [LongevityNotification: Date],
        now: Date,
        throttle: TimeInterval = NotificationPolicy.defaultThrottle,
        quietHours: QuietHours? = nil,
        calendar: Calendar = .current
    ) -> [LongevityNotification] {
        if let quietHours, quietHours.contains(hour: calendar.component(.hour, from: now)) {
            return []
        }
        return active
            .filter { notification in
                guard let last = lastSent[notification] else { return true }
                return now.timeIntervalSince(last) >= throttle
            }
            .sorted { $0.rawValue < $1.rawValue }
    }
}

public extension NotificationPolicy {
    /// Pure decision of which longevity notifications are currently active, given a snapshot
    /// and the day's exposure/longevity context. Throttling and quiet hours are applied
    /// separately by `due(...)`.
    static func activeNotifications(
        snapshot: SystemSnapshot,
        todayChargeExposure: ChargeExposureSummary,
        todayCPUExposure: CPUExposureSummary,
        batteryLongevity: BatteryLongevityReport?
    ) -> Set<LongevityNotification> {
        var active = Set<LongevityNotification>()
        if StatusBrief(snapshot: snapshot).isChargingWhileHot { active.insert(.chargingWhileHot) }
        if snapshot.thermal.batteryWarningLevel == .hot { active.insert(.sustainedHotBattery) }
        if todayChargeExposure.today.secondsAbove95OnAC >= 2 * 3600 { active.insert(.highSoCDwell) }
        if (100 - snapshot.disk.usedPercent) < 10 { active.insert(.lowStorage) }
        if todayCPUExposure.today.secondsAbove95 >= 30 * 60 { active.insert(.sustainedHotCPU) }
        if batteryLongevity?.alerts.contains(.highCycleRate) == true { active.insert(.highCycleRate) }
        return active
    }
}
