import Foundation
import Observation
import AppKit
import ThermoMoleCore

@MainActor
@Observable
final class OptimizeModel {
    private(set) var optimizeState = OperationState.idle
    private(set) var optimizeLog = [OptimizeExecutionResult]()
    private(set) var optimizeSafetyContext = OptimizeSafetyContext()

    private let currentSnapshot: () -> SystemSnapshot
    private let logOperation: (OperationHistoryEntry) -> Void
    private let onChanged: () -> Void

    init(
        currentSnapshot: @escaping () -> SystemSnapshot,
        logOperation: @escaping (OperationHistoryEntry) -> Void,
        onChanged: @escaping () -> Void
    ) {
        self.currentSnapshot = currentSnapshot
        self.logOperation = logOperation
        self.onChanged = onChanged
    }

    func runOptimizeTask(_ task: OptimizeTask) {
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
        Task.detached(priority: .utility) {
            OptimizeExecutor().execute(plan: plan)
        }.receive(on: MainActor.self) { [weak self] result in
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

    func runDefaultOptimize() {
        guard !optimizeState.isRunning else { return }
        let context = makeOptimizeSafetyContext()
        optimizeSafetyContext = context
        let batch = OptimizeBatchPlan.defaultMaintenance(safetyContext: context)
        guard !batch.plans.isEmpty else {
            optimizeState = optimizeState.failed(message: "No runnable maintenance")
            return
        }

        optimizeState = optimizeState.started(message: "Running \(batch.plans.count) maintenance tasks")
        Task.detached(priority: .utility) {
            OptimizeExecutor().execute(batch: batch)
        }.receive(on: MainActor.self) { [weak self] results in
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

    func refreshOptimizeSafetyContext() {
        // Read main-actor state here; run the slow system_profiler/scutil probes
        // off-main so the Optimize tab's onAppear no longer blocks for seconds.
        let snapshot = currentSnapshot()
        let isOnBattery = snapshot.battery.percent > 0 && !snapshot.battery.isOnACPower
        let hasExternalDisplay = NSScreen.screens.count > 1
        Task.detached(priority: .utility) { [weak self] in
            let bluetooth = Self.probeBluetooth()
            let context = OptimizeSafetyContext(
                isOnBatteryPower: isOnBattery,
                hasActiveVPN: Self.probeActiveVPN(),
                hasExternalDisplay: hasExternalDisplay,
                hasExternalAudio: Self.probeExternalAudio(),
                hasBluetoothHID: bluetooth.hid,
                hasBluetoothAudio: bluetooth.audio
            )
            await MainActor.run { self?.optimizeSafetyContext = context }
        }
    }

    private func makeOptimizeSafetyContext() -> OptimizeSafetyContext {
        let snapshot = currentSnapshot()
        let bluetooth = Self.probeBluetooth()
        return OptimizeSafetyContext(
            isOnBatteryPower: snapshot.battery.percent > 0 && !snapshot.battery.isOnACPower,
            hasActiveVPN: Self.probeActiveVPN(),
            hasExternalDisplay: NSScreen.screens.count > 1,
            hasExternalAudio: Self.probeExternalAudio(),
            hasBluetoothHID: bluetooth.hid,
            hasBluetoothAudio: bluetooth.audio
        )
    }

    // These probes only shell out (no actor state), so they are nonisolated static
    // and safe to run off the main actor — see refreshOptimizeSafetyContext.
    nonisolated private static func probeActiveVPN() -> Bool {
        let result = Shell.run("/usr/sbin/scutil", ["--nc", "list"], timeoutSeconds: 1)
        guard result.status == 0 else { return false }
        return OptimizeSafetyContextParser.hasActiveVPN(scutilOutput: result.stdout)
    }

    nonisolated private static func probeExternalAudio() -> Bool {
        let result = Shell.run("/usr/sbin/system_profiler", ["SPAudioDataType"], timeoutSeconds: 2)
        guard result.status == 0 else { return false }
        return OptimizeSafetyContextParser.hasExternalAudio(systemProfilerAudioOutput: result.stdout)
    }

    nonisolated private static func probeBluetooth() -> (hid: Bool, audio: Bool) {
        let result = Shell.run("/usr/sbin/system_profiler", ["SPBluetoothDataType"], timeoutSeconds: 2)
        guard result.status == 0 else { return (hid: false, audio: false) }
        return (
            hid: OptimizeSafetyContextParser.hasBluetoothHID(systemProfilerBluetoothOutput: result.stdout),
            audio: OptimizeSafetyContextParser.hasBluetoothAudio(systemProfilerBluetoothOutput: result.stdout)
        )
    }
}
