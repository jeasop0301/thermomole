import Foundation

public enum OptimizeRiskLevel: String, Codable, Sendable {
    case low
    case medium
}

public struct OptimizeCommand: Equatable, Sendable {
    public var executablePath: String
    public var arguments: [String]

    public init(executablePath: String, arguments: [String]) {
        self.executablePath = executablePath
        self.arguments = arguments
    }
}

public struct CommandResult: Equatable, Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public struct OptimizePlan: Equatable, Sendable {
    public var task: OptimizeTask
    public var commands: [OptimizeCommand]
    public var riskLevel: OptimizeRiskLevel
    public var summary: String
    public var effects: [String]
    public var confirmationMessage: String
    public var requiresConfirmation: Bool

    public init(
        task: OptimizeTask,
        commands: [OptimizeCommand]? = nil,
        riskLevel: OptimizeRiskLevel? = nil,
        summary: String? = nil,
        effects: [String]? = nil,
        confirmationMessage: String? = nil,
        requiresConfirmation: Bool = true
    ) {
        self.task = task
        self.commands = commands ?? task.defaultCommands
        self.riskLevel = riskLevel ?? task.defaultRiskLevel
        self.summary = summary ?? task.reviewSummary
        self.effects = effects ?? task.defaultEffects
        self.confirmationMessage = confirmationMessage ?? task.defaultConfirmationMessage
        self.requiresConfirmation = requiresConfirmation
    }
}

public struct OptimizeSafetyContext: Equatable, Sendable {
    public var isOnBatteryPower: Bool
    public var hasActiveVPN: Bool
    public var hasExternalDisplay: Bool
    public var hasExternalAudio: Bool
    public var hasBluetoothHID: Bool
    public var hasBluetoothAudio: Bool

    public init(
        isOnBatteryPower: Bool = false,
        hasActiveVPN: Bool = false,
        hasExternalDisplay: Bool = false,
        hasExternalAudio: Bool = false,
        hasBluetoothHID: Bool = false,
        hasBluetoothAudio: Bool = false
    ) {
        self.isOnBatteryPower = isOnBatteryPower
        self.hasActiveVPN = hasActiveVPN
        self.hasExternalDisplay = hasExternalDisplay
        self.hasExternalAudio = hasExternalAudio
        self.hasBluetoothHID = hasBluetoothHID
        self.hasBluetoothAudio = hasBluetoothAudio
    }
}

public enum OptimizeSafetyContextParser {
    public static func hasActiveVPN(scutilOutput: String) -> Bool {
        scutilOutput
            .split(separator: "\n")
            .contains { $0.contains("(Connected)") }
    }

    public static func hasExternalAudio(systemProfilerAudioOutput: String) -> Bool {
        defaultAudioOutputBlocks(from: systemProfilerAudioOutput).contains { block in
            let lowered = block.lowercased()
            return !builtInAudioMarkers.contains { lowered.contains($0) }
        }
    }

    public static func hasBluetoothAudio(systemProfilerBluetoothOutput: String) -> Bool {
        connectedBluetoothBlocks(from: systemProfilerBluetoothOutput).contains { block in
            let lowered = block.lowercased()
            return bluetoothAudioMarkers.contains { lowered.contains($0) }
        }
    }

    public static func hasBluetoothHID(systemProfilerBluetoothOutput: String) -> Bool {
        connectedBluetoothBlocks(from: systemProfilerBluetoothOutput).contains { block in
            let lowered = block.lowercased()
            return bluetoothHIDMarkers.contains { lowered.contains($0) }
        }
    }

    private static let builtInAudioMarkers = [
        "macbook pro speakers",
        "macbook air speakers",
        "built-in output",
        "built in output",
        "internal speakers"
    ]

    private static let bluetoothAudioMarkers = [
        "airpods",
        "beats",
        "headphones",
        "headset",
        "speaker",
        "audio"
    ]

    private static let bluetoothHIDMarkers = [
        "keyboard",
        "mouse",
        "trackpad",
        "hid",
        "input"
    ]

