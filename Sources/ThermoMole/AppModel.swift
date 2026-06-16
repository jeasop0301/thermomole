import Foundation
import Combine
import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers
import ThermoMoleCore
import ThermoMoleNative
import ThermoMoleAppCore

@MainActor
final class AppModel: ObservableObject {
    @Published var snapshot: SystemSnapshot = .placeholder
    @Published var menuBarMetrics: [MenuBarMetric] = MenuBarMetric.defaultMetrics {
        didSet {
            UserDefaults.standard.set(MenuBarMetricStorage.encode(menuBarMetrics), forKey: "menuBarMetrics")
        }
    }
    @Published var diskEntries = [DiskEntry]()
    @Published var diskTrashLog = [DiskEntryTrashResult]()
    @Published var diskAnalysisPath = DiskAnalysisPath(rootURL: FileManager.default.homeDirectoryForCurrentUser)
    @Published var installedApps = [InstalledApp]()
    @Published var startupItems = [StartupItem]()
    @Published var appUninstallLog = [AppUninstallResult]()
    @Published var statusHistory = BoundedStatusHistory(limit: 30)
    @Published var analyzeState = OperationState.idle
    @Published var softwareState = OperationState.idle
    @Published var optimizeState = OperationState.idle
    @Published var optimizeLog = [OptimizeExecutionResult]()
    @Published var optimizeSafetyContext = OptimizeSafetyContext()
    @Published var memoryPurgeState = OperationState.idle
    @Published var memoryPurgeLog = [MemoryPurgeResult]()
    @Published var operationHistoryEntries = [OperationHistoryEntry]()
    @Published var operationHistoryError: String?
    @Published var diagnosticExportState = OperationState.idle
    @Published var diagnosticImportState = OperationState.idle
    @Published var importedDiagnosticSummary: DiagnosticReportSummary?
    @Published var showsDockIcon = false
    @Published var launchAtLoginEnabled = false
    @Published var launchAtLoginStatusText = "Off"
    @Published var lastError: String?
    @Published var doctorReport = DoctorReport.make(inputs: .placeholder)
    @Published var todayExposure = ThermalExposureSummary.empty
    @Published var todayChargeExposure = ChargeExposureSummary.empty
    @Published var batteryHealthSeries: [Double] = []
    @Published var latestBatteryHealth: DailyBatteryHealth?

    private let provider = NativeSensorProvider()
    private let historyStore = OperationHistoryStore.live
    private let statusSnapshotStore = StatusSnapshotStore.live
    private let exposureCoordinator = ThermalExposureCoordinator()
    private let chargeCoordinator = ChargeExposureCoordinator()
    private let batteryHealthStore = BatteryHealthStore()
    private var batteryHealthLog = BatteryHealthLog()
    private var lastSavedHealthRecord: BatteryHealthRecord?
    private var timer: Timer?
    private var doctorFreshnessTimer: Timer?
    private var samplingGate = SamplingGate(timeout: 8)
    private var analyzeTask: Task<[DiskEntry], Never>?
    private var analyzeRequestID = UUID()

    private(set) lazy var clean = CleanModel(
        scan: { CleanupScanner().scan(preselection: $0) },
        execute: { items, selection in CleanupExecutor().execute(items: items, selection: selection, mode: .trash) },
        logOperation: { [weak self] entry in self?.appendHistory(entry) },
        onCleaned: { [weak self] in self?.refreshDoctorReport() }
    )

    init() {
        let stored = UserDefaults.standard.stringArray(forKey: "menuBarMetrics") ?? []
        let decoded = MenuBarMetricStorage.decode(stored)
        menuBarMetrics = decoded
        if MenuBarMetricStorage.needsRewrite(rawValues: stored, normalizedMetrics: decoded) {
            UserDefaults.standard.set(MenuBarMetricStorage.encode(decoded), forKey: "menuBarMetrics")
        }
        if let lastSnapshot = try? statusSnapshotStore.load() {
            snapshot = lastSnapshot
            statusHistory.append(lastSnapshot)
        }
        if let healthRecord = try? batteryHealthStore.load() {
            var seeded: [String: DailyBatteryHealth] = [:]
            for day in healthRecord.days { seeded[day.day] = day }
            batteryHealthLog = BatteryHealthLog(days: seeded)
            lastSavedHealthRecord = healthRecord.pruned()
            batteryHealthSeries = batteryHealthLog.healthSeries()
            latestBatteryHealth = batteryHealthLog.latest
        }
        Task {
            await exposureCoordinator.bootstrap()
            await chargeCoordinator.bootstrap()
            todayExposure = await exposureCoordinator.summary(at: Date(), calendar: .current)
            todayChargeExposure = await chargeCoordinator.summary(at: Date(), calendar: .current)
        }
        showsDockIcon = UserDefaults.standard.bool(forKey: "showsDockIcon")
        loadOperationHistory()
        refreshLaunchAtLoginStatus()
        refreshDoctorReport()
    }

