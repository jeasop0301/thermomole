import Foundation

public enum OperationHistoryKind: String, Codable, Equatable, Sendable {
    // Legacy cases retained for decoding historical log entries
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
