import Foundation
import Observation
import ThermoMoleCore

@MainActor
@Observable
public final class MemoryModel {
    public private(set) var memoryPurgeState = OperationState.idle
    public private(set) var memoryPurgeLog = [MemoryPurgeResult]()

    public typealias Purge = @Sendable (MemoryPurgePlan) -> MemoryPurgeResult

    private let currentSnapshot: () -> SystemSnapshot
    private let purge: Purge
    private let logOperation: (OperationHistoryEntry) -> Void
    private let onChanged: () -> Void

    public init(
        currentSnapshot: @escaping () -> SystemSnapshot,
        purge: @escaping Purge,
        logOperation: @escaping (OperationHistoryEntry) -> Void,
        onChanged: @escaping () -> Void
    ) {
        self.currentSnapshot = currentSnapshot
        self.purge = purge
        self.logOperation = logOperation
        self.onChanged = onChanged
    }

    public func runMemoryPurge() {
        guard !memoryPurgeState.isRunning else { return }
        let snapshot = currentSnapshot()
        let report = MemoryDoctorReport(memory: snapshot.memory, topProcesses: snapshot.topProcesses)
        let plan = MemoryPurgePlan(report: report)
        guard plan.canExecute else {
            memoryPurgeState = memoryPurgeState.failed(message: "Requires critical memory pressure", at: Date())
            return
        }

        memoryPurgeState = memoryPurgeState.started(message: "Running advanced purge")
        let purge = self.purge
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) { purge(plan) }.value
            guard let self else { return }
            memoryPurgeLog = [result] + memoryPurgeLog
            logOperation(OperationHistoryEntry.memoryPurge(result))
            onChanged()
            switch result.status {
            case .succeeded:
                memoryPurgeState = memoryPurgeState.finished(message: "Advanced purge complete", at: result.executedAt)
            case .skipped:
                memoryPurgeState = memoryPurgeState.finished(message: result.message, at: result.executedAt)
            case .failed:
                memoryPurgeState = memoryPurgeState.failed(message: result.message, at: result.executedAt)
            }
        }
    }
}