    func start() {
        refresh()
        startDoctorFreshnessTimer()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func startDoctorFreshnessTimer() {
        doctorFreshnessTimer?.invalidate()
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshDoctorReport() }
        }
        RunLoop.main.add(timer, forMode: .common)
        doctorFreshnessTimer = timer
    }

    func refresh() {
        guard samplingGate.begin() else { return }
        guard let sampleStartedAt = samplingGate.startedAt else { return }
        Task {
            let next = await provider.sample()
            snapshot = next
            statusHistory.append(next)
            Task.detached { [statusSnapshotStore] in try? statusSnapshotStore.save(next) }
            await exposureCoordinator.record(
                temperatureC: next.thermal.batteryDisplayC,
                at: next.sampledAt,
                calendar: .current
            )
            todayExposure = await exposureCoordinator.summary(at: next.sampledAt, calendar: .current)
            await chargeCoordinator.record(
                percent: next.battery.percent,
                isOnACPower: next.battery.isOnACPower,
                at: next.sampledAt,
                calendar: .current
            )
            todayChargeExposure = await chargeCoordinator.summary(at: next.sampledAt, calendar: .current)
            recordBatteryHealth(from: next)
            refreshDoctorReport()
            samplingGate.finish(startedAt: sampleStartedAt)
        }
    }

    private func recordBatteryHealth(from snapshot: SystemSnapshot) {
        batteryHealthLog.record(
            healthPercent: snapshot.battery.healthPercent,
            cycleCount: snapshot.battery.cycleCount,
            maxCapacityMAh: snapshot.battery.maxCapacityMAh,
            designCapacityMAh: snapshot.battery.designCapacityMAh,
            at: snapshot.sampledAt,
            calendar: .current
        )
        batteryHealthSeries = batteryHealthLog.healthSeries()
        latestBatteryHealth = batteryHealthLog.latest
        let record = BatteryHealthRecord(days: batteryHealthLog.all()).pruned()
        if record != lastSavedHealthRecord {
            lastSavedHealthRecord = record
            Task.detached { [batteryHealthStore] in try? batteryHealthStore.save(record) }
        }
    }

    nonisolated func flushExposureForTermination() async {
        await exposureCoordinator.flushNow(at: Date())
        await chargeCoordinator.flushNow(at: Date())
    }

    func analyzeHome() {
        guard !analyzeState.isRunning else { return }
        diskAnalysisPath.reset(to: FileManager.default.homeDirectoryForCurrentUser)
        analyzeCurrentDiskURL(message: "Analyzing home folder")
    }

    func analyzeFolder(_ url: URL) {
        guard !analyzeState.isRunning else { return }
        diskAnalysisPath.reset(to: url)
        analyzeCurrentDiskURL(message: "Analyzing \(url.lastPathComponent)")
    }

    func analyzeDiskEntry(_ entry: DiskEntry) {
        guard entry.isDirectory, !analyzeState.isRunning else { return }
        diskAnalysisPath.push(entry.url)
        analyzeCurrentDiskURL(message: "Analyzing \(entry.url.lastPathComponent)")
    }

    func analyzeDiskBreadcrumb(_ breadcrumb: DiskBreadcrumb) {
        guard !analyzeState.isRunning else { return }
        diskAnalysisPath.popTo(breadcrumb.url)
        analyzeCurrentDiskURL(message: "Analyzing \(breadcrumb.title)")
    }

    func analyzeParentDiskURL() {
        guard diskAnalysisPath.canGoUp, !analyzeState.isRunning else { return }
        diskAnalysisPath.popUp()
        analyzeCurrentDiskURL(message: "Analyzing \(diskAnalysisPath.currentURL.lastPathComponent)")
    }

    func cancelAnalyze() {
        guard analyzeState.isRunning else { return }
        analyzeTask?.cancel()
        analyzeTask = nil
        analyzeRequestID = UUID()
        analyzeState = analyzeState.finished(message: "Canceled", at: Date())
    }

    func canTrashDiskEntry(_ entry: DiskEntry) -> Bool {
        let resolvedURL = entry.url.resolvingSymlinksInPath().standardizedFileURL
        return ProtectedPathValidator().canDelete(entry.url, resolvedURL: resolvedURL)
    }

    func trashDiskEntry(_ entry: DiskEntry) {
        guard !analyzeState.isRunning else { return }
        analyzeState = analyzeState.started(message: "Moving \(entry.url.lastPathComponent) to Trash")
        Task.detached(priority: .utility) {
            DiskEntryTrashExecutor().moveToTrash(entry)
        }.receive(on: MainActor.self) { [weak self] result in
            guard let self else { return }
            diskTrashLog = [result] + diskTrashLog
            appendHistory(OperationHistoryEntry.analyzeTrash(result))
            if result.status == .succeeded {
                diskEntries.removeAll { $0.id == result.entry.id }
                refreshDoctorReport()
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
        let task = Task.detached(priority: .utility) {
            DiskAnalyzer().analyze(url, shouldCancel: { Task.isCancelled })
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

    func loadSoftware() {
        guard !softwareState.isRunning else { return }
        softwareState = softwareState.started(message: "Loading applications")
        Task.detached(priority: .utility) {
            let inventory = SoftwareInventory()
            return (inventory.installedApps(), inventory.startupItems())
        }.receive(on: MainActor.self) { [weak self] apps, startupItems in
            self?.installedApps = apps
            self?.startupItems = startupItems
            self?.softwareState = self?.softwareState.finished(
                message: "\(apps.count) apps · \(startupItems.count) startup items",
                at: Date()
            ) ?? .idle
        }
    }

    func uninstallApp(_ app: InstalledApp) {
        guard !softwareState.isRunning else { return }
        softwareState = softwareState.started(message: "Moving \(app.name) to Trash")
        Task.detached(priority: .utility) {
            AppUninstallExecutor().moveToTrash(app)
        }.receive(on: MainActor.self) { [weak self] result in
            guard let self else { return }
            appUninstallLog = [result] + appUninstallLog
            appendHistory(OperationHistoryEntry.uninstall(result))
            refreshDoctorReport()
            if result.status == .succeeded {
                installedApps.removeAll { $0.id == result.app.id }
                softwareState = softwareState.finished(message: "\(result.app.name) moved to Trash", at: Date())
            } else {
                softwareState = softwareState.failed(message: "\(result.app.name) uninstall failed", at: Date())
            }
        }
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
            appendHistory(OperationHistoryEntry.optimize(
                title: result.task.title,
                results: [result],
                skippedCount: 0
            ))
            refreshDoctorReport()
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
            appendHistory(OperationHistoryEntry.optimize(
                title: "Default Optimize",
                results: results,
                skippedCount: batch.skippedTasks.count
            ))
            refreshDoctorReport()
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
        optimizeSafetyContext = makeOptimizeSafetyContext()
    }

    func runMemoryPurge() {
        guard !memoryPurgeState.isRunning else { return }
        let report = MemoryDoctorReport(memory: snapshot.memory, topProcesses: snapshot.topProcesses)
        let plan = MemoryPurgePlan(report: report)
        guard plan.canExecute else {
            memoryPurgeState = memoryPurgeState.failed(message: "Requires critical memory pressure", at: Date())
            return
        }

        memoryPurgeState = memoryPurgeState.started(message: "Running advanced purge")
        Task.detached(priority: .utility) {
            MemoryPurgeExecutor().execute(plan: plan)
        }.receive(on: MainActor.self) { [weak self] result in
            guard let self else { return }
            memoryPurgeLog = [result] + memoryPurgeLog
            appendHistory(OperationHistoryEntry.memoryPurge(result))
            refreshDoctorReport()
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

    func setMenuBarMetric(_ metric: MenuBarMetric, enabled: Bool) {
        if enabled {
            if !menuBarMetrics.contains(metric) {
                menuBarMetrics = MenuBarMetric.sanitized(menuBarMetrics + [metric])
            }
        } else {
            menuBarMetrics = MenuBarMetric.sanitized(menuBarMetrics.filter { $0 != metric })
        }
    }

    func moveMenuBarMetric(_ metric: MenuBarMetric, direction: MenuBarMetricMoveDirection) {
        menuBarMetrics = MenuBarMetric.move(metric, in: menuBarMetrics, direction: direction)
    }

    func setDockIconVisible(_ visible: Bool) {
        showsDockIcon = visible
        UserDefaults.standard.set(visible, forKey: "showsDockIcon")
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
        if visible {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = "Launch at Login: \(error.localizedDescription)"
        }
        refreshLaunchAtLoginStatus()
    }

    func refreshLaunchAtLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLoginEnabled = status == .enabled
        launchAtLoginStatusText = switch status {
        case .enabled: "On"
        case .notRegistered: "Off"
        case .notFound: "Install to /Applications"
        case .requiresApproval: "Needs Approval"
        @unknown default: "Unknown"
        }
    }

    func refreshDoctorReport(now: Date = Date()) {
        doctorReport = DoctorReport.make(inputs: DoctorInputs.make(
            snapshot: snapshot,
            hasFullDiskAccess: hasLikelyFullDiskAccess(),
            operationLogWritable: isOperationLogWritable(),
            recentOperationFailures: recentOperationFailureCount(),
            now: now
        ))
    }

    func loadOperationHistory() {
        do {
            operationHistoryEntries = try historyStore.readRecent(limit: 20)
            operationHistoryError = nil
        } catch {
            operationHistoryEntries = []
            operationHistoryError = error.localizedDescription
        }
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    func revealOperationHistoryLog() {
        let url = historyStore.logURL
        if FileManager.default.fileExists(atPath: url.path) {
            revealInFinder(url)
        } else {
            revealInFinder(url.deletingLastPathComponent())
        }
    }

    func exportDiagnosticReport(to url: URL) {
        let report = DiagnosticReport(
            appVersion: appVersionString(),
            snapshot: snapshot,
            doctorReport: doctorReport,
            recentOperations: operationHistoryEntries
        )
        do {
            try DiagnosticReportStore().write(report, to: url)
            diagnosticExportState = diagnosticExportState.finished(
                message: "Diagnostic report exported",
                at: Date()
            )
            lastError = nil
        } catch {
            diagnosticExportState = diagnosticExportState.failed(
                message: "Diagnostic export failed",
                at: Date()
            )
            lastError = "Diagnostic report: \(error.localizedDescription)"
        }
    }

    func importDiagnosticReport(from url: URL) {
        do {
            let report = try DiagnosticReportStore().read(from: url)
            importedDiagnosticSummary = DiagnosticReportSummary(report: report)
            diagnosticImportState = diagnosticImportState.finished(
                message: "Diagnostic report imported",
                at: Date()
            )
            lastError = nil
        } catch {
            importedDiagnosticSummary = nil
            diagnosticImportState = diagnosticImportState.failed(
                message: "Diagnostic import failed",
                at: Date()
            )
            lastError = "Diagnostic report: \(error.localizedDescription)"
        }
    }

    private func recentOperationFailureCount() -> Int {
        operationHistoryEntries.filter { $0.status == .failed }.count
    }

    private func makeOptimizeSafetyContext() -> OptimizeSafetyContext {
        let bluetooth = bluetoothSafetyFlags()
        return OptimizeSafetyContext(
            isOnBatteryPower: snapshot.battery.percent > 0 && !snapshot.battery.isOnACPower,
            hasActiveVPN: hasActiveVPNConnection(),
            hasExternalDisplay: NSScreen.screens.count > 1,
            hasExternalAudio: hasExternalAudioDevice(),
            hasBluetoothHID: bluetooth.hid,
            hasBluetoothAudio: bluetooth.audio
        )
    }

    private func hasActiveVPNConnection() -> Bool {
        let result = Shell.run("/usr/sbin/scutil", ["--nc", "list"], timeoutSeconds: 1)
        guard result.status == 0 else { return false }
        return OptimizeSafetyContextParser.hasActiveVPN(scutilOutput: result.stdout)
    }

    private func hasExternalAudioDevice() -> Bool {
        let result = Shell.run("/usr/sbin/system_profiler", ["SPAudioDataType"], timeoutSeconds: 2)
        guard result.status == 0 else { return false }
        return OptimizeSafetyContextParser.hasExternalAudio(systemProfilerAudioOutput: result.stdout)
    }

    private func bluetoothSafetyFlags() -> (hid: Bool, audio: Bool) {
        let result = Shell.run("/usr/sbin/system_profiler", ["SPBluetoothDataType"], timeoutSeconds: 2)
        guard result.status == 0 else { return (hid: false, audio: false) }
        return (
            hid: OptimizeSafetyContextParser.hasBluetoothHID(systemProfilerBluetoothOutput: result.stdout),
            audio: OptimizeSafetyContextParser.hasBluetoothAudio(systemProfilerBluetoothOutput: result.stdout)
        )
    }

    private func appendHistory(_ entry: OperationHistoryEntry) {
        do {
            try historyStore.append(entry)
            operationHistoryError = nil
        } catch {
            operationHistoryError = error.localizedDescription
        }
        loadOperationHistory()
    }

    private func isOperationLogWritable() -> Bool {
        let logsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
        return FileManager.default.isWritableFile(atPath: logsURL.path)
    }

    private func hasLikelyFullDiskAccess() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let protectedPaths = [
            home.appendingPathComponent("Library/Messages/chat.db"),
            home.appendingPathComponent("Library/Safari/History.db"),
            home.appendingPathComponent("Library/Mail"),
            URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db")
        ]

        return protectedPaths.contains { url in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
            if isDirectory.boolValue {
                return (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
            }
            return FileHandle(forReadingAtPath: url.path) != nil
        }
    }

    private func appVersionString() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let joined = [version, build]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return joined.isEmpty ? "debug" : joined
    }
}
