import Foundation

public struct DiskEntryTrashResult: Identifiable, Equatable, Sendable {
    public var id: String
    public var entry: DiskEntry
    public var status: CleanupOperationStatus
    public var destinationURL: URL?
    public var message: String
    public var executedAt: Date

    public init(
        entry: DiskEntry,
        status: CleanupOperationStatus,
        destinationURL: URL? = nil,
        message: String,
        executedAt: Date = Date()
    ) {
        id = "\(executedAt.timeIntervalSince1970)-\(entry.id)-\(status.rawValue)"
        self.entry = entry
        self.status = status
        self.destinationURL = destinationURL
        self.message = message
        self.executedAt = executedAt
    }
}

public struct DiskEntryTrashExecutor {
    public typealias TrashItem = @Sendable (URL) throws -> URL

    public var validator: ProtectedPathValidator
    private var trashItem: TrashItem

    public init(
        validator: ProtectedPathValidator = ProtectedPathValidator(),
        trashItem: @escaping TrashItem = DiskEntryTrashExecutor.defaultTrashItem
    ) {
        self.validator = validator
        self.trashItem = trashItem
    }

    public func moveToTrash(_ entry: DiskEntry, at date: Date = Date()) -> DiskEntryTrashResult {
        let resolvedURL = entry.url.resolvingSymlinksInPath().standardizedFileURL
        guard validator.canDelete(entry.url, resolvedURL: resolvedURL) else {
            return DiskEntryTrashResult(
                entry: entry,
                status: .skipped,
                message: "Protected path skipped",
                executedAt: date
            )
        }

        do {
            let destination = try trashItem(entry.url)
            return DiskEntryTrashResult(
                entry: entry,
                status: .succeeded,
                destinationURL: destination,
                message: "Moved to Trash",
                executedAt: date
            )
        } catch {
            return DiskEntryTrashResult(
                entry: entry,
                status: .failed,
                message: error.localizedDescription,
                executedAt: date
            )
        }
    }

    public static func defaultTrashItem(_ url: URL) throws -> URL {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        return (resultingURL as URL?) ?? url
    }
}
