import Foundation

public enum OperationHistoryKind: String, Codable, Equatable, Sendable {
    case clean
    case installer
    case optimize
    case analyzeTrash
    case uninstall
    case memoryPurge
}

public enum OperationHistoryStatus: String, Codable, Equatable, Sendable {
    case succeeded
    case failed
    case skipped
    case mixed

    public var title: String {
        switch self {
        case .succeeded: "Succeeded"
        case .failed: "Failed"
        case .skipped: "Skipped"
        case .mixed: "Mixed"
        }
    }
}

public struct OperationHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: OperationHistoryKind
    public var title: String
    public var status: OperationHistoryStatus
    public var itemCount: Int
    public var bytes: UInt64
    public var message: String
    public var executedAt: Date

    public init(
        kind: OperationHistoryKind,
        title: String,
        status: OperationHistoryStatus,
        itemCount: Int,
        bytes: UInt64,
        message: String,
        executedAt: Date = Date()
    ) {
        self.kind = kind
        self.title = title
        self.status = status
        self.itemCount = itemCount
        self.bytes = bytes
        self.message = message
        self.executedAt = executedAt
        id = "\(executedAt.timeIntervalSince1970)-\(kind.rawValue)-\(title)"
    }

    public static func cleanup(
        kind: OperationHistoryKind,
        title: String,
        result: CleanupExecutionResult,
        executedAt: Date = Date()
    ) -> OperationHistoryEntry {
        OperationHistoryEntry(
            kind: kind,
            title: title,
            status: status(
                succeeded: result.succeededCount,
                skipped: result.skippedCount,
                failed: result.failedCount
            ),
            itemCount: result.entries.count,
            bytes: result.reclaimedBytes,
            message: "\(result.succeededCount) moved · \(result.skippedCount) skipped · \(result.failedCount) failed",
            executedAt: executedAt
        )
    }

    public static func optimize(
        title: String,
        results: [OptimizeExecutionResult],
        skippedCount: Int,
        executedAt: Date = Date()
    ) -> OperationHistoryEntry {
        let failed = results.filter { $0.status == .failed }.count
        return OperationHistoryEntry(
            kind: .optimize,
            title: title,
            status: failed == 0 ? .succeeded : .failed,
            itemCount: results.count,
            bytes: 0,
            message: "\(results.count) run · \(failed) failed · \(skippedCount) staged",
            executedAt: executedAt
        )
    }

    public static func analyzeTrash(_ result: DiskEntryTrashResult) -> OperationHistoryEntry {
        OperationHistoryEntry(
            kind: .analyzeTrash,
            title: "Analyze Trash",
            status: historyStatus(result.status),
            itemCount: 1,
            bytes: result.status == .succeeded ? result.entry.sizeBytes : 0,
            message: result.message,
            executedAt: result.executedAt
        )
    }

    public static func uninstall(_ result: AppUninstallResult) -> OperationHistoryEntry {
        OperationHistoryEntry(
            kind: .uninstall,
            title: "Uninstall \(result.app.name)",
            status: result.status == .succeeded ? .succeeded : .failed,
            itemCount: 1,
            bytes: 0,
            message: result.message,
            executedAt: result.executedAt
        )
    }

    public static func memoryPurge(_ result: MemoryPurgeResult) -> OperationHistoryEntry {
        OperationHistoryEntry(
            kind: .memoryPurge,
            title: "Advanced Memory Purge",
            status: historyStatus(result.status),
            itemCount: result.command == nil ? 0 : 1,
            bytes: 0,
            message: result.message,
            executedAt: result.executedAt
        )
    }

    private static func status(succeeded: Int, skipped: Int, failed: Int) -> OperationHistoryStatus {
        let nonZero = [succeeded, skipped, failed].filter { $0 > 0 }.count
        if nonZero > 1 { return .mixed }
        if failed > 0 { return .failed }
        if skipped > 0 { return .skipped }
        return .succeeded
    }

    private static func historyStatus(_ status: CleanupOperationStatus) -> OperationHistoryStatus {
        switch status {
        case .succeeded: .succeeded
        case .skipped: .skipped
        case .failed: .failed
        }
    }

    private static func historyStatus(_ status: MemoryPurgeStatus) -> OperationHistoryStatus {
        switch status {
        case .succeeded: .succeeded
        case .skipped: .skipped
        case .failed: .failed
        }
    }
}

public struct OperationHistoryStore: Sendable {
    public var logURL: URL

    public init(logURL: URL = OperationHistoryStore.defaultLogURL) {
        self.logURL = logURL
    }

    public static var defaultLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("ThermoMole", isDirectory: true)
            .appendingPathComponent("operations.jsonl")
    }

    public static var live: OperationHistoryStore {
        OperationHistoryStore()
    }

    public func append(_ entry: OperationHistoryEntry) throws {
        try FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var data = try JSONEncoder().encode(entry)
        data.append(0x0A)

        if !FileManager.default.fileExists(atPath: logURL.path) {
            try data.write(to: logURL, options: .atomic)
            return
        }

        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.close()
    }

    public func readRecent(limit: Int) throws -> [OperationHistoryEntry] {
        guard limit > 0, FileManager.default.fileExists(atPath: logURL.path) else { return [] }
        let data = try Data(contentsOf: logURL)
        let lines = String(data: data, encoding: .utf8)?
            .split(separator: "\n")
            .map(String.init) ?? []
        let decoder = JSONDecoder()
        return lines
            .compactMap { line in
                try? decoder.decode(OperationHistoryEntry.self, from: Data(line.utf8))
            }
            .sorted { $0.executedAt > $1.executedAt }
            .prefix(limit)
            .map { $0 }
    }
}
