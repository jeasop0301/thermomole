import XCTest
@testable import ThermoMoleCore

final class MemoryDoctorTests: XCTestCase {
    func testMemoryDoctorKeepsCleanupDisabledWhenPressureIsNormal() {
        let memory = MemorySnapshot(
            usedBytes: 8_000,
            totalBytes: 16_000,
            usedPercent: 50,
            pressure: .normal,
            activeBytes: 4_000,
            wiredBytes: 2_000,
            compressedBytes: 2_000,
            freeBytes: 8_000
        )
        let report = MemoryDoctorReport(memory: memory, topProcesses: [])

        XCTAssertEqual(report.level, .calm)
        XCTAssertEqual(report.primaryAction, .none)
        XCTAssertFalse(report.allowsPurge)
        XCTAssertTrue(report.summary.localizedCaseInsensitiveContains("no cleanup needed"))
    }

    func testMemoryDoctorRecommendsReviewingTopProcessesWhenPressureIsWarning() {
        let memory = MemorySnapshot(
            usedBytes: 13_000,
            totalBytes: 16_000,
            usedPercent: 81,
            pressure: .warning,
            activeBytes: 7_000,
            wiredBytes: 3_000,
            compressedBytes: 3_000,
            freeBytes: 3_000
        )
        let process = ProcessSnapshot(pid: 42, name: "Xcode", cpuPercent: 5, memoryBytes: 4_000)
        let report = MemoryDoctorReport(memory: memory, topProcesses: [process])

        XCTAssertEqual(report.level, .watch)
        XCTAssertEqual(report.primaryAction, .reviewProcesses)
        XCTAssertFalse(report.allowsPurge)
        XCTAssertEqual(report.topMemoryProcess?.name, "Xcode")
        XCTAssertTrue(report.summary.localizedCaseInsensitiveContains("review"))
    }

    func testMemoryDoctorAllowsAdvancedPurgeOnlyAtCriticalPressure() {
        let memory = MemorySnapshot(
            usedBytes: 15_000,
            totalBytes: 16_000,
            usedPercent: 94,
            pressure: .critical,
            activeBytes: 8_000,
            wiredBytes: 4_000,
            compressedBytes: 3_000,
            freeBytes: 1_000
        )
        let report = MemoryDoctorReport(memory: memory, topProcesses: [])

        XCTAssertEqual(report.level, .critical)
        XCTAssertEqual(report.primaryAction, .reviewProcesses)
        XCTAssertTrue(report.allowsPurge)
        XCTAssertTrue(report.summary.localizedCaseInsensitiveContains("critical"))
    }

    func testTerminalFormatterRendersMemoryDoctorReport() {
        let memory = MemorySnapshot(
            usedBytes: 13_000,
            totalBytes: 16_000,
            usedPercent: 81,
            pressure: .warning,
            activeBytes: 7_000,
            wiredBytes: 3_000,
            compressedBytes: 3_000,
            freeBytes: 3_000
        )
        let report = MemoryDoctorReport(
            memory: memory,
            topProcesses: [ProcessSnapshot(pid: 42, name: "Xcode", cpuPercent: 5, memoryBytes: 4_000)]
        )
        let output = TerminalOutputFormatter.memoryDoctor(report)

        XCTAssertTrue(output.contains("Memory Doctor"))
        XCTAssertTrue(output.contains("Warning"))
        XCTAssertTrue(output.contains("Xcode"))
        XCTAssertFalse(output.localizedCaseInsensitiveContains("free ram"))
    }

    func testMemoryPurgePlanOnlyAllowsExecutionAtCriticalPressure() {
        let normal = MemoryDoctorReport(
            memory: memory(pressure: .normal, usedPercent: 50),
            topProcesses: []
        )
        let critical = MemoryDoctorReport(
            memory: memory(pressure: .critical, usedPercent: 94),
            topProcesses: []
        )

        let disabledPlan = MemoryPurgePlan(report: normal)
        XCTAssertFalse(disabledPlan.canExecute)
        XCTAssertTrue(disabledPlan.commands.isEmpty)
        XCTAssertTrue(disabledPlan.summary.localizedCaseInsensitiveContains("disabled"))

        let criticalPlan = MemoryPurgePlan(report: critical)
        XCTAssertTrue(criticalPlan.canExecute)
        XCTAssertEqual(criticalPlan.commands, [OptimizeCommand(executablePath: "/usr/bin/purge", arguments: [])])
        XCTAssertTrue(criticalPlan.confirmationMessage.localizedCaseInsensitiveContains("temporary"))
    }

    func testMemoryPurgeExecutorSkipsWhenPlanIsDisabled() {
        let plan = MemoryPurgePlan(report: MemoryDoctorReport(
            memory: memory(pressure: .warning, usedPercent: 82),
            topProcesses: []
        ))
        let ran = MemoryTestLockedBox(false)
        let executor = MemoryPurgeExecutor { _ in
            ran.withValue { $0 = true }
            return CommandResult(exitCode: 0, stdout: "ok", stderr: "")
        }

        let result = executor.execute(plan: plan)

        XCTAssertEqual(result.status, .skipped)
        XCTAssertFalse(ran.value)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("critical"))
    }

    func testMemoryPurgeExecutorRunsPurgeWhenPlanIsEnabled() {
        let plan = MemoryPurgePlan(report: MemoryDoctorReport(
            memory: memory(pressure: .critical, usedPercent: 96),
            topProcesses: []
        ))
        let commands = MemoryTestLockedBox([OptimizeCommand]())
        let executor = MemoryPurgeExecutor { command in
            commands.withValue { $0.append(command) }
            return CommandResult(exitCode: 0, stdout: "purged", stderr: "")
        }

        let result = executor.execute(plan: plan, at: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(commands.value, [OptimizeCommand(executablePath: "/usr/bin/purge", arguments: [])])
        XCTAssertEqual(result.executedAt, Date(timeIntervalSince1970: 1))
    }

    private func memory(pressure: MemoryPressure, usedPercent: Int) -> MemorySnapshot {
        MemorySnapshot(
            usedBytes: UInt64(usedPercent) * 1_000,
            totalBytes: 100_000,
            usedPercent: usedPercent,
            pressure: pressure,
            activeBytes: 40_000,
            wiredBytes: 20_000,
            compressedBytes: 10_000,
            freeBytes: 30_000
        )
    }
}

private final class MemoryTestLockedBox<Value>: @unchecked Sendable {
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
