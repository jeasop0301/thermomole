import Foundation
import Observation
import ThermoMoleCore

@MainActor
@Observable
public final class OptimizeModel {
    public private(set) var optimizeState = OperationState.idle
    public private(set) var optimizeLog = [OptimizeExecutionResult]()
    public private(set) var optimizeSafetyContext = OptimizeSafetyContext()

    public typealias Execute = @Sendable (OptimizePlan) -> OptimizeExecutionResult
    public typealias ExecuteBatch = @Sendable (OptimizeBatchPlan) -> [OptimizeExecutionResult]

    private let currentSnapshot: () -> SystemSnapshot
    private let hasExternalDisplay: () -> Bool
    private let probeSafety: @Sendable () -> OptimizeSafetyProbe
    private let execute: Execute
    private let executeBatch: ExecuteBatch
    private let logOperation: (OperationHistoryEntry) -> Void
    private let onChanged: () -> Void

    public init(
        currentSnapshot: @escaping () -> SystemSnapshot,
        hasExternalDisplay: @escaping () -> Bool,
        probeSafety: @escaping @Sendable () -> OptimizeSafetyProbe,
        execute: @escaping Execute,
        executeBatch: @escaping ExecuteBatch,
        logOperation: @escaping (OperationHistoryEntry) -> Void,
        onChanged: @escaping () -> Void
    ) {
        self.currentSnapshot = currentSnapshot
        self.hasExternalDisplay = hasExternalDisplay
        self.probeSafety = probeSafety
        self.execute = execute
        self.executeBatch = executeBatch
        self.logOperation = logOperation
        self.onChanged = onChanged
    }

    public func runOptimizeTask(_ task: OptimizeTask) {
        guard !optimizeState.isRunning else { return }
        let context = makeOptimizeSafetyContext()
        optimizeSafetyContext = context
        if let skipReason = OptimizeSafetyPolicy(context: context).decision(for: task).skipReason {
            optimizeState = optimizeState.finished(message: "\(task.title) staged: \(skipReason)", at: Date())
            return
        }
        let plan = OptimizePlan(task: task)
        guard !plan.commands.isEmpty else {
            optimizeState = optimizeState.failed(message: "No runnable command")
            return
        }

        optimizeState = optimizeState.started(message: "Running \(task.title)")
        let execute = self.execute
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) { execute(plan) }.value
            guard let self else { return }
            optimizeLog = [result] + optimizeLog
            logOperation(OperationHistoryEntry.optimize(
                title: result.task.title,
                results: [result],
                skippedCount: 0
            ))
            onChanged()
            switch result.status {
            case .succeeded:
                optimizeState = optimizeState.finished(message: "\(result.task.title) complete", at: Date())
            case .failed:
                optimizeState = optimizeState.failed(message: "\(result.task.title) failed", at: Date())
            }
        }
    }

    public func runDefaultOptimize() {
        guard !optimizeState.isRunning else { return }
        let context = makeOptimizeSafetyContext()
        optimizeSafetyContext = context
        let batch = OptimizeBatchPlan.defaultMaintenance(safetyContext: context)
        guard !batch.plans.isEmpty else {
            optimizeState = optimizeState.failed(message: "No runnable maintenance")
            return
        }

        optimizeState = optimizeState.started(message: "Running \(batch.plans.count) maintenance tasks")
        let executeBatch = self.executeBatch
        Task { [weak self] in
            let results = await Task.detached(priority: .utility) { executeBatch(batch) }.value
            guard let self else { return }
            optimizeLog = results.reversed() + optimizeLog
            logOperation(OperationHistoryEntry.optimize(
                title: "Default Optimize",
                results: results,
                skippedCount: batch.skippedTasks.count
            ))
            onChanged()
            if let failed = results.first(where: { $0.status == .failed }) {
                optimizeState = optimizeState.failed(message: "\(failed.task.title) failed", at: Date())
            } else {
                let skippedText = batch.skippedTasks.isEmpty ? "" : " · \(batch.skippedTasks.count) staged"
                optimizeState = optimizeState.finished(
                    message: "\(results.count) tasks complete\(skippedText)",
                    at: Date()
                )
            }
        }
    }

    public func refreshOptimizeSafetyContext() {
        // Read main-actor state here; run the slow probes off-main so the Optimize
        // tab's onAppear no longer blocks for seconds.
        let snapshot = currentSnapshot()
        let isOnBattery = snapshot.battery.percent > 0 && !snapshot.battery.isOnACPower
        let hasExternalDisplay = self.hasExternalDisplay()
        let probeSafety = self.probeSafety
        Task.detached(priority: .utility) { [weak self] in
            let probe = probeSafety()
            let context = OptimizeSafetyContext(
                isOnBatteryPower: isOnBattery,
                hasActiveVPN: probe.hasActiveVPN,
                hasExternalDisplay: hasExternalDisplay,
                hasExternalAudio: probe.hasExternalAudio,
                hasBluetoothHID: probe.hasBluetoothHID,
                hasBluetoothAudio: probe.hasBluetoothAudio
            )
            await MainActor.run { self?.optimizeSafetyContext = context }
        }
    }

    private func makeOptimizeSafetyContext() -> OptimizeSafetyContext {
        let snapshot = currentSnapshot()
        let probe = probeSafety()
        return OptimizeSafetyContext(
            isOnBatteryPower: snapshot.battery.percent > 0 && !snapshot.battery.isOnACPower,
            hasActiveVPN: probe.hasActiveVPN,
            hasExternalDisplay: hasExternalDisplay(),
            hasExternalAudio: probe.hasExternalAudio,
            hasBluetoothHID: probe.hasBluetoothHID,
            hasBluetoothAudio: probe.hasBluetoothAudio
        )
    }
}
