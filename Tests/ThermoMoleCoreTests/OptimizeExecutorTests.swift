import Foundation
import XCTest
@testable import ThermoMoleCore

final class OptimizeExecutorTests: XCTestCase {
    func testLaunchServicesUsesSafeIncrementalRefresh() {
        // -kill wipes and rebuilds the whole LaunchServices DB (freezes the GUI while it
        // rebuilds); the system domain needs root (fails). The default action must use a
        // safe, root-free incremental re-register.
        let plan = OptimizePlan(task: .launchServices)
        let command = plan.commands.first
        XCTAssertNotNil(command)
        XCTAssertFalse(command?.arguments.contains("-kill") ?? true, "lsregister -kill hangs the GUI")
        XCTAssertFalse(command?.arguments.contains("system") ?? true, "system domain needs root and fails")
        XCTAssertEqual(command?.arguments, ["-r", "-domain", "local", "-domain", "user"])
    }

    func testOptimizeTaskBuildsReviewablePlan() {
        let plan = OptimizePlan(task: .quickLook)

        XCTAssertEqual(plan.task, .quickLook)
        XCTAssertFalse(plan.commands.isEmpty)
        XCTAssertTrue(plan.requiresConfirmation)
        XCTAssertEqual(plan.riskLevel, .low)
        XCTAssertTrue(plan.summary.contains("Quick Look"))
        XCTAssertFalse(plan.effects.isEmpty)
        XCTAssertTrue(plan.confirmationMessage.contains("Quick Look"))
    }

    func testDockRefreshPlanExplainsUserVisibleEffects() {
        let plan = OptimizePlan(task: .dockRefresh)

        XCTAssertTrue(plan.effects.contains { $0.localizedCaseInsensitiveContains("Dock") })
        XCTAssertTrue(plan.effects.contains { $0.localizedCaseInsensitiveContains("Mission Control") })
        XCTAssertTrue(plan.confirmationMessage.localizedCaseInsensitiveContains("Dock"))
    }

    func testSavedApplicationStatePlanIsStagedWithoutCommands() {
        let plan = OptimizePlan(task: .savedApplicationState)

        XCTAssertTrue(plan.commands.isEmpty)
        XCTAssertTrue(plan.effects.contains { $0.localizedCaseInsensitiveContains("Clean") })
        XCTAssertTrue(plan.confirmationMessage.localizedCaseInsensitiveContains("staged"))
    }

    func testDefaultOptimizeBatchIncludesRunnableTasksAndSkipsStagedTasks() {
        let batch = OptimizeBatchPlan.defaultMaintenance()

        XCTAssertFalse(batch.plans.isEmpty)
        XCTAssertTrue(batch.plans.allSatisfy { !$0.commands.isEmpty })
        XCTAssertFalse(batch.plans.contains { $0.task == .savedApplicationState })
        XCTAssertTrue(batch.skippedTasks.contains(.savedApplicationState))
        XCTAssertGreaterThan(batch.commandCount, 0)
    }

    func testDefaultOptimizeBatchSkipsRiskyTasksWhenSafetyContextIsActive() {
        let context = OptimizeSafetyContext(
            isOnBatteryPower: true,
            hasActiveVPN: true,
            hasExternalDisplay: true,
            hasExternalAudio: true,
            hasBluetoothHID: true,
            hasBluetoothAudio: true
        )

        let batch = OptimizeBatchPlan.defaultMaintenance(safetyContext: context)

        XCTAssertEqual(batch.plans.map(\.task), [.quickLook])
        XCTAssertTrue(batch.skippedTasks.contains(.launchServices))
        XCTAssertTrue(batch.skippedTasks.contains(.periodicMaintenance))
        XCTAssertTrue(batch.skippedTasks.contains(.dockRefresh))
        XCTAssertTrue(batch.skippedTasks.contains(.savedApplicationState))
    }

