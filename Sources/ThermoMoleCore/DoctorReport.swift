import Foundation

public enum DoctorSeverity: String, Codable, Sendable {
    case ok
    case warning
}

public enum DoctorAction: String, Codable, Sendable {
    case none
    case openFullDiskAccess
    case reduceMemoryLoad
    case reviewStorage
    case reviewBatteryHealth
    case repairOperationLog
    case reviewRecentFailures
    case refreshStatusSnapshot
}

public struct DoctorInputs: Codable, Equatable, Sendable {
    public var hasFullDiskAccess: Bool
    public var memoryPressure: MemoryPressure
    public var diskUsedPercent: Double
    public var batteryHealthPercent: Int
    public var operationLogWritable: Bool
    public var recentOperationFailures: Int
    public var statusFreshnessLevel: StatusFreshnessLevel

    public init(
        hasFullDiskAccess: Bool,
        memoryPressure: MemoryPressure,
        diskUsedPercent: Double,
        batteryHealthPercent: Int,
        operationLogWritable: Bool,
        recentOperationFailures: Int,
        statusFreshnessLevel: StatusFreshnessLevel = .live
    ) {
        self.hasFullDiskAccess = hasFullDiskAccess
        self.memoryPressure = memoryPressure
        self.diskUsedPercent = diskUsedPercent
        self.batteryHealthPercent = batteryHealthPercent
        self.operationLogWritable = operationLogWritable
        self.recentOperationFailures = recentOperationFailures
        self.statusFreshnessLevel = statusFreshnessLevel
    }

    public static let placeholder = DoctorInputs(
        hasFullDiskAccess: false,
        memoryPressure: .normal,
        diskUsedPercent: 0,
        batteryHealthPercent: 100,
        operationLogWritable: true,
        recentOperationFailures: 0,
        statusFreshnessLevel: .live
    )

    public static func make(
        snapshot: SystemSnapshot,
        hasFullDiskAccess: Bool,
        operationLogWritable: Bool,
        recentOperationFailures: Int,
        now: Date = Date()
    ) -> DoctorInputs {
        DoctorInputs(
            hasFullDiskAccess: hasFullDiskAccess,
            memoryPressure: snapshot.memory.pressure,
            diskUsedPercent: snapshot.disk.usedPercent,
            batteryHealthPercent: snapshot.battery.healthPercent,
            operationLogWritable: operationLogWritable,
            recentOperationFailures: recentOperationFailures,
            statusFreshnessLevel: StatusFreshness(sampledAt: snapshot.sampledAt, now: now).level
        )
    }
}

public struct DoctorCheck: Codable, Identifiable, Equatable, Sendable {
    public var id: DoctorAction { action }
    public var title: String
    public var message: String
    public var severity: DoctorSeverity
    public var action: DoctorAction

    public init(title: String, message: String, severity: DoctorSeverity, action: DoctorAction) {
        self.title = title
        self.message = message
        self.severity = severity
        self.action = action
    }
}

public struct DoctorReport: Codable, Equatable, Sendable {
    public var summary: String
    public var checks: [DoctorCheck]

    public var isAllClear: Bool {
        checks.allSatisfy { $0.severity == .ok }
    }

    public static func make(inputs: DoctorInputs) -> DoctorReport {
        var checks = [DoctorCheck]()

        if !inputs.hasFullDiskAccess {
            checks.append(DoctorCheck(
                title: "Full Disk Access",
                message: "Deeper cache and app-support scans may be incomplete.",
                severity: .warning,
                action: .openFullDiskAccess
            ))
        }

        if inputs.memoryPressure != .normal {
            checks.append(DoctorCheck(
                title: "Memory pressure",
                message: inputs.memoryPressure == .critical ? "Memory pressure is critical." : "Memory pressure is elevated.",
                severity: .warning,
                action: .reduceMemoryLoad
            ))
        }

        if inputs.diskUsedPercent >= 90 {
            checks.append(DoctorCheck(
                title: "Storage",
                message: "Startup disk is above 90% used.",
                severity: .warning,
                action: .reviewStorage
            ))
        }

        if inputs.batteryHealthPercent > 0, inputs.batteryHealthPercent < 80 {
            checks.append(DoctorCheck(
                title: "Battery health",
                message: "Maximum capacity is below 80%.",
                severity: .warning,
                action: .reviewBatteryHealth
            ))
        }

        if !inputs.operationLogWritable {
            checks.append(DoctorCheck(
                title: "Operation log",
                message: "ThermoMole cannot write its local operation log.",
                severity: .warning,
                action: .repairOperationLog
            ))
        }

        if inputs.recentOperationFailures > 0 {
            checks.append(DoctorCheck(
                title: "Recent operations",
                message: "\(inputs.recentOperationFailures) recent operation\(inputs.recentOperationFailures == 1 ? "" : "s") failed.",
                severity: .warning,
                action: .reviewRecentFailures
            ))
        }

        if inputs.statusFreshnessLevel == .stale {
            checks.append(DoctorCheck(
                title: "Status freshness",
                message: "The last status snapshot is stale. Refresh status before trusting live readings.",
                severity: .warning,
                action: .refreshStatusSnapshot
            ))
        }

        if checks.isEmpty {
            checks.append(DoctorCheck(
                title: "All clear",
                message: "No local issues detected.",
                severity: .ok,
                action: .none
            ))
        }

        let warningCount = checks.filter { $0.severity == .warning }.count
        return DoctorReport(
            summary: warningCount == 0 ? "All clear" : "\(warningCount) item\(warningCount == 1 ? " needs" : "s need") attention",
            checks: checks
        )
    }
}

public struct DoctorGuidanceSummary: Equatable, Sendable {
    public var fullDiskAccessStatus: String
    public var fullDiskAccessDetail: String
    public var diagnosticScopeTitle: String
    public var diagnosticIncludedLines: [String]
    public var diagnosticExcludedLines: [String]
    public var sharingNote: String

    public init(report: DoctorReport) {
        let hasMissingFullDiskAccess = report.checks.contains { $0.action == .openFullDiskAccess }
        fullDiskAccessStatus = hasMissingFullDiskAccess ? "Missing or unknown" : "Granted"
        if hasMissingFullDiskAccess {
            fullDiskAccessDetail = "Full Disk Access is optional. It expands deeper cache and app-support scan coverage while protected roots remain guarded."
        } else {
            fullDiskAccessDetail = "Deeper scans can cover more local cache and app-support paths."
        }

        diagnosticScopeTitle = "Local JSON"
        diagnosticIncludedLines = [
            "Last status snapshot",
            "Doctor checks",
            "Recent operation history"
        ]
        diagnosticExcludedLines = [
            "File contents",
            "Personal documents",
            "Browser history"
        ]
        sharingNote = "Review before sharing; diagnostic reports can include local paths and operation summaries."
    }
}
