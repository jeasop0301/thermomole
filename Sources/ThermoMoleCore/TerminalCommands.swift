import Foundation

public enum TerminalExecutionMode: String, Equatable, Sendable {
    case plan
    case execute
}

public enum TerminalOutputFormat: String, Equatable, Sendable {
    case text
    case json
}

public struct TerminalCommandRequest: Equatable, Sendable {
    public var command: TerminalCommand
    public var outputFormat: TerminalOutputFormat

    public init(command: TerminalCommand, outputFormat: TerminalOutputFormat = .text) {
        self.command = command
        self.outputFormat = outputFormat
    }
}

public enum TerminalCommand: Equatable, Sendable {
    case status
    case clean(mode: TerminalExecutionMode)
    case optimize(mode: TerminalExecutionMode)
    case installer(mode: TerminalExecutionMode)
    case uninstall(query: String, mode: TerminalExecutionMode)
    case analyze
    case software
    case memory
    case memoryPurge(mode: TerminalExecutionMode)
    case history
    case help
}

public enum TerminalCommandError: Error, Equatable, Sendable {
    case unknownCommand(String)
    case unknownOption(String)
    case missingArgument(String)
}

public enum TerminalCommandParser {
    public static func parse(_ arguments: [String]) throws -> TerminalCommand {
        try parseRequest(arguments).command
    }

    public static func parseRequest(_ arguments: [String]) throws -> TerminalCommandRequest {
        guard let command = arguments.first else {
            return TerminalCommandRequest(command: .status)
        }
        let parsed = try outputFormatAndCommandOptions(from: Array(arguments.dropFirst()))

        switch command {
        case "status":
            try rejectOptions(parsed.commandOptions)
            return TerminalCommandRequest(command: .status, outputFormat: parsed.outputFormat)
        case "clean":
            return TerminalCommandRequest(command: .clean(mode: try mode(from: parsed.commandOptions)), outputFormat: parsed.outputFormat)
        case "optimize":
            return TerminalCommandRequest(command: .optimize(mode: try mode(from: parsed.commandOptions)), outputFormat: parsed.outputFormat)
        case "installer":
            return TerminalCommandRequest(command: .installer(mode: try mode(from: parsed.commandOptions)), outputFormat: parsed.outputFormat)
        case "uninstall":
            let command = try uninstallCommand(from: parsed.commandOptions)
            return TerminalCommandRequest(command: command, outputFormat: parsed.outputFormat)
        case "analyze":
            try rejectOptions(parsed.commandOptions)
            return TerminalCommandRequest(command: .analyze, outputFormat: parsed.outputFormat)
        case "software":
            try rejectOptions(parsed.commandOptions)
            return TerminalCommandRequest(command: .software, outputFormat: parsed.outputFormat)
        case "memory":
            return TerminalCommandRequest(command: try memoryCommand(from: parsed.commandOptions), outputFormat: parsed.outputFormat)
        case "history":
            try rejectOptions(parsed.commandOptions)
            return TerminalCommandRequest(command: .history, outputFormat: parsed.outputFormat)
        case "help", "--help", "-h":
            try rejectOptions(parsed.commandOptions)
            return TerminalCommandRequest(command: .help, outputFormat: parsed.outputFormat)
        default:
            throw TerminalCommandError.unknownCommand(command)
        }
    }

    private static func outputFormatAndCommandOptions(from options: [String]) throws -> (outputFormat: TerminalOutputFormat, commandOptions: [String]) {
        var outputFormat = TerminalOutputFormat.text
        var commandOptions = [String]()
        for option in options {
            if option == "--json" {
                outputFormat = .json
            } else {
                commandOptions.append(option)
            }
        }
        return (outputFormat, commandOptions)
    }

    private static func mode(from options: [String]) throws -> TerminalExecutionMode {
        guard let option = options.first else { return .plan }
        guard options.count == 1, option == "--execute" else {
            throw TerminalCommandError.unknownOption(option)
        }
        return .execute
    }