    private static func defaultAudioOutputBlocks(from output: String) -> [String] {
        deviceBlocks(from: output).filter { block in
            let lowered = block.lowercased()
            return lowered.contains("default output device: yes") || lowered.contains("default system output device: yes")
        }
    }

    private static func connectedBluetoothBlocks(from output: String) -> [String] {
        deviceBlocks(from: output).filter { block in
            block.lowercased().contains("connected: yes")
        }
    }

    private static func deviceBlocks(from output: String) -> [String] {
        var blocks = [String]()
        var current = [String]()

        for line in output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let startsBlock = trimmed.hasSuffix(":")
            if startsBlock, !current.isEmpty {
                blocks.append(current.joined(separator: "\n"))
                current.removeAll()
            }
            if !trimmed.isEmpty || !current.isEmpty {
                current.append(line)
            }
        }

        if !current.isEmpty {
            blocks.append(current.joined(separator: "\n"))
        }
        return blocks
    }
}

public struct OptimizeSafetySignal: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var detail: String

    public init(id: String, title: String, detail: String) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

public struct OptimizeSafetySummary: Equatable, Sendable {
    public var title: String
    public var detail: String
    public var activeSignals: [OptimizeSafetySignal]
    public var runnableTaskCount: Int
    public var stagedTaskCount: Int
    public var commandCount: Int

    public init(
        context: OptimizeSafetyContext,
        tasks: [OptimizeTask] = OptimizeTask.allCases
    ) {
        let batch = OptimizeBatchPlan.defaultMaintenance(tasks: tasks, safetyContext: context)
        activeSignals = OptimizeSafetySummary.activeSignals(context: context)
        runnableTaskCount = batch.plans.count
        stagedTaskCount = batch.skippedTasks.count
        commandCount = batch.commandCount
        title = activeSignals.isEmpty ? "Ready" : "Guarded"
        detail = "\(runnableTaskCount) runnable · \(commandCount) commands · \(stagedTaskCount) staged"
    }

    private static func activeSignals(context: OptimizeSafetyContext) -> [OptimizeSafetySignal] {
        var signals = [OptimizeSafetySignal]()
        if context.isOnBatteryPower {
            signals.append(OptimizeSafetySignal(
                id: "batteryPower",
                title: "Battery Power",
                detail: "Periodic maintenance staged"
            ))
        }
        if context.hasActiveVPN {
            signals.append(OptimizeSafetySignal(
                id: "activeVPN",
                title: "VPN",
                detail: "Launch Services staged"
            ))
        }
        if context.hasExternalDisplay {
            signals.append(OptimizeSafetySignal(
                id: "externalDisplay",
                title: "External Display",
                detail: "Dock refresh staged"
            ))
        }
        if context.hasExternalAudio {
            signals.append(OptimizeSafetySignal(
                id: "externalAudio",
                title: "External Audio",
                detail: "Dock refresh staged"
            ))
        }
        if context.hasBluetoothHID {
            signals.append(OptimizeSafetySignal(
                id: "bluetoothInput",
                title: "Bluetooth Input",
                detail: "Dock refresh staged"
            ))
        }
        if context.hasBluetoothAudio {
            signals.append(OptimizeSafetySignal(
                id: "bluetoothAudio",
                title: "Bluetooth Audio",
                detail: "Dock refresh staged"
            ))
        }
        return signals
    }
}

public struct OptimizeSafetyDecision: Equatable, Sendable {
    public var task: OptimizeTask
    public var skipReason: String?

    public init(task: OptimizeTask, skipReason: String? = nil) {
        self.task = task
        self.skipReason = skipReason
    }
}

public struct OptimizeSafetyPolicy: Sendable {
    public var context: OptimizeSafetyContext

    public init(context: OptimizeSafetyContext = OptimizeSafetyContext()) {
        self.context = context
    }

    public func decisions(for tasks: [OptimizeTask]) -> [OptimizeTask: OptimizeSafetyDecision] {
        Dictionary(uniqueKeysWithValues: tasks.map { task in
            (task, decision(for: task))
        })
    }

