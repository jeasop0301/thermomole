import Foundation
import Observation
import ThermoMoleCore

@MainActor
@Observable
public final class AnalyzeModel {
    public private(set) var diskEntries = [DiskEntry]()
    public private(set) var diskTrashLog = [DiskEntryTrashResult]()
    public private(set) var diskAnalysisPath = DiskAnalysisPath(rootURL: FileManager.default.homeDirectoryForCurrentUser)
    public private(set) var analyzeState = OperationState.idle

    public typealias Analyze = @Sendable (URL, @Sendable () -> Bool) -> [DiskEntry]
    public typealias Trash = @Sendable (DiskEntry) -> DiskEntryTrashResult

    private let analyze: Analyze
    private let trash: Trash
    private let logOperation: (OperationHistoryEntry) -> Void
    private let onChanged: () -> Void

    private var analyzeTask: Task<[DiskEntry], Never>?
    private var analyzeRequestID = UUID()

    public init(
        analyze: @escaping Analyze,
        trash: @escaping Trash,
        logOperation: @escaping (OperationHistoryEntry) -> Void,
        onChanged: @escaping () -> Void
    ) {
        self.analyze = analyze
        self.trash = trash
        self.logOperation = logOperation
        self.onChanged = onChanged
    }

    public func analyzeHome() {
        guard !analyzeState.isRunning else { return }
        diskAnalysisPath.reset(to: FileManager.default.homeDirectoryForCurrentUser)
        analyzeCurrentDiskURL(message: "Analyzing home folder")
    }

    public func analyzeFolder(_ url: URL) {
        guard !analyzeState.isRunning else { return }
        diskAnalysisPath.reset(to: url)
        analyzeCurrentDiskURL(message: "Analyzing \(url.lastPathComponent)")
    }

    public func analyzeDiskEntry(_ entry: DiskEntry) {
        guard entry.isDirectory, !analyzeState.isRunning else { return }
        diskAnalysisPath.push(entry.url)
        analyzeCurrentDiskURL(message: "Analyzing \(entry.url.lastPathComponent)")
    }

    public func analyzeDiskBreadcrumb(_ breadcrumb: DiskBreadcrumb) {
        guard !analyzeState.isRunning else { return }
        diskAnalysisPath.popTo(breadcrumb.url)
        analyzeCurrentDiskURL(message: "Analyzing \(breadcrumb.title)")
    }

    public func analyzeParentDiskURL() {
        guard diskAnalysisPath.canGoUp, !analyzeState.isRunning else { return }
        diskAnalysisPath.popUp()
        analyzeCurrentDiskURL(message: "Analyzing \(diskAnalysisPath.currentURL.lastPathComponent)")
    }

    public func cancelAnalyze() {
        guard analyzeState.isRunning else { return }
        analyzeTask?.cancel()
        analyzeTask = nil
        analyzeRequestID = UUID()
        analyzeState = analyzeState.finished(message: "Canceled", at: Date())
    }

    public func canTrashDiskEntry(_ entry: DiskEntry) -> Bool {
        let resolvedURL = entry.url.resolvingSymlinksInPath().standardizedFileURL
        return ProtectedPathValidator().canDelete(entry.url, resolvedURL: resolvedURL)
    }

    public func trashDiskEntry(_ entry: DiskEntry) {
        guard !analyzeState.isRunning else { return }
        analyzeState = analyzeState.started(message: "Moving \(entry.url.lastPathComponent) to Trash")
        let trash = self.trash
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) { trash(entry) }.value
            guard let self else { return }
            diskTrashLog = [result] + diskTrashLog
            logOperation(OperationHistoryEntry.analyzeTrash(result))
            if result.status == .succeeded {
                diskEntries.removeAll { $0.id == result.entry.id }
                onChanged()
            }
            switch result.status {
            case .succeeded:
                analyzeState = analyzeState.finished(message: "Moved to Trash", at: result.executedAt)
            case .skipped:
                analyzeState = analyzeState.finished(message: "Protected path skipped", at: result.executedAt)
            case .failed:
                analyzeState = analyzeState.failed(message: result.message, at: result.executedAt)
            }
        }
    }

    private func analyzeCurrentDiskURL(message: String) {
        let url = diskAnalysisPath.currentURL
        analyzeTask?.cancel()
        let requestID = UUID()
        analyzeRequestID = requestID
        analyzeState = analyzeState.started(message: message)
        let analyze = self.analyze
        let task = Task.detached(priority: .utility) {
            analyze(url, { Task.isCancelled })
        }
        analyzeTask = task
        Task { [weak self] in
            let entries = await task.value
            await MainActor.run {
                guard let self, self.analyzeRequestID == requestID, !task.isCancelled else { return }
                self.diskEntries = entries
                self.analyzeTask = nil
                self.analyzeState = self.analyzeState.finished(
                    message: "\(entries.count) entries",
                    at: Date()
                )
            }
        }
    }
}