    private static func uninstallCommand(from options: [String]) throws -> TerminalCommand {
        var mode = TerminalExecutionMode.plan
        var queryParts = [String]()

        for option in options {
            if option == "--execute" {
                mode = .execute
            } else if option.hasPrefix("-") {
                throw TerminalCommandError.unknownOption(option)
            } else {
                queryParts.append(option)
            }
        }

        let query = queryParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw TerminalCommandError.missingArgument("uninstall <app name>")
        }
        return .uninstall(query: query, mode: mode)
    }

    private static func memoryCommand(from options: [String]) throws -> TerminalCommand {
        guard !options.isEmpty else { return .memory }

        var mode = TerminalExecutionMode.plan
        var hasPurge = false
        for option in options {
            switch option {
            case "--purge":
                hasPurge = true
            case "--execute":
                mode = .execute
            default:
                throw TerminalCommandError.unknownOption(option)
            }
        }

        guard hasPurge else {
            throw TerminalCommandError.unknownOption(options[0])
        }
        return .memoryPurge(mode: mode)
    }

    private static func rejectOptions(_ options: [String]) throws {
        if let option = options.first {
            throw TerminalCommandError.unknownOption(option)
        }
    }
}

public enum TerminalOutputFormatter {
    public static func status(_ snapshot: SystemSnapshot, now: Date = Date()) -> String {
        let freshness = StatusFreshness(sampledAt: snapshot.sampledAt, now: now)
        let batteryLine = "Battery \(formatTemperature(snapshot.thermal.batteryDisplayC)) · \(batterySourceLabel(snapshot.thermal.batteryTemperatureSource))"
        let sensorLine = if snapshot.thermal.hasBatterySensorMismatch {
            "Battery sensors: AppleSmartBattery \(formatTemperature(snapshot.thermal.batteryIORegC)) · SMC TB max \(formatTemperature(snapshot.thermal.batteryCellMaxC))"
        } else {
            "Battery sensor: \(batterySourceLabel(snapshot.thermal.batteryTemperatureSource))"
        }

        return [
            "Status",
            "\(freshness.title) · \(freshness.detail)",
            "CPU \(formatTemperature(snapshot.thermal.cpuDisplayC)) · \(cpuSourceLabel(snapshot.thermal.cpuTemperatureSource))",
            batteryLine,
            "RAM \(snapshot.memory.usedPercent)% · \(snapshot.memory.pressure.rawValue.capitalized)",
            "Health \(snapshot.health.value) · \(snapshot.health.band.rawValue.capitalized)",
            sensorLine
        ].joined(separator: "\n")
    }

    public static func jsonStatus(_ snapshot: SystemSnapshot, now: Date = Date()) throws -> String {
        let freshness = StatusFreshness(sampledAt: snapshot.sampledAt, now: now)
        return try encodeJSON(TerminalStatusJSON(
            command: "status",
            cpuTemperatureC: snapshot.thermal.cpuDisplayC,
            cpuTemperatureSource: snapshot.thermal.cpuTemperatureSource.rawValue,
            cpuDieHotspotTemperatureC: snapshot.thermal.cpuDieHotspotC,
            cpuAverageTemperatureC: snapshot.thermal.cpuAverageC,
            batteryTemperatureC: snapshot.thermal.batteryDisplayC,
            batteryTemperatureSource: snapshot.thermal.batteryTemperatureSource.rawValue,
            batteryIORegTemperatureC: snapshot.thermal.batteryIORegC,
            batteryCellMaxTemperatureC: snapshot.thermal.batteryCellMaxC,
            batterySensorMismatch: snapshot.thermal.hasBatterySensorMismatch,
            memoryUsedPercent: snapshot.memory.usedPercent,
            memoryPressure: snapshot.memory.pressure.rawValue,
            healthScore: snapshot.health.value,
            healthBand: snapshot.health.band.rawValue,
            freshnessLevel: freshness.level.rawValue,
            freshnessDetail: freshness.detail,
            sampledAt: snapshot.sampledAt
        ))
    }

    public static func smartCleanPlan(_ plan: SmartCleanupReviewPlan) -> String {
        if !plan.hasSelection {
            return "Smart Clean\nNothing safe to clean."
        }

        let skipped = plan.skippedCount > 0 ? " · \(plan.skippedCount) skipped" : ""
        return "Smart Clean\n\(plan.selectedItemCount) items · \(formatTerminalBytes(plan.selectedBytes))\(skipped)\nRun `thermomole clean --execute` to move them to Trash."
    }

