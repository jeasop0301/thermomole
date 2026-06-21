import Foundation

public enum LongevityFactorStatus: String, Equatable, Sendable, Codable {
    case good, watch, poor
}

public struct LongevityFactor: Equatable, Sendable, Identifiable {
    public var id: String           // "battery" | "heat" | "charging" | "storage" | "memory"
    public var title: String
    public var status: LongevityFactorStatus
    public var summary: String

    public init(id: String, title: String, status: LongevityFactorStatus, summary: String) {
        self.id = id
        self.title = title
        self.status = status
        self.summary = summary
    }
}

public enum LongevityActionSeverity: Int, Equatable, Sendable, Codable {
    case info = 0, suggest = 1, urgent = 2
}

public struct LongevityAction: Equatable, Sendable, Identifiable {
    public var id: String
    public var severity: LongevityActionSeverity
    public var title: String        // plain-language imperative
    public var detail: String

    public init(id: String, severity: LongevityActionSeverity, title: String, detail: String) {
        self.id = id
        self.severity = severity
        self.title = title
        self.detail = detail
    }
}

/// All signals the advisor needs, as plain values so the advisor stays pure/testable.
public struct LongevitySignals: Equatable, Sendable {
    public var batteryLongevity: BatteryLongevityReport?
    public var batteryExposure: ThermalExposureSummary
    public var cpuExposure: CPUExposureSummary
    public var chargeExposure: ChargeExposureSummary
    public var diskFreePercent: Double
    public var diskUsedPercent: Double
    public var memoryPressure: String
    public var isChargingWhileHot: Bool
    public var batteryTempC: Double?
    public var ssdTempC: Double?
    /// Highest state-of-charge the BMS recorded recently (from ioreg BatteryData). nil = unknown.
    /// Drives the native charge-limit nudge: high values mean the user keeps the pack near full.
    public var dailyMaxSoc: Int?

    public init(
        batteryLongevity: BatteryLongevityReport? = nil,
        batteryExposure: ThermalExposureSummary = .empty,
        cpuExposure: CPUExposureSummary = .empty,
        chargeExposure: ChargeExposureSummary = .empty,
        diskFreePercent: Double = 50,
        diskUsedPercent: Double = 50,
        memoryPressure: String = "normal",
        isChargingWhileHot: Bool = false,
        batteryTempC: Double? = nil,
        ssdTempC: Double? = nil,
        dailyMaxSoc: Int? = nil
    ) {
        self.batteryLongevity = batteryLongevity
        self.batteryExposure = batteryExposure
        self.cpuExposure = cpuExposure
        self.chargeExposure = chargeExposure
        self.diskFreePercent = diskFreePercent
        self.diskUsedPercent = diskUsedPercent
        self.memoryPressure = memoryPressure
        self.isChargingWhileHot = isChargingWhileHot
        self.batteryTempC = batteryTempC
        self.ssdTempC = ssdTempC
        self.dailyMaxSoc = dailyMaxSoc
    }
}

public struct LongevityAssessment: Equatable, Sendable {
    public var score: Int                 // 0–100
    public var factors: [LongevityFactor]
    public var actions: [LongevityAction]  // sorted by severity descending

    public init(score: Int, factors: [LongevityFactor], actions: [LongevityAction]) {
        self.score = score
        self.factors = factors
        self.actions = actions
    }
}

