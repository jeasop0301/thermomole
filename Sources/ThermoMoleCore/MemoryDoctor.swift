import Foundation

public enum MemoryDoctorLevel: String, Equatable, Sendable {
    case calm
    case watch
    case critical

    public var title: String {
        switch self {
        case .calm: "Calm"
        case .watch: "Warning"
        case .critical: "Critical"
        }
    }
}

public enum MemoryDoctorAction: String, Equatable, Sendable {
    case none
    case reviewProcesses
}

public struct MemoryDoctorReport: Equatable, Sendable {
    public var memory: MemorySnapshot
    public var topProcesses: [ProcessSnapshot]
    public var level: MemoryDoctorLevel
    public var primaryAction: MemoryDoctorAction
    public var allowsPurge: Bool
    public var summary: String

    public init(memory: MemorySnapshot, topProcesses: [ProcessSnapshot]) {
        self.memory = memory
        self.topProcesses = topProcesses.sorted { $0.memoryBytes > $1.memoryBytes }

        switch memory.pressure {
        case .normal:
            level = .calm
            primaryAction = .none
            allowsPurge = false
            summary = "Memory pressure is normal. No cleanup needed."
        case .warning:
            level = .watch
            primaryAction = .reviewProcesses
            allowsPurge = false
            summary = "Memory pressure is elevated. Review top memory processes first."
        case .critical:
            level = .critical
            primaryAction = .reviewProcesses
            allowsPurge = true
            summary = "Memory pressure is critical. Review top processes before considering advanced cache purge."
        }
    }

    public var topMemoryProcess: ProcessSnapshot? {
        topProcesses.first
    }
}

public enum MemoryPurgePlanStatus: String, Codable, Equatable, Sendable {
    case disabled
    case ready
}

public struct MemoryPurgePlan: Equatable, Sendable {
    public var report: MemoryDoctorReport
    public var status: MemoryPurgePlanStatus
    public var commands: [OptimizeCommand]
    public var summary: String
    public var confirmationMessage: String

    public init(report: MemoryDoctorReport) {
        self.report = report
        if report.allowsPurge {
            status = .ready
            commands = [OptimizeCommand(executablePath: "/usr/bin/purge", arguments: [])]
            summary = "Advanced purge is available because memory pressure is critical."
            confirmationMessage = "Run a temporary disk/file cache purge? This does not free anonymous app memory, can make next app or file access slower, and should only be used after reviewing top processes."
        } else {
            status = .disabled
            commands = []
            summary = "Advanced purge is disabled until memory pressure is critical."
            confirmationMessage = "Memory pressure is not critical. Review Memory Doctor instead."
        }
    }

    public var canExecute: Bool {
        status == .ready && !commands.isEmpty
    }
}

public enum MemoryPurgeStatus: String, Codable, Equatable, Sendable {
    case succeeded
    case failed
    case skipped
}

public struct MemoryPurgeResult: Identifiable, Equatable, Sendable {
    public var id: String
    public var status: MemoryPurgeStatus
    public var command: OptimizeCommand?
    public var message: String
    public var executedAt: Date

    public init(
        status: MemoryPurgeStatus,
        command: OptimizeCommand? = nil,
        message: String,
        executedAt: Date = Date()
    ) {
        self.status = status
        self.command = command
        self.message = message
        self.executedAt = executedAt
        id = "\(executedAt.timeIntervalSince1970)-memory-purge-\(status.rawValue)"
    }
}

public struct MemoryPurgeExecutor {
    public typealias Runner = @Sendable (OptimizeCommand) -> CommandResult

    private var runner: Runner

    public init(runner: @escaping Runner = OptimizeExecutor.defaultRunner) {
        self.runner = runner
    }

    public func execute(plan: MemoryPurgePlan, at date: Date = Date()) -> MemoryPurgeResult {
        guard plan.canExecute, let command = plan.commands.first else {
            return MemoryPurgeResult(
                status: .skipped,
                message: "Advanced purge requires critical memory pressure.",
                executedAt: date
            )
        }

        let result = runner(command)
        if result.exitCode == 0 {
            let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return MemoryPurgeResult(
                status: .succeeded,
                command: command,
                message: output.isEmpty ? "Purge completed." : output,
                executedAt: date
            )
        }

        let output = (result.stderr.isEmpty ? result.stdout : result.stderr)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return MemoryPurgeResult(
            status: .failed,
            command: command,
            message: output.isEmpty ? "Purge failed with exit code \(result.exitCode)." : output,
            executedAt: date
        )
    }
}