    public static func jsonSmartCleanPlan(_ plan: SmartCleanupReviewPlan) throws -> String {
        try encodeJSON(TerminalCleanupPlanJSON(
            command: "clean",
            title: "Smart Clean",
            selectedItemCount: plan.selectedItemCount,
            selectedBytes: plan.selectedBytes,
            skippedCount: plan.skippedCount,
            hasSelection: plan.hasSelection,
            executeCommand: "thermomole clean --execute"
        ))
    }

    public static func jsonCleanupExecution(command: String, title: String, result: CleanupExecutionResult) throws -> String {
        try encodeJSON(TerminalCleanupExecutionJSON(
            command: command,
            title: title,
            succeededCount: result.succeededCount,
            skippedCount: result.skippedCount,
            failedCount: result.failedCount,
            reclaimedBytes: result.reclaimedBytes
        ))
    }

    public static func optimizeBatch(_ batch: OptimizeBatchPlan) -> String {
        let staged = batch.skippedTasks.isEmpty ? "" : " · \(batch.skippedTasks.count) staged"
        let taskLines = batch.plans.map { "- \($0.task.title)" }.joined(separator: "\n")
        return "Default Optimize\n\(batch.plans.count) runnable · \(batch.commandCount) commands\(staged)\n\(taskLines)"
    }

    public static func jsonOptimizeBatch(_ batch: OptimizeBatchPlan) throws -> String {
        try encodeJSON(TerminalOptimizeBatchJSON(
            command: "optimize",
            title: "Default Optimize",
            runnableCount: batch.plans.count,
            commandCount: batch.commandCount,
            stagedCount: batch.skippedTasks.count,
            tasks: batch.plans.map { $0.task.title }
        ))
    }

    public static func jsonOptimizeExecution(_ results: [OptimizeExecutionResult], skippedCount: Int) throws -> String {
        let failed = results.filter { $0.status == .failed }.count
        return try encodeJSON(TerminalOptimizeExecutionJSON(
            command: "optimize",
            title: "Default Optimize",
            runCount: results.count,
            failedCount: failed,
            stagedCount: skippedCount
        ))
    }

    public static func installerPlan(_ plan: SmartCleanupReviewPlan) -> String {
        if !plan.hasSelection {
            return "Installer Cleanup\nNo installer files found."
        }

        let skipped = plan.skippedCount > 0 ? " · \(plan.skippedCount) skipped" : ""
        return "Installer Cleanup\n\(plan.selectedItemCount) files · \(formatTerminalBytes(plan.selectedBytes))\(skipped)\nRun `thermomole installer --execute` to move them to Trash."
    }

    public static func jsonInstallerPlan(_ plan: SmartCleanupReviewPlan) throws -> String {
        try encodeJSON(TerminalCleanupPlanJSON(
            command: "installer",
            title: "Installer Cleanup",
            selectedItemCount: plan.selectedItemCount,
            selectedBytes: plan.selectedBytes,
            skippedCount: plan.skippedCount,
            hasSelection: plan.hasSelection,
            executeCommand: "thermomole installer --execute"
        ))
    }

    public static func appUninstallPlan(_ plan: AppUninstallPlan) -> String {
        switch plan.status {
        case .ready:
            guard let app = plan.selectedApp else {
                return "Uninstall\nNo app selected."
            }
            return """
            Uninstall
            \(app.name) · \(app.version) · \(app.bundleIdentifier)
            \(app.bundlePath)
            Run `thermomole uninstall "\(escapedCommandArgument(app.name))" --execute` to move it to Trash.
            """
        case .ambiguous:
            let lines = plan.matches.map {
                "- \($0.name) · \($0.bundleIdentifier) · \($0.bundlePath)"
            }.joined(separator: "\n")
            return "Uninstall\n\(plan.message)\n\(lines)\nRefine the app name before executing."
        case .notFound:
            return "Uninstall\n\(plan.message)"
        case .missingQuery:
            return "Uninstall\nProvide an app name: `thermomole uninstall \"App Name\"`."
        }
    }