    public func decision(for task: OptimizeTask) -> OptimizeSafetyDecision {
        let reasons = skipReasons(for: task)
        return OptimizeSafetyDecision(task: task, skipReason: reasons.isEmpty ? nil : reasons.joined(separator: " · "))
    }

    private func skipReasons(for task: OptimizeTask) -> [String] {
        switch task {
        case .quickLook:
            []
        case .launchServices:
            context.hasActiveVPN ? ["Active VPN detected"] : []
        case .periodicMaintenance:
            context.isOnBatteryPower ? ["Mac is on battery power"] : []
        case .savedApplicationState:
            ["Staged until Clean can review saved application state files"]
        case .dockRefresh:
            dockRefreshReasons()
        }
    }

    private func dockRefreshReasons() -> [String] {
        var reasons = [String]()
        if context.hasExternalDisplay {
            reasons.append("External display detected")
        }
        if context.hasExternalAudio {
            reasons.append("External audio detected")
        }
        if context.hasBluetoothHID {
            reasons.append("Bluetooth input device detected")
        }
        if context.hasBluetoothAudio {
            reasons.append("Bluetooth audio detected")
        }
        return reasons
    }
}

public struct OptimizeBatchPlan: Equatable, Sendable {
    public var plans: [OptimizePlan]
    public var skippedTasks: [OptimizeTask]
    public var skippedReasons: [OptimizeTask: String]

    public init(plans: [OptimizePlan], skippedTasks: [OptimizeTask], skippedReasons: [OptimizeTask: String] = [:]) {
        self.plans = plans
        self.skippedTasks = skippedTasks
        self.skippedReasons = skippedReasons
    }

    public static func defaultMaintenance(
        tasks: [OptimizeTask] = OptimizeTask.allCases,
        safetyContext: OptimizeSafetyContext = OptimizeSafetyContext()
    ) -> OptimizeBatchPlan {
        var plans = [OptimizePlan]()
        var skippedTasks = [OptimizeTask]()
        var skippedReasons = [OptimizeTask: String]()
        let safetyPolicy = OptimizeSafetyPolicy(context: safetyContext)

        for task in tasks {
            let plan = OptimizePlan(task: task)
            if plan.commands.isEmpty {
                skippedTasks.append(task)
                skippedReasons[task] = plan.summary
            } else if task.requiresAdmin {
                skippedTasks.append(task)
                skippedReasons[task] = "Needs administrator privileges — run it yourself when needed."
            } else if let skipReason = safetyPolicy.decision(for: task).skipReason {
                skippedTasks.append(task)
                skippedReasons[task] = skipReason
            } else {
                plans.append(plan)
            }
        }

        return OptimizeBatchPlan(plans: plans, skippedTasks: skippedTasks, skippedReasons: skippedReasons)
    }

    public var commandCount: Int {
        plans.reduce(0) { $0 + $1.commands.count }
    }
}

public struct OptimizeBatchConfirmationSummary: Equatable, Sendable {
    public var title: String
    public var runnableTaskCount: Int
    public var commandCount: Int
    public var stagedTaskCount: Int
    public var runnableLines: [String]
    public var commandLines: [String]
    public var stagedLines: [String]

    public init(batch: OptimizeBatchPlan) {
        title = "Run default maintenance?"
        runnableTaskCount = batch.plans.count
        commandCount = batch.commandCount
        stagedTaskCount = batch.skippedTasks.count
        runnableLines = batch.plans.map { $0.task.title }
        commandLines = batch.plans.flatMap { plan in
            plan.commands.map(Self.commandLabel)
        }
        stagedLines = batch.skippedTasks.map { task in
            "\(task.title): \(batch.skippedReasons[task] ?? "Staged by safety policy")"
        }
    }

    public var confirmationMessage: String {
        var lines = [
            "\(runnableTaskCount) \(Self.plural("runnable task", runnableTaskCount)) · \(commandCount) \(Self.plural("command", commandCount)) · \(stagedTaskCount) staged",
            "Mode: Run local maintenance commands"
        ]

        if !runnableLines.isEmpty {
            lines.append("Runnable: \(runnableLines.joined(separator: ", "))")
        }
        if !commandLines.isEmpty {
            let prefix = commandLines.count == 1 ? "Command" : "Commands"
            lines.append("\(prefix): \(commandLines.joined(separator: "\n"))")
        }
        if !stagedLines.isEmpty {
            lines.append("Staged: \(stagedLines.joined(separator: "\n"))")
        }

        return lines.joined(separator: "\n")
    }

