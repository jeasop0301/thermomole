import Foundation
import ThermoMoleCore
import ThermoMoleNative

@main
struct ThermoMoleCLI {
    static func main() async {
        do {
            let request = try TerminalCommandParser.parseRequest(Array(CommandLine.arguments.dropFirst()))
            switch request.command {
            case .status:
                let snapshot = await NativeSensorProvider().sample()
                print(try output(
                    text: TerminalOutputFormatter.status(snapshot),
                    json: { try TerminalOutputFormatter.jsonStatus(snapshot) },
                    format: request.outputFormat
                ))
            case .clean(let mode):
                let result = CleanupScanner().scan(preselection: .recommended)
                let plan = SmartCleanupReviewPlan(result)
                if mode == .execute {
                    let execution = CleanupExecutor().execute(
                        items: result.items,
                        selection: plan.selection,
                        mode: .trash
                    )
                    try? OperationHistoryStore.live.append(OperationHistoryEntry.cleanup(
                        kind: .clean,
                        title: "Smart Clean",
                        result: execution
                    ))
                    print(try output(
                        text: "Smart Clean\n\(execution.succeededCount) moved · \(TerminalOutputFormatter.formatTerminalBytes(execution.reclaimedBytes)) · \(execution.skippedCount) skipped · \(execution.failedCount) failed",
                        json: { try TerminalOutputFormatter.jsonCleanupExecution(command: "clean", title: "Smart Clean", result: execution) },
                        format: request.outputFormat
                    ))
                } else {
                    print(try output(
                        text: TerminalOutputFormatter.smartCleanPlan(plan),
                        json: { try TerminalOutputFormatter.jsonSmartCleanPlan(plan) },
                        format: request.outputFormat
                    ))
                }
            case .optimize(let mode):
                let batch = OptimizeBatchPlan.defaultMaintenance()
                if mode == .execute {
                    let results = OptimizeExecutor().execute(batch: batch)
                    let failed = results.filter { $0.status == .failed }.count
                    try? OperationHistoryStore.live.append(OperationHistoryEntry.optimize(
                        title: "Default Optimize",
                        results: results,
                        skippedCount: batch.skippedTasks.count
                    ))
                    print(try output(
                        text: "Default Optimize\n\(results.count) run · \(failed) failed · \(batch.skippedTasks.count) staged",
                        json: { try TerminalOutputFormatter.jsonOptimizeExecution(results, skippedCount: batch.skippedTasks.count) },
                        format: request.outputFormat
                    ))
                } else {
                    print(try output(
                        text: TerminalOutputFormatter.optimizeBatch(batch),
                        json: { try TerminalOutputFormatter.jsonOptimizeBatch(batch) },
                        format: request.outputFormat
                    ))
                }
            case .installer(let mode):
                let result = CleanupScanner().scan(categories: [.installers], preselection: .recommended)
                let plan = SmartCleanupReviewPlan(result)
                if mode == .execute {
                    let execution = CleanupExecutor().execute(
                        items: result.items,
                        selection: plan.selection,
                        mode: .trash
                    )
                    try? OperationHistoryStore.live.append(OperationHistoryEntry.cleanup(
                        kind: .installer,
                        title: "Installer Cleanup",
                        result: execution
                    ))
                    print(try output(
                        text: "Installer Cleanup\n\(execution.succeededCount) moved · \(TerminalOutputFormatter.formatTerminalBytes(execution.reclaimedBytes)) · \(execution.skippedCount) skipped · \(execution.failedCount) failed",
                        json: { try TerminalOutputFormatter.jsonCleanupExecution(command: "installer", title: "Installer Cleanup", result: execution) },
                        format: request.outputFormat
                    ))
                } else {
                    print(try output(
                        text: TerminalOutputFormatter.installerPlan(plan),
                        json: { try TerminalOutputFormatter.jsonInstallerPlan(plan) },
                        format: request.outputFormat
                    ))
                }
            case .uninstall(let query, let mode):
                let plan = AppUninstallPlan(query: query, apps: SoftwareInventory().installedApps())
                guard mode == .execute else {
                    print(try output(
                        text: TerminalOutputFormatter.appUninstallPlan(plan),
                        json: { try TerminalOutputFormatter.jsonAppUninstallPlan(plan) },
                        format: request.outputFormat
                    ))
                    break
                }
                guard plan.canExecute, let app = plan.selectedApp else {
                    print(try output(
                        text: TerminalOutputFormatter.appUninstallPlan(plan),
                        json: { try TerminalOutputFormatter.jsonAppUninstallPlan(plan) },
                        format: request.outputFormat
                    ))
                    Foundation.exit(65)
                }
                let result = AppUninstallExecutor().moveToTrash(app)
                try? OperationHistoryStore.live.append(OperationHistoryEntry.uninstall(result))
                print(try output(
                    text: TerminalOutputFormatter.appUninstallResult(result),
                    json: { try TerminalOutputFormatter.jsonAppUninstallResult(result) },
                    format: request.outputFormat
                ))
            case .analyze:
                let scopeURL = FileManager.default.homeDirectoryForCurrentUser
                let entries = DiskAnalyzer().analyze(scopeURL)
                let summary = DiskAnalysisSummary(scopeURL: scopeURL, entries: entries)
                if request.outputFormat == .json {
                    print(try TerminalOutputFormatter.jsonDiskAnalysis(summary))
                } else {
                    print(TerminalOutputFormatter.diskAnalysis(summary))
                    for entry in entries.prefix(10) {
                        print("\(TerminalOutputFormatter.formatTerminalBytes(entry.sizeBytes))\t\(entry.url.path)")
                    }
                }
            case .software:
                let inventory = SoftwareInventory()
                let apps = inventory.installedApps()
                let startupItems = inventory.startupItems()
                let summary = SoftwareSummary(apps: apps, startupItems: startupItems)
                print(try output(
                    text: TerminalOutputFormatter.software(summary),
                    json: { try TerminalOutputFormatter.jsonSoftware(summary) },
                    format: request.outputFormat
                ))
            case .memory:
                let report = await NativeSensorProvider().sampleMemoryReport()
                print(try output(
                    text: TerminalOutputFormatter.memoryDoctor(report),
                    json: { try TerminalOutputFormatter.jsonMemoryDoctor(report) },
                    format: request.outputFormat
                ))
            case .memoryPurge(let mode):
                let report = await NativeSensorProvider().sampleMemoryReport()
                let plan = MemoryPurgePlan(report: report)
                guard mode == .execute else {
                    print(try output(
                        text: TerminalOutputFormatter.memoryPurgePlan(plan),
                        json: { try TerminalOutputFormatter.jsonMemoryPurgePlan(plan) },
                        format: request.outputFormat
                    ))
                    break
                }
                guard plan.canExecute else {
                    print(try output(
                        text: TerminalOutputFormatter.memoryPurgePlan(plan),
                        json: { try TerminalOutputFormatter.jsonMemoryPurgePlan(plan) },
                        format: request.outputFormat
                    ))
                    Foundation.exit(65)
                }
                let result = MemoryPurgeExecutor().execute(plan: plan)
                try? OperationHistoryStore.live.append(OperationHistoryEntry.memoryPurge(result))
                print(try output(
                    text: TerminalOutputFormatter.memoryPurgeResult(result),
                    json: { try TerminalOutputFormatter.jsonMemoryPurgeResult(result) },
                    format: request.outputFormat
                ))
            case .history:
                let entries = (try? OperationHistoryStore.live.readRecent(limit: 20)) ?? []
                print(try output(
                    text: TerminalOutputFormatter.history(entries),
                    json: { try TerminalOutputFormatter.jsonHistory(entries) },
                    format: request.outputFormat
                ))
            case .help:
                print(TerminalOutputFormatter.help())
            }
        } catch let error as TerminalCommandError {
            fputs("\(errorMessage(error))\n\n\(TerminalOutputFormatter.help())\n", stderr)
            Foundation.exit(64)
        } catch {
            fputs("\(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func output(text: String, json: () throws -> String, format: TerminalOutputFormat) throws -> String {
        switch format {
        case .text:
            return text
        case .json:
            return try json()
        }
    }

    private static func errorMessage(_ error: TerminalCommandError) -> String {
        switch error {
        case .unknownCommand(let command):
            return "Unknown command: \(command)"
        case .unknownOption(let option):
            return "Unknown option: \(option)"
        case .missingArgument(let usage):
            return "Missing argument: \(usage)"
        }
    }
}