    public static func jsonAppUninstallPlan(_ plan: AppUninstallPlan) throws -> String {
        try encodeJSON(TerminalAppUninstallPlanJSON(
            command: "uninstall",
            query: plan.query,
            status: plan.status.rawValue,
            canExecute: plan.canExecute,
            selectedApp: plan.selectedApp.map(TerminalInstalledAppJSON.init(app:)),
            matches: plan.matches.map(TerminalInstalledAppJSON.init(app:)),
            message: plan.message,
            executeCommand: plan.selectedApp.map {
                "thermomole uninstall \"\(escapedCommandArgument($0.name))\" --execute"
            }
        ))
    }

    public static func appUninstallResult(_ result: AppUninstallResult) -> String {
        let destination = result.destinationURL.map { "\n\($0.path)" } ?? ""
        return "Uninstall \(result.app.name)\n\(result.status.rawValue.capitalized) · \(result.message)\(destination)"
    }

    public static func jsonAppUninstallResult(_ result: AppUninstallResult) throws -> String {
        try encodeJSON(TerminalAppUninstallResultJSON(
            command: "uninstall",
            appName: result.app.name,
            bundleIdentifier: result.app.bundleIdentifier,
            bundlePath: result.app.bundlePath,
            status: result.status.rawValue,
            destinationPath: result.destinationURL?.path,
            message: result.message,
            executedAt: result.executedAt
        ))
    }

    public static func memoryResearch() -> String {
        """
        Memory Clean
        Research-only. Use memory pressure, swap, compressed memory, and top processes before any action.
        `purge` is not a default cleanup path because it targets disk cache, not anonymous app memory.
        """
    }

    public static func memoryDoctor(_ report: MemoryDoctorReport) -> String {
        let top = report.topMemoryProcess.map {
            "\($0.name) · \(formatTerminalBytes($0.memoryBytes))"
        } ?? "None"
        let purge = report.allowsPurge ? "Advanced purge: available with confirmation" : "Advanced purge: disabled"
        return "Memory Doctor\n\(report.level.title) · \(report.memory.usedPercent)% used · \(report.memory.pressure.rawValue.capitalized)\n\(report.summary)\nTop process: \(top)\n\(purge)"
    }

    public static func jsonMemoryDoctor(_ report: MemoryDoctorReport) throws -> String {
        try encodeJSON(TerminalMemoryDoctorJSON(
            command: "memory",
            level: report.level.rawValue,
            usedPercent: report.memory.usedPercent,
            pressure: report.memory.pressure.rawValue,
            summary: report.summary,
            topProcessName: report.topMemoryProcess?.name,
            topProcessMemoryBytes: report.topMemoryProcess?.memoryBytes,
            allowsPurge: report.allowsPurge
        ))
    }

    public static func memoryPurgePlan(_ plan: MemoryPurgePlan) -> String {
        if plan.canExecute {
            return """
            Advanced Memory Purge
            \(plan.summary)
            \(plan.confirmationMessage)
            Run `thermomole memory --purge --execute` to execute.
            """
        }

        return "Advanced Memory Purge\n\(plan.summary)"
    }

    public static func jsonMemoryPurgePlan(_ plan: MemoryPurgePlan) throws -> String {
        try encodeJSON(TerminalMemoryPurgePlanJSON(
            command: "memoryPurge",
            status: plan.status.rawValue,
            canExecute: plan.canExecute,
            commandPath: plan.commands.first?.executablePath,
            summary: plan.summary,
            confirmationMessage: plan.confirmationMessage,
            executeCommand: plan.canExecute ? "thermomole memory --purge --execute" : nil
        ))
    }

    public static func memoryPurgeResult(_ result: MemoryPurgeResult) -> String {
        "Advanced Memory Purge\n\(result.status.rawValue.capitalized) · \(result.message)"
    }

    public static func jsonMemoryPurgeResult(_ result: MemoryPurgeResult) throws -> String {
        try encodeJSON(TerminalMemoryPurgeResultJSON(
            command: "memoryPurge",
            status: result.status.rawValue,
            commandPath: result.command?.executablePath,
            message: result.message,
            executedAt: result.executedAt
        ))
    }