    private static func plural(_ singular: String, _ count: Int) -> String {
        count == 1 ? singular : "\(singular)s"
    }

    private static func commandLabel(_ command: OptimizeCommand) -> String {
        let executable = URL(fileURLWithPath: command.executablePath).lastPathComponent
        return ([executable] + command.arguments).joined(separator: " ")
    }
}

public struct OptimizeTaskConfirmationSummary: Equatable, Sendable {
    public var title: String
    public var riskLine: String
    public var commandLines: [String]
    public var effectLines: [String]
    public var confirmationMessage: String

    public init(plan: OptimizePlan) {
        title = "Run \(plan.task.title)?"
        riskLine = "Risk: \(plan.riskLevel.rawValue.capitalized)"
        commandLines = plan.commands.map(Self.commandLabel)
        effectLines = plan.effects

        var lines = [
            plan.confirmationMessage,
            riskLine,
            "Mode: Run local maintenance \(plan.commands.count == 1 ? "command" : "commands")"
        ]
        if !commandLines.isEmpty {
            let prefix = commandLines.count == 1 ? "Command" : "Commands"
            lines.append("\(prefix): \(commandLines.joined(separator: "\n"))")
        }
        if !plan.summary.isEmpty {
            lines.append(plan.summary)
        }
        if !effectLines.isEmpty {
            lines.append(effectLines.joined(separator: "\n"))
        }
        confirmationMessage = lines.joined(separator: "\n")
    }

    private static func commandLabel(_ command: OptimizeCommand) -> String {
        let executable = URL(fileURLWithPath: command.executablePath).lastPathComponent
        return ([executable] + command.arguments).joined(separator: " ")
    }
}

public enum OptimizeExecutionStatus: String, Codable, Sendable {
    case succeeded
    case failed
}

public struct OptimizeOperationLogEntry: Identifiable, Equatable, Sendable {
    public var id: String
    public var command: OptimizeCommand
    public var status: OptimizeExecutionStatus
    public var output: String
    public var executedAt: Date

    public init(
        command: OptimizeCommand,
        status: OptimizeExecutionStatus,
        output: String,
        executedAt: Date = Date()
    ) {
        id = "\(executedAt.timeIntervalSince1970)-\(command.executablePath)-\(command.arguments.joined(separator: "-"))"
        self.command = command
        self.status = status
        self.output = output
        self.executedAt = executedAt
    }
}

public struct OptimizeExecutionResult: Equatable, Sendable {
    public var task: OptimizeTask
    public var status: OptimizeExecutionStatus
    public var entries: [OptimizeOperationLogEntry]
    public var executedAt: Date

    public init(
        task: OptimizeTask,
        status: OptimizeExecutionStatus,
        entries: [OptimizeOperationLogEntry],
        executedAt: Date = Date()
    ) {
        self.task = task
        self.status = status
        self.entries = entries
        self.executedAt = executedAt
    }
}

public struct OptimizeExecutor {
    public typealias Runner = @Sendable (OptimizeCommand) -> CommandResult

    private var runner: Runner

    public init(runner: @escaping Runner = OptimizeExecutor.defaultRunner) {
        self.runner = runner
    }

    public func execute(plan: OptimizePlan, at date: Date = Date()) -> OptimizeExecutionResult {
        var entries = [OptimizeOperationLogEntry]()
        for command in plan.commands {
            let result = runner(command)
            let status: OptimizeExecutionStatus = result.exitCode == 0 ? .succeeded : .failed
            let output = result.stderr.isEmpty ? result.stdout : result.stderr
            entries.append(OptimizeOperationLogEntry(
                command: command,
                status: status,
                output: output,
                executedAt: date
            ))

            if status == .failed {
                return OptimizeExecutionResult(task: plan.task, status: .failed, entries: entries, executedAt: date)
            }
        }

        return OptimizeExecutionResult(task: plan.task, status: .succeeded, entries: entries, executedAt: date)
    }