/// Fuses the longevity signals into a single score, per-factor statuses, and a prioritized
/// list of plain-language recommended actions. Heuristic and unit-tested for monotonicity and
/// action generation — its job is to prioritize what the user should do, not to be a lab gauge.
public enum LongevityAdvisor {
    public static func assess(_ s: LongevitySignals) -> LongevityAssessment {
        var factors: [LongevityFactor] = []
        var actions: [LongevityAction] = []

        // Battery
        let bScore = s.batteryLongevity?.score ?? 100
        let bAlerts = s.batteryLongevity?.alerts ?? []
        let batteryStatus: LongevityFactorStatus
        if bAlerts.contains(.fastFade) || bAlerts.contains(.healthBelow60) || bScore < 65 {
            batteryStatus = .poor
        } else if bScore < 85 || bAlerts.contains(.healthBelow80) || bAlerts.contains(.highCycleRate) {
            batteryStatus = .watch
        } else {
            batteryStatus = .good
        }
        let batterySummary = s.batteryLongevity.map { "\($0.healthPercent)% health · \($0.cycleCount) cycles" } ?? "Collecting daily readings…"
        factors.append(LongevityFactor(id: "battery", title: "Battery", status: batteryStatus, summary: batterySummary))
        if bAlerts.contains(.fastFade) {
            actions.append(LongevityAction(id: "battery-fade", severity: .urgent, title: "Battery is fading fast", detail: "Capacity is dropping quickly — consider a battery service check."))
        } else if bAlerts.contains(.healthBelow80) {
            actions.append(LongevityAction(id: "battery-low", severity: .suggest, title: "Battery is below 80% health", detail: "Apple's service threshold; keep heat and high-charge dwell down to slow further loss."))
        }

        // Heat
        let warm40 = s.batteryExposure.today.secondsAbove40 / 60
        let hot45 = s.batteryExposure.today.secondsAbove45 / 60
        let cpu85 = s.cpuExposure.today.secondsAbove85 / 60
        let cpu95 = s.cpuExposure.today.secondsAbove95 / 60
        let heatStatus: LongevityFactorStatus
        if s.isChargingWhileHot || hot45 > 0 || cpu95 > 0 {
            heatStatus = .poor
        } else if warm40 >= 30 || cpu85 >= 30 {
            heatStatus = .watch
        } else {
            heatStatus = .good
        }
        let heatScore = clamp(100 - (warm40 * 0.5 + hot45 * 1.5 + cpu85 * 0.3 + cpu95 * 1.0 + (s.isChargingWhileHot ? 25 : 0)))
        factors.append(LongevityFactor(id: "heat", title: "Heat", status: heatStatus, summary: heatSummary(warm40: warm40, hot45: hot45, cpu85: cpu85, charging: s.isChargingWhileHot)))
        if s.isChargingWhileHot {
            actions.append(LongevityAction(id: "charge-hot", severity: .urgent, title: "Unplug to let the battery cool", detail: "Charging while hot accelerates battery aging the most."))
        } else if hot45 > 0 {
            actions.append(LongevityAction(id: "heat-45", severity: .suggest, title: "Reduce sustained heat", detail: "The battery spent time above 45° today; ease heavy load or improve airflow."))
        } else if warm40 >= 60 {
            actions.append(LongevityAction(id: "heat-40", severity: .suggest, title: "Watch sustained warmth", detail: "Over an hour above 40° today; cooler running extends battery life."))
        }

        // Charging habits
        let soc80 = s.chargeExposure.today.secondsAbove80OnAC / 60
        let soc95 = s.chargeExposure.today.secondsAbove95OnAC / 60
        let chargingStatus: LongevityFactorStatus
        if soc95 >= 120 {
            chargingStatus = .poor
        } else if soc95 >= 30 || soc80 >= 240 {
            chargingStatus = .watch
        } else {
            chargingStatus = .good
        }
        let chargingScore = clamp(100 - (soc80 * 0.05 + soc95 * 0.2))
        factors.append(LongevityFactor(id: "charging", title: "Charging habits", status: chargingStatus, summary: chargingSummary(soc80: soc80, soc95: soc95)))
        if soc95 >= 30 {
            actions.append(LongevityAction(id: "high-soc", severity: .suggest, title: "Unplug around 80% when you can", detail: "Holding a high charge on AC for long stretches ages the cells faster."))
        }

        // High-SoC exposure → nudge the user toward macOS's native Charge Limit. Pure insight:
        // measure how high the pack actually sits (BMS DailyMaxSoc) and point at Settings; no
        // SMC writes, no daemon. >=90 means routinely near full; <=82 means a limit is likely
        // already active (no nudge); nil means unknown (no nudge). .suggest so it never outranks
        // genuine urgent actions (battery-fade, charge-hot).
        if let maxSoc = s.dailyMaxSoc, maxSoc >= 90 {
            actions.append(LongevityAction(
                id: "high-soc-limit",
                severity: .suggest,
                title: NSLocalizedString("Enable charge limit", comment: ""),
                detail: String(format: NSLocalizedString("Battery reaches %d%% daily — capping at 80%% in Settings → Battery cuts high-charge aging.", comment: ""), maxSoc)
            ))
        }

        // Storage
        let free = s.diskFreePercent
        let storageStatus: LongevityFactorStatus = free < 10 ? .poor : (free < 15 ? .watch : .good)
        let storageScore = clamp(free * 5)
        factors.append(LongevityFactor(id: "storage", title: "Storage", status: storageStatus, summary: String(format: "%.0f%% free", free)))
        if free < 10 {
            actions.append(LongevityAction(id: "free-storage", severity: .urgent, title: "Free up disk space", detail: "Very low free space forces heavy swap to the SSD, slowing the Mac and wearing the drive."))
        } else if free < 15 {
            actions.append(LongevityAction(id: "free-storage", severity: .suggest, title: "Free up some disk space", detail: "Keeping ~15%+ free avoids swap thrash and keeps the Mac responsive."))
        }

        // Memory
        let pressure = s.memoryPressure.lowercased()
        let memoryStatus: LongevityFactorStatus
        let memoryScore: Double
        switch pressure {
        case "critical": memoryStatus = .poor; memoryScore = 40
        case "warning", "elevated": memoryStatus = .watch; memoryScore = 70
        default: memoryStatus = .good; memoryScore = 100
        }
        factors.append(LongevityFactor(id: "memory", title: "Memory", status: memoryStatus, summary: pressure.capitalized + " pressure"))
        if memoryStatus == .poor {
            actions.append(LongevityAction(id: "memory", severity: .suggest, title: "Close memory-heavy apps", detail: "Sustained critical pressure pushes constant swap to the SSD."))
        }

        let score = Int((0.35 * Double(bScore) + 0.30 * heatScore + 0.15 * chargingScore + 0.12 * storageScore + 0.08 * memoryScore).rounded())
        let sortedActions = actions.sorted { $0.severity.rawValue > $1.severity.rawValue }
        return LongevityAssessment(score: max(0, min(100, score)), factors: factors, actions: sortedActions)
    }

    private static func clamp(_ v: Double) -> Double { max(0, min(100, v)) }

    private static func heatSummary(warm40: Double, hot45: Double, cpu85: Double, charging: Bool) -> String {
        if charging { return "Charging while warm" }
        if hot45 > 0 { return "\(Int(hot45.rounded())) min above 45° today" }
        if warm40 > 0 { return "\(Int(warm40.rounded())) min above 40° today" }
        if cpu85 > 0 { return "CPU warm \(Int(cpu85.rounded())) min today" }
        return "Cool today"
    }

    private static func chargingSummary(soc80: Double, soc95: Double) -> String {
        if soc95 > 0 { return "\(Int(soc95.rounded())) min ≥95% on AC today" }
        if soc80 > 0 { return "\(Int(soc80.rounded())) min ≥80% on AC today" }
        return "No high-charge dwell today"
    }
}
