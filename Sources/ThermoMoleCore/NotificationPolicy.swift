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
        case .chargingWhileHot: NSLocalizedString("Charging while hot", comment: "")
        case .sustainedHotBattery: NSLocalizedString("Battery running hot", comment: "")
        case .highSoCDwell: NSLocalizedString("Held at high charge", comment: "")
        case .lowStorage: NSLocalizedString("Storage almost full", comment: "")
        case .sustainedHotCPU: NSLocalizedString("CPU running hot", comment: "")
        case .highCycleRate: NSLocalizedString("High charge cycles", comment: "")
        }
    }

    /// Notification body, OS-aware. On macOS 26.4+ (`nativeChargeLimitAvailable`) the high-SoC
    /// dwell nudge points at the native Charge Limit toggle instead of telling the user to unplug.
    /// Posted directly via UNUserNotificationCenter (no SwiftUI LocalizedStringKey layer), so each
    /// string is wrapped in NSLocalizedString to localize from the .app bundle.
    public func body(nativeChargeLimitAvailable: Bool) -> String {
        switch self {
        case .chargingWhileHot:
            return NSLocalizedString("Unplug to let the battery cool — heat plus charging ages it fastest.", comment: "")
        case .sustainedHotBattery:
            return NSLocalizedString("The battery has been hot for a while. Ease the load to cool it down.", comment: "")
        case .highSoCDwell:
            return nativeChargeLimitAvailable
                ? NSLocalizedString("It's been near full on AC for hours. Turn on Charge Limit in Settings → Battery to hold it lower.", comment: "")
                : NSLocalizedString("It's been near full on AC for hours. Unplug around 80% when you can.", comment: "")
        case .lowStorage:
            return NSLocalizedString("Low free space forces swap to the SSD. Free up some room.", comment: "")
        case .sustainedHotCPU:
            return NSLocalizedString("CPU has been very hot. Ease the load to cool it down.", comment: "")
        case .highCycleRate:
            return NSLocalizedString("Charge cycles are climbing fast. Fewer full charge/discharge swings help.", comment: "")
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
        batteryLongevity: BatteryLongevityReport?,
        dailyMaxSoc: Int? = nil
    ) -> Set<LongevityNotification> {
        var active = Set<LongevityNotification>()
        if StatusBrief(snapshot: snapshot).isChargingWhileHot { active.insert(.chargingWhileHot) }
        if snapshot.thermal.batteryWarningLevel == .hot { active.insert(.sustainedHotBattery) }
        // Skip the high-SoC dwell nudge when a charge limit is effectively holding the pack down
        // (inferred via ChargeLimitInsight): a limit is already doing the job, so don't nag.
        let limitActive = ChargeLimitInsight.classify(dailyMaxSoc: dailyMaxSoc) == .limitActive
        if !limitActive && todayChargeExposure.today.secondsAbove95OnAC >= 2 * 3600 { active.insert(.highSoCDwell) }
        if (100 - snapshot.disk.usedPercent) < 10 { active.insert(.lowStorage) }
        if todayCPUExposure.today.secondsAbove95 >= 30 * 60 { active.insert(.sustainedHotCPU) }
        if batteryLongevity?.alerts.contains(.highCycleRate) == true { active.insert(.highCycleRate) }
        return active
    }
}
