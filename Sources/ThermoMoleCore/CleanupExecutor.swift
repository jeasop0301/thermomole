import Foundation

public enum CleanupExecutionMode: String, Codable, Sendable {
    case trash
}

public enum CleanupOperationStatus: String, Codable, Sendable {
    case succeeded
    case skipped
    case failed
}

public struct CleanupOperationLogEntry: Identifiable, Equatable, Sendable {
    public var id: String
    public var item: CleanupItem
    public var mode: CleanupExecutionMode
    public var status: CleanupOperationStatus
    public var destinationURL: URL?
    public var message: String
    public var executedAt: Date

    public init(
        item: CleanupItem,
        mode: CleanupExecutionMode,
        status: CleanupOperationStatus,
        destinationURL: URL? = nil,
        message: String,
        executedAt: Date = Date()
    ) {
        id = "\(executedAt.timeIntervalSince1970)-\(item.id)-\(status.rawValue)"
        self.item = item
        self.mode = mode
        self.status = status
        self.destinationURL = destinationURL
        self.message = message
        self.executedAt = executedAt
    }
}

public struct CleanupExecutionResult: Equatable, Sendable {
    public var entries: [CleanupOperationLogEntry]

    public init(entries: [CleanupOperationLogEntry]) {
        self.entries = entries
    }

    public var succeededCount: Int {
        entries.filter { $0.status == .succeeded }.count
    }

    public var skippedCount: Int {
        entries.filter { $0.status == .skipped }.count
    }

    public var failedCount: Int {
        entries.filter { $0.status == .failed }.count
    }

    public var reclaimedBytes: UInt64 {
        entries
            .filter { $0.status == .succeeded }
            .reduce(0) { $0 + $1.item.sizeBytes }
    }
}

public struct CleanupExecutor {
    public typealias TrashItem = @Sendable (URL) throws -> URL

    public var validator: ProtectedPathValidator
    private var trashItem: TrashItem

    public init(
        validator: ProtectedPathValidator = ProtectedPathValidator(),
        trashItem: @escaping TrashItem = CleanupExecutor.defaultTrashItem
    ) {
        self.validator = validator
        self.trashItem = trashItem
    }

    public func execute(
        items: [CleanupItem],
        selection: CleanupReviewSelection,
        mode: CleanupExecutionMode
    ) -> CleanupExecutionResult {
        let selectedItems = items.filter { selection.contains($0) }
        let entries = selectedItems.map { item in
            execute(item: item, mode: mode)
        }
        return CleanupExecutionResult(entries: entries)
    }

    private func execute(item: CleanupItem, mode: CleanupExecutionMode) -> CleanupOperationLogEntry {
        let resolvedURL = item.url.resolvingSymlinksInPath().standardizedFileURL
        guard validator.canDelete(item.url, resolvedURL: resolvedURL) else {
            return CleanupOperationLogEntry(
                item: item,
                mode: mode,
                status: .skipped,
                message: "Protected path skipped"
            )
        }

        switch mode {
        case .trash:
            do {
                let destination = try trashItem(item.url)
                return CleanupOperationLogEntry(
                    item: item,
                    mode: mode,
                    status: .succeeded,
                    destinationURL: destination,
                    message: "Moved to Trash"
                )
            } catch {
                return CleanupOperationLogEntry(
                    item: item,
                    mode: mode,
                    status: .failed,
                    message: error.localizedDescription
                )
            }
        }
    }

    public static func defaultTrashItem(_ url: URL) throws -> URL {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        return (resultingURL as URL?) ?? url
    }
}