    func testOptimizeBatchConfirmationSummaryDescribesRunnableCommandsAndStagedReasons() {
        let context = OptimizeSafetyContext(isOnBatteryPower: true, hasActiveVPN: true)
        let batch = OptimizeBatchPlan.defaultMaintenance(
            tasks: [.quickLook, .launchServices, .periodicMaintenance, .savedApplicationState],
            safetyContext: context
        )

        let summary = OptimizeBatchConfirmationSummary(batch: batch)

        XCTAssertEqual(summary.title, "Run default maintenance?")
        XCTAssertEqual(summary.runnableTaskCount, 1)
        XCTAssertEqual(summary.commandCount, 1)
        XCTAssertEqual(summary.stagedTaskCount, 3)
        XCTAssertTrue(summary.confirmationMessage.contains("1 runnable task · 1 command · 3 staged"))
        XCTAssertTrue(summary.confirmationMessage.contains("Runnable: Rebuild Quick Look"))
        XCTAssertTrue(summary.confirmationMessage.contains("Command: qlmanage -r"))
        XCTAssertTrue(summary.confirmationMessage.contains("Refresh Launch Services: Active VPN detected"))
        XCTAssertTrue(summary.confirmationMessage.contains("Run periodic maintenance: Mac is on battery power"))
        XCTAssertTrue(summary.confirmationMessage.contains("Clean saved application state"))
        XCTAssertTrue(summary.confirmationMessage.contains("Mode: Run local maintenance commands"))
    }

    func testOptimizeTaskConfirmationSummaryDescribesSingleCommandAndEffects() {
        let plan = OptimizePlan(task: .dockRefresh)

        let summary = OptimizeTaskConfirmationSummary(plan: plan)

        XCTAssertEqual(summary.title, "Run Refresh Dock?")
        XCTAssertEqual(summary.riskLine, "Risk: Medium")
        XCTAssertTrue(summary.confirmationMessage.contains("Command: killall Dock"))
        XCTAssertTrue(summary.confirmationMessage.contains("Restarts Dock."))
        XCTAssertTrue(summary.confirmationMessage.contains("Mode: Run local maintenance command"))
    }

    func testOptimizeSafetyPolicyExplainsWhyTasksAreSkipped() {
        let context = OptimizeSafetyContext(isOnBatteryPower: true, hasActiveVPN: true)

        let decisions = OptimizeSafetyPolicy(context: context).decisions(for: [.quickLook, .launchServices, .periodicMaintenance])

        XCTAssertNil(decisions[.quickLook]?.skipReason)
        XCTAssertTrue(decisions[.launchServices]?.skipReason?.contains("VPN") == true)
        XCTAssertTrue(decisions[.periodicMaintenance]?.skipReason?.contains("battery power") == true)
    }

    func testOptimizeSafetyContextParserDetectsConnectedVPNOnly() {
        let output = """
        Available network connection services in the current set (*=enabled):
        * (Disconnected) Office VPN
        * (Connected) WireGuard
        """

        XCTAssertTrue(OptimizeSafetyContextParser.hasActiveVPN(scutilOutput: output))
        XCTAssertFalse(OptimizeSafetyContextParser.hasActiveVPN(scutilOutput: "* (Disconnected) Office VPN"))
    }

    func testOptimizeSafetyContextParserDetectsExternalAudioDefaultOutput() {
        let externalOutput = """
        USB Audio Device:

          Default Output Device: Yes
          Manufacturer: Example
        """
        let builtInOutput = """
        MacBook Pro Speakers:

          Default Output Device: Yes
          Manufacturer: Apple Inc.
        """

        XCTAssertTrue(OptimizeSafetyContextParser.hasExternalAudio(systemProfilerAudioOutput: externalOutput))
        XCTAssertFalse(OptimizeSafetyContextParser.hasExternalAudio(systemProfilerAudioOutput: builtInOutput))
    }

    func testOptimizeSafetyContextParserDetectsConnectedBluetoothAudioAndInput() {
        let output = """
        AirPods Pro:
          Connected: Yes
          Minor Type: Headphones

        Magic Keyboard:
          Connected: Yes
          Minor Type: Keyboard

        Old Mouse:
          Connected: No
          Minor Type: Mouse
        """

        XCTAssertTrue(OptimizeSafetyContextParser.hasBluetoothAudio(systemProfilerBluetoothOutput: output))
        XCTAssertTrue(OptimizeSafetyContextParser.hasBluetoothHID(systemProfilerBluetoothOutput: output))
        XCTAssertFalse(OptimizeSafetyContextParser.hasBluetoothHID(systemProfilerBluetoothOutput: "Old Mouse:\n  Connected: No\n  Minor Type: Mouse"))
    }