    public static func history(_ entries: [OperationHistoryEntry]) -> String {
        guard !entries.isEmpty else {
            return "History\nNo operations logged."
        }

        let lines = entries.map { entry in
            "- \(entry.title) · \(entry.status.title) · \(entry.itemCount) item\(entry.itemCount == 1 ? "" : "s") · \(formatTerminalBytes(entry.bytes)) · \(entry.message)"
        }
        return "History\n\(lines.joined(separator: "\n"))"
    }

    public static func jsonHistory(_ entries: [OperationHistoryEntry]) throws -> String {
        try encodeJSON(TerminalHistoryJSON(command: "history", entries: entries))
    }

    public static func diskAnalysis(_ summary: DiskAnalysisSummary) -> String {
        guard summary.entryCount > 0 else {
            return "Analyze\nNo entries found for \(summary.scopeURL.path)."
        }

        let largest = summary.largestEntry.map {
            "\($0.url.lastPathComponent) · \(formatTerminalBytes($0.sizeBytes))"
        } ?? "None"
        return "Analyze\n\(summary.entryCount) entries · \(formatTerminalBytes(summary.totalBytes)) total\nLargest: \(largest)"
    }

    public static func jsonDiskAnalysis(_ summary: DiskAnalysisSummary) throws -> String {
        try encodeJSON(TerminalDiskAnalysisJSON(
            command: "analyze",
            scopePath: summary.scopeURL.path,
            entryCount: summary.entryCount,
            totalBytes: summary.totalBytes,
            largestName: summary.largestEntry?.url.lastPathComponent,
            largestBytes: summary.largestEntry?.sizeBytes
        ))
    }

    public static func software(_ summary: SoftwareSummary) -> String {
        "Software\n\(summary.appCount) apps · \(summary.startupItemCount) startup items · \(summary.enabledStartupItemCount) enabled startup · \(summary.uninstallCandidateCount) uninstall candidate"
    }

    public static func jsonSoftware(_ summary: SoftwareSummary) throws -> String {
        try encodeJSON(TerminalSoftwareJSON(
            command: "software",
            appCount: summary.appCount,
            startupItemCount: summary.startupItemCount,
            enabledStartupItemCount: summary.enabledStartupItemCount,
            uninstallCandidateCount: summary.uninstallCandidateCount
        ))
    }

    public static func help() -> String {
        """
        ThermoMole CLI
        Add --json to any command for machine-readable output.

        thermomole status
        thermomole clean [--execute]
        thermomole installer [--execute]
        thermomole uninstall <app name> [--execute]
        thermomole optimize [--execute]
        thermomole analyze
        thermomole software
        thermomole memory
        thermomole memory --purge [--execute]
        thermomole history
        """
    }

    public static func formatTerminalBytes(_ value: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var amount = Double(value)
        var index = 0
        while amount >= 1024, index < units.count - 1 {
            amount /= 1024
            index += 1
        }
        return index == 0 ? "\(Int(amount)) \(units[index])" : String(format: "%.1f %@", amount, units[index])
    }

