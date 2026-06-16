import Foundation
import Observation
import ThermoMoleCore

@MainActor
@Observable
public final class CleanModel {
    public private(set) var result = CleanupScanResult(items: [], skipped: [])
    public private(set) var selection = CleanupReviewSelection(items: [])
    public private(set) var smartPlan: SmartCleanupReviewPlan?
    public private(set) var log: [CleanupOperationLogEntry] = []
    public private(set) var state: OperationState = .idle

    public typealias Scan = @Sendable (CleanupPreselectionMode) -> CleanupScanResult
    public typealias Execute = @Sendable ([CleanupItem], CleanupReviewSelection) -> CleanupExecutionResult

    private let scan: Scan
    private let execute: Execute
    private let logOperation: (OperationHistoryEntry) -> Void
    private let onCleaned: () -> Void

    public init(
        scan: @escaping Scan,
        execute: @escaping Execute,
        logOperation: @escaping (OperationHistoryEntry) -> Void,
        onCleaned: @escaping () -> Void
    ) {
        self.scan = scan
        self.execute = execute
        self.logOperation = logOperation
        self.onCleaned = onCleaned
    }

    public func runScan() async {
        guard !state.isRunning else { return }
        smartPlan = nil
        state = state.started(message: "Scanning review items")
        let scan = self.scan
        let scanned = await Task.detached(priority: .utility) { scan(.none) }.value
        result = scanned
        selection = CleanupReviewSelection(items: scanned.items)
        let summary = CleanupReviewSummary(scanned)
        state = state.finished(message: "\(summary.itemCount) items · \(formatBytes(summary.totalBytes))")
    }

    public func prepareSmartCleanup() async {
        guard !state.isRunning else { return }
        smartPlan = nil
        state = state.started(message: "Finding safe cleanup")
        let scan = self.scan
        let scanned = await Task.detached(priority: .utility) { scan(.recommended) }.value
        result = scanned
        selection = CleanupReviewSelection(items: scanned.items)
        let plan = SmartCleanupReviewPlan(scanned)
        if plan.hasSelection {
            smartPlan = plan
            state = state.finished(message: "\(plan.selectedItemCount) ready · \(formatBytes(plan.selectedBytes))")
        } else {
            state = state.finished(message: "Nothing safe to clean")
        }
    }

    public func setSelected(_ item: CleanupItem, _ isSelected: Bool) {
        selection.setSelected(item, isSelected: isSelected)
    }

    public func setSelected(_ items: [CleanupItem], _ isSelected: Bool) {
        selection.setSelected(items, isSelected: isSelected)
    }

    public func selectedBytes() -> UInt64 {
        selection.selectedBytes(in: result.items)
    }

    public func executeSelected() async {
        guard !state.isRunning, !selection.selectedIDs.isEmpty else { return }
        smartPlan = nil
        state = state.started(message: "Moving selected items to Trash")
        let items = result.items
        let currentSelection = selection
        let execute = self.execute
        let execution = await Task.detached(priority: .utility) { execute(items, currentSelection) }.value
        log = execution.entries + log
        logOperation(OperationHistoryEntry.cleanup(kind: .clean, title: "Clean Selected", result: execution))
        let succeededIDs = Set(execution.entries.filter { $0.status == .succeeded }.map(\.item.id))
        let remainingItems = result.items.filter { !succeededIDs.contains($0.id) }
        result = CleanupScanResult(items: remainingItems, skipped: result.skipped)
        selection = CleanupReviewSelection(items: remainingItems)
        onCleaned()
        state = state.finished(message: "\(execution.succeededCount) moved · \(formatBytes(execution.reclaimedBytes))")
    }
}