    func testOptimizeSafetySummaryShowsReadyStateWhenNoContextIsActive() {
        let summary = OptimizeSafetySummary(context: OptimizeSafetyContext())

        XCTAssertEqual(summary.title, "Ready")
        XCTAssertTrue(summary.activeSignals.isEmpty)
        XCTAssertGreaterThan(summary.runnableTaskCount, 0)
        XCTAssertEqual(summary.stagedTaskCount, 1)
        XCTAssertTrue(summary.detail.contains("1 staged"))
    }

    func testOptimizeSafetySummaryNamesActiveContextAndStagedTasks() {
        let context = OptimizeSafetyContext(
            isOnBatteryPower: true,
            hasActiveVPN: true,
            hasExternalDisplay: true,
            hasExternalAudio: true,
            hasBluetoothHID: true,
            hasBluetoothAudio: true
        )

        let summary = OptimizeSafetySummary(context: context)

        XCTAssertEqual(summary.title, "Guarded")
        XCTAssertEqual(summary.activeSignals.map(\.title), [
            "Battery Power",
            "VPN",
            "External Display",
            "External Audio",
            "Bluetooth Input",
            "Bluetooth Audio"
        ])
        XCTAssertEqual(summary.runnableTaskCount, 1)
        XCTAssertEqual(summary.stagedTaskCount, 4)
        XCTAssertTrue(summary.detail.contains("4 staged"))
    }

    func testOptimizeExecutorRunsCommandsAndLogsSuccess() {
        let commands = LockedBox([[String]]())
        let executor = OptimizeExecutor { command in
            commands.withValue { $0.append([command.executablePath] + command.arguments) }
            return CommandResult(exitCode: 0, stdout: "ok", stderr: "")
        }

        let result = executor.execute(plan: OptimizePlan(task: .quickLook), at: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.task, .quickLook)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries.first?.status, .succeeded)
        XCTAssertEqual(commands.value.count, 1)
    }

    func testOptimizeExecutorStopsAfterFailure() {
        let first = OptimizeCommand(executablePath: "/bin/echo", arguments: ["first"])
        let second = OptimizeCommand(executablePath: "/bin/echo", arguments: ["second"])
        let plan = OptimizePlan(task: .dockRefresh, commands: [first, second], riskLevel: .medium, summary: "Test")
        let executed = LockedBox([OptimizeCommand]())
        let executor = OptimizeExecutor { command in
            executed.withValue { $0.append(command) }
            return CommandResult(exitCode: 9, stdout: "", stderr: "failed")
        }

        let result = executor.execute(plan: plan)

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries.first?.status, .failed)
        XCTAssertEqual(executed.value, [first])
    }

    func testOptimizeExecutorRunsBatchPlansAndStopsAfterFailedTask() {
        let first = OptimizePlan(
            task: .quickLook,
            commands: [OptimizeCommand(executablePath: "/bin/echo", arguments: ["ok"])],
            riskLevel: .low,
            summary: "First"
        )
        let second = OptimizePlan(
            task: .dockRefresh,
            commands: [OptimizeCommand(executablePath: "/bin/false", arguments: [])],
            riskLevel: .medium,
            summary: "Second"
        )
        let third = OptimizePlan(
            task: .periodicMaintenance,
            commands: [OptimizeCommand(executablePath: "/bin/echo", arguments: ["later"])],
            riskLevel: .low,
            summary: "Third"
        )
        let executed = LockedBox([OptimizeTask]())
        let executor = OptimizeExecutor { command in
            if command.executablePath == "/bin/false" {
                return CommandResult(exitCode: 1, stdout: "", stderr: "failed")
            }
            return CommandResult(exitCode: 0, stdout: "ok", stderr: "")
        }

        let results = executor.execute(batch: OptimizeBatchPlan(plans: [first, second, third], skippedTasks: [])) { task in
            executed.withValue { $0.append(task) }
        }

        XCTAssertEqual(results.map(\.task), [.quickLook, .dockRefresh])
        XCTAssertEqual(results.map(\.status), [.succeeded, .failed])
        XCTAssertEqual(executed.value, [.quickLook, .dockRefresh])
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private var storage: Value
    private let lock = NSLock()

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func withValue(_ body: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&storage)
    }
}