    public func execute(
        batch: OptimizeBatchPlan,
        at date: Date = Date(),
        onPlanStart: ((OptimizeTask) -> Void)? = nil
    ) -> [OptimizeExecutionResult] {
        var results = [OptimizeExecutionResult]()

        for plan in batch.plans {
            onPlanStart?(plan.task)
            let result = execute(plan: plan, at: date)
            results.append(result)
            if result.status == .failed {
                break
            }
        }

        return results
    }

    public static func defaultRunner(_ command: OptimizeCommand) -> CommandResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: command.executablePath)
        process.arguments = command.arguments
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
            let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return CommandResult(exitCode: process.terminationStatus, stdout: stdoutText, stderr: stderrText)
        } catch {
            return CommandResult(exitCode: 127, stdout: "", stderr: error.localizedDescription)
        }
    }
}

public extension OptimizeTask {
    var reviewSummary: String {
        switch self {
        case .quickLook:
            "Reset Quick Look generator cache."
        case .launchServices:
            "Re-register apps with Launch Services for the local and user domains."
        case .periodicMaintenance:
            "Run macOS daily, weekly, and monthly periodic maintenance scripts."
        case .savedApplicationState:
            "Move saved application state files to Trash via the Clean workflow before execution."
        case .dockRefresh:
            "Restart Dock to refresh Dock and Mission Control state."
        }
    }

    var defaultEffects: [String] {
        switch self {
        case .quickLook:
            [
                "Refreshes Finder preview generation.",
                "Does not delete user files."
            ]
        case .launchServices:
            [
                "Re-registers apps in the local and user domains (incremental, no full rebuild).",
                "May briefly refresh Open With and default-app resolution."
            ]
        case .periodicMaintenance:
            [
                "Runs macOS daily, weekly, and monthly maintenance scripts.",
                "May take a while on large log sets."
            ]
        case .savedApplicationState:
            [
                "Staged until the Clean workflow can review saved state files.",
                "Will use Trash, not permanent deletion."
            ]
        case .dockRefresh:
            [
                "Restarts Dock.",
                "Refreshes Mission Control, Spaces, and Dock state."
            ]
        }
    }

    var defaultConfirmationMessage: String {
        switch self {
        case .quickLook:
            "Run Quick Look cache reset now?"
        case .launchServices:
            "Re-register apps with Launch Services now?"
        case .periodicMaintenance:
            "Run macOS periodic maintenance scripts now?"
        case .savedApplicationState:
            "This task is staged until Clean can review saved application state files."
        case .dockRefresh:
            "Restart Dock and refresh Mission Control state now?"
        }
    }

    var defaultRiskLevel: OptimizeRiskLevel {
        switch self {
        case .quickLook, .periodicMaintenance:
            .low
        case .launchServices, .savedApplicationState, .dockRefresh:
            .medium
        }
    }

    /// Tasks that only do meaningful work as root. They stay individually runnable but are
    /// kept out of the one-click default batch (which runs unprivileged).
    var requiresAdmin: Bool {
        switch self {
        case .periodicMaintenance: true
        default: false
        }
    }

    var defaultCommands: [OptimizeCommand] {
        switch self {
        case .quickLook:
            [OptimizeCommand(executablePath: "/usr/bin/qlmanage", arguments: ["-r"])]
        case .launchServices:
            // Incremental re-register only. NOT "-kill" (wipes the whole LaunchServices DB and
            // hangs the GUI while it rebuilds) and NOT "-domain system" (needs root, fails).
            [OptimizeCommand(
                executablePath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                arguments: ["-r", "-domain", "local", "-domain", "user"]
            )]
        case .periodicMaintenance:
            [OptimizeCommand(executablePath: "/usr/sbin/periodic", arguments: ["daily", "weekly", "monthly"])]
        case .savedApplicationState:
            []
        case .dockRefresh:
            [OptimizeCommand(executablePath: "/usr/bin/killall", arguments: ["Dock"])]
        }
    }
}