    private static func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func escapedCommandArgument(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func formatTemperature(_ value: Double?) -> String {
        guard let value else { return "--°" }
        return String(format: "%.1f°", value)
    }

    private static func batterySourceLabel(_ source: BatteryTemperatureSource) -> String {
        switch source {
        case .unavailable: "Unavailable"
        case .smcCellMax: "SMC TB max"
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

private struct TerminalStatusJSON: Encodable {
    var command: String
    var cpuTemperatureC: Double?
    var cpuTemperatureSource: String
    var cpuDieHotspotTemperatureC: Double?
    var cpuAverageTemperatureC: Double?
    var batteryTemperatureC: Double?
    var batteryTemperatureSource: String
    var batteryIORegTemperatureC: Double?
    var batteryCellMaxTemperatureC: Double?
    var batterySensorMismatch: Bool
    var memoryUsedPercent: Int
    var memoryPressure: String
    var healthScore: Int
    var healthBand: String
    var freshnessLevel: String
    var freshnessDetail: String
    var sampledAt: Date
}

private struct TerminalCleanupPlanJSON: Encodable {
    var command: String
    var title: String
    var selectedItemCount: Int
    var selectedBytes: UInt64
    var skippedCount: Int
    var hasSelection: Bool
    var executeCommand: String
}

private struct TerminalCleanupExecutionJSON: Encodable {
    var command: String
    var title: String
    var succeededCount: Int
    var skippedCount: Int
    var failedCount: Int
    var reclaimedBytes: UInt64
}

private struct TerminalInstalledAppJSON: Encodable {
    var name: String
    var bundleIdentifier: String
    var bundlePath: String
    var version: String
    var build: String

    init(app: InstalledApp) {
        name = app.name
        bundleIdentifier = app.bundleIdentifier
        bundlePath = app.bundlePath
        version = app.version
        build = app.build
    }
}

private struct TerminalAppUninstallPlanJSON: Encodable {
    var command: String
    var query: String
    var status: String
    var canExecute: Bool
    var selectedApp: TerminalInstalledAppJSON?
    var matches: [TerminalInstalledAppJSON]
    var message: String
    var executeCommand: String?
}

private struct TerminalAppUninstallResultJSON: Encodable {
    var command: String
    var appName: String
    var bundleIdentifier: String
    var bundlePath: String
    var status: String
    var destinationPath: String?
    var message: String
    var executedAt: Date
}

private struct TerminalOptimizeBatchJSON: Encodable {
    var command: String
    var title: String
    var runnableCount: Int
    var commandCount: Int
    var stagedCount: Int
    var tasks: [String]
}

private struct TerminalOptimizeExecutionJSON: Encodable {
    var command: String
    var title: String
    var runCount: Int
    var failedCount: Int
    var stagedCount: Int
}

private struct TerminalMemoryDoctorJSON: Encodable {
    var command: String
    var level: String
    var usedPercent: Int
    var pressure: String
    var summary: String
    var topProcessName: String?
    var topProcessMemoryBytes: UInt64?
    var allowsPurge: Bool
}

private struct TerminalMemoryPurgePlanJSON: Encodable {
    var command: String
    var status: String
    var canExecute: Bool
    var commandPath: String?
    var summary: String
    var confirmationMessage: String
    var executeCommand: String?
}

private struct TerminalMemoryPurgeResultJSON: Encodable {
    var command: String
    var status: String
    var commandPath: String?
    var message: String
    var executedAt: Date
}

private struct TerminalHistoryJSON: Encodable {
    var command: String
    var entries: [OperationHistoryEntry]
}

private struct TerminalDiskAnalysisJSON: Encodable {
    var command: String
    var scopePath: String
    var entryCount: Int
    var totalBytes: UInt64
    var largestName: String?
    var largestBytes: UInt64?
}

private struct TerminalSoftwareJSON: Encodable {
    var command: String
    var appCount: Int
    var startupItemCount: Int
    var enabledStartupItemCount: Int
    var uninstallCandidateCount: Int
}

public struct DiskAnalysisSummary: Equatable, Sendable {
    public var scopeURL: URL
    public var entries: [DiskEntry]

    public init(scopeURL: URL, entries: [DiskEntry]) {
        self.scopeURL = scopeURL
        self.entries = entries
    }

    public var entryCount: Int {
        entries.count
    }

    public var totalBytes: UInt64 {
        entries.reduce(0) { $0 + $1.sizeBytes }
    }

    public var largestEntry: DiskEntry? {
        entries.first
    }
}

public struct SoftwareSummary: Equatable, Sendable {
    public var apps: [InstalledApp]
    public var startupItems: [StartupItem]

    public init(apps: [InstalledApp], startupItems: [StartupItem]) {
        self.apps = apps
        self.startupItems = startupItems
    }

    public var appCount: Int {
        apps.count
    }

    public var startupItemCount: Int {
        startupItems.count
    }

    public var enabledStartupItemCount: Int {
        startupItems.filter(\.isEnabled).count
    }

    public var uninstallCandidateCount: Int {
        apps.filter {
            $0.version == "unknown" || $0.build == "unknown"
        }.count
    }
}
