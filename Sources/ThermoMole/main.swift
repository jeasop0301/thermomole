import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI
import ThermoMoleCore
import ThermoMoleNative
import UniformTypeIdentifiers

@main
enum ThermoMoleMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        let showsDockIcon = UserDefaults.standard.bool(forKey: "showsDockIcon")
        app.setActivationPolicy(showsDockIcon ? .regular : .accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var mainWindow: NSWindow?
    private var freshnessTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()

        Publishers.CombineLatest(model.$snapshot, model.$menuBarMetrics)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot, metrics in
                self?.updateMenuBar(snapshot, metrics: metrics)
            }
            .store(in: &cancellables)

        model.start()
        startMenuBarFreshnessTimer()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.title = "CPU --° · BAT --° · RAM --%"
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "ThermoMole"
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 360, height: 520)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(model: model) { [weak self] in
                self?.showMainWindow()
            }
        )
    }

    @objc private func statusItemClicked() {
        guard let button = statusItem?.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open ThermoMole", action: #selector(openMainWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit ThermoMole", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openMainWindow() {
        showMainWindow()
    }

    @objc private func refreshNow() {
        model.refresh()
        updateMenuBar(model.snapshot, metrics: model.menuBarMetrics)
    }

    private func startMenuBarFreshnessTimer() {
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.updateMenuBar(self.model.snapshot, metrics: self.model.menuBarMetrics)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        freshnessTimer = timer
    }

    private func showMainWindow() {
        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "ThermoMole"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: MainWindowView(model: model)
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow = window
    }

    private func updateMenuBar(_ snapshot: SystemSnapshot, metrics: [MenuBarMetric]) {
        guard let button = statusItem?.button else { return }
        let condition = systemCondition(for: snapshot)
        let presentation = MenuBarPresentation(snapshot: snapshot, metrics: metrics)
        let color = presentation.freshnessLevel == .stale ? NSColor.systemRed : nsColor(for: condition)

        let attributed = NSMutableAttributedString(string: presentation.visibleTitle)
        attributed.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: 1))
        button.attributedTitle = attributed
        button.toolTip = presentation.toolTip
        button.setAccessibilityLabel(presentation.accessibilityLabel)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var snapshot: SystemSnapshot = .placeholder
    @Published var menuBarMetrics: [MenuBarMetric] = MenuBarMetric.defaultMetrics {
        didSet {
            UserDefaults.standard.set(MenuBarMetricStorage.encode(menuBarMetrics), forKey: "menuBarMetrics")
        }
    }
    @Published var cleanupResult = CleanupScanResult(items: [], skipped: [])
    @Published var cleanupSelection = CleanupReviewSelection(items: [])
    @Published var smartCleanupPlan: SmartCleanupReviewPlan?
    @Published var cleanupLog = [CleanupOperationLogEntry]()
    @Published var diskEntries = [DiskEntry]()
    @Published var diskTrashLog = [DiskEntryTrashResult]()
    @Published var diskAnalysisPath = DiskAnalysisPath(rootURL: FileManager.default.homeDirectoryForCurrentUser)
    @Published var installedApps = [InstalledApp]()
    @Published var startupItems = [StartupItem]()
    @Published var appUninstallLog = [AppUninstallResult]()
    @Published var statusHistory = BoundedStatusHistory(limit: 30)
    @Published var cleanupState = OperationState.idle
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

    private let provider = NativeSensorProvider()
    private let historyStore = OperationHistoryStore.live
    private let statusSnapshotStore = StatusSnapshotStore.live
    private var timer: Timer?
    private var doctorFreshnessTimer: Timer?
    private var samplingGate = SamplingGate(timeout: 8)
    private var analyzeTask: Task<[DiskEntry], Never>?
    private var analyzeRequestID = UUID()

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
            try? statusSnapshotStore.save(next)
            refreshDoctorReport()
            samplingGate.finish(startedAt: sampleStartedAt)
        }
    }

    func scanCleanup() {
        guard !cleanupState.isRunning else { return }
        smartCleanupPlan = nil
        cleanupState = cleanupState.started(message: "Scanning review items")
        Task.detached(priority: .utility) {
            let scanner = CleanupScanner()
            return scanner.scan()
        }.receive(on: MainActor.self) { [weak self] result in
            self?.cleanupResult = result
            self?.cleanupSelection = CleanupReviewSelection(items: result.items)
            let summary = CleanupReviewSummary(result)
            self?.cleanupState = self?.cleanupState.finished(
                message: "\(summary.itemCount) items · \(formatBytes(summary.totalBytes))",
                at: Date()
            ) ?? .idle
        }
    }

    func prepareSmartCleanup() {
        guard !cleanupState.isRunning else { return }
        smartCleanupPlan = nil
        cleanupState = cleanupState.started(message: "Finding safe cleanup")
        Task.detached(priority: .utility) {
            let scanner = CleanupScanner()
            return scanner.scan(preselection: .recommended)
        }.receive(on: MainActor.self) { [weak self] result in
            guard let self else { return }
            cleanupResult = result
            cleanupSelection = CleanupReviewSelection(items: result.items)
            let plan = SmartCleanupReviewPlan(result)
            if plan.hasSelection {
                smartCleanupPlan = plan
                cleanupState = cleanupState.finished(
                    message: "\(plan.selectedItemCount) ready · \(formatBytes(plan.selectedBytes))",
                    at: Date()
                )
            } else {
                cleanupState = cleanupState.finished(message: "Nothing safe to clean", at: Date())
            }
        }
    }

    func setCleanupItem(_ item: CleanupItem, selected: Bool) {
        cleanupSelection.setSelected(item, isSelected: selected)
    }

    func setCleanupItems(_ items: [CleanupItem], selected: Bool) {
        cleanupSelection.setSelected(items, isSelected: selected)
    }

    func selectedCleanupBytes() -> UInt64 {
        cleanupSelection.selectedBytes(in: cleanupResult.items)
    }

    func executeSelectedCleanup() {
        guard !cleanupState.isRunning, !cleanupSelection.selectedIDs.isEmpty else { return }
        smartCleanupPlan = nil
        cleanupState = cleanupState.started(message: "Moving selected items to Trash")
        let items = cleanupResult.items
        let selection = cleanupSelection
        Task.detached(priority: .utility) {
            let executor = CleanupExecutor()
            return executor.execute(items: items, selection: selection, mode: .trash)
        }.receive(on: MainActor.self) { [weak self] result in
            guard let self else { return }
            cleanupLog = result.entries + cleanupLog
            appendHistory(OperationHistoryEntry.cleanup(
                kind: .clean,
                title: "Clean Selected",
                result: result
            ))
            let succeededIDs = Set(result.entries.filter { $0.status == .succeeded }.map(\.item.id))
            let remainingItems = cleanupResult.items.filter { !succeededIDs.contains($0.id) }
            cleanupResult = CleanupScanResult(items: remainingItems, skipped: cleanupResult.skipped)
            cleanupSelection = CleanupReviewSelection(items: remainingItems)
            refreshDoctorReport()
            cleanupState = cleanupState.finished(
                message: "\(result.succeededCount) moved · \(formatBytes(result.reclaimedBytes))",
                at: Date()
            )
        }
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

private extension Task where Success: Sendable, Failure == Never {
    func receive(on actor: MainActor.Type, _ body: @escaping @MainActor (Success) -> Void) {
        Task<Void, Never> {
            let value = await self.value
            await MainActor.run {
                body(value)
            }
        }
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case status
    case clean
    case software
    case optimize
    case analyze
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: "Status"
        case .clean: "Clean"
        case .software: "Software"
        case .optimize: "Optimize"
        case .analyze: "Analyze"
        case .settings: "Settings"
        }
    }

    var subtitle: String {
        switch self {
        case .status: "Battery heat, CPU warmth"
        case .clean: "Safe clutter review"
        case .software: "Apps and quiet starters"
        case .optimize: "Small repairs, staged"
        case .analyze: "Follow storage inward"
        case .settings: "Local choices"
        }
    }

    var symbol: String {
        switch self {
        case .status: "gauge.with.dots.needle.67percent"
        case .clean: "sparkles"
        case .software: "shippingbox"
        case .optimize: "wand.and.stars"
        case .analyze: "chart.pie"
        case .settings: "gearshape"
        }
    }
}

struct MainWindowView: View {
    @ObservedObject var model: AppModel
    @State private var selection: AppSection = .status

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(Color.subtleStroke)
                .frame(width: 1)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
        }
        .frame(minWidth: 1040, minHeight: 680)
        .background(Color.appBackground)
        .tint(Color.thermoAccent)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.thermoAccent)
                    .frame(width: 34, height: 34)
                    .background(Color.iconBadgeFill)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("ThermoMole")
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                    Text("Local Mac monitor")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)

            VStack(spacing: 4) {
                ForEach(AppSection.allCases) { section in
                    Button {
                        selection = section
                    } label: {
                        SidebarRow(section: section, isSelected: selection == section)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                Text("Real Battery Pack")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(batterySourceLabel(model.snapshot.thermal.batteryTemperatureSource))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(formatTemperaturePrecise(model.snapshot.thermal.batteryDisplayC))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(batteryColor(model.snapshot.thermal.batteryWarningLevel))
                    .monospacedDigit()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .softPanel()
        }
        .padding(14)
        .frame(width: 244)
        .background(Color.appSidebar)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .status:
            StatusTab(model: model)
        case .clean:
            CleanTab(model: model)
        case .software:
            SoftwareTab(model: model)
        case .optimize:
            OptimizeTab(model: model)
        case .analyze:
            AnalyzeTab(model: model)
        case .settings:
            SettingsTab(model: model)
        }
    }
}

struct SidebarRow: View {
    var section: AppSection
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: section.symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 22)
                .foregroundStyle(isSelected ? Color.thermoAccent : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(section.title)
                    .font(.callout.weight(.semibold))
                Text(section.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(isSelected ? Color.selectionFill : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.thermoAccent.opacity(0.22) : Color.clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(section.title), \(section.subtitle)"))
        .accessibilityHint(Text(isSelected ? "Current section" : "Open section"))
    }
}

struct MenuBarPopoverView: View {
    @ObservedObject var model: AppModel
    var openMain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PopoverHeader(snapshot: model.snapshot)

            PopoverMetricStack(snapshot: model.snapshot)

            CompactProcessList(processes: Array(model.snapshot.topProcesses.prefix(5)))

            Divider()
            HStack {
                Button {
                    model.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Spacer()
                Button("Open ThermoMole", action: openMain)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 370)
        .background(Color.appBackground)
        .tint(Color.thermoAccent)
    }
}

struct PopoverHeader: View {
    var snapshot: SystemSnapshot

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(healthColor(snapshot.health.band).opacity(0.18))
                Text("\(snapshot.health.value)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(healthColor(snapshot.health.band))
            }
            .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text("ThermoMole")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                Text("Quietly watching \(snapshot.modelIdentifier)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                FreshnessChip(sampledAt: snapshot.sampledAt, isCompact: true)
                Label(conditionTitle(systemCondition(for: snapshot)), systemImage: conditionSymbol(systemCondition(for: snapshot)))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(conditionColor(systemCondition(for: snapshot)))
            }
            Spacer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("ThermoMole health score \(snapshot.health.value), \(conditionTitle(systemCondition(for: snapshot)))"))
        .accessibilityValue(Text(StatusFreshness(sampledAt: snapshot.sampledAt).accessibilityLabel))
    }
}

struct FreshnessChip: View {
    var sampledAt: Date
    var isCompact = false

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            let freshness = StatusFreshness(sampledAt: sampledAt, now: context.date)
            Label {
                Text("\(freshness.title) · \(freshness.detail)")
            } icon: {
                Image(systemName: freshnessSymbol(freshness.level))
            }
            .font((isCompact ? Font.caption2 : Font.caption).weight(.semibold))
            .foregroundStyle(freshnessColor(freshness.level))
            .padding(.horizontal, isCompact ? 7 : 9)
            .padding(.vertical, isCompact ? 3 : 5)
            .background(freshnessColor(freshness.level).opacity(0.12))
            .clipShape(Capsule())
            .accessibilityLabel(Text(freshness.accessibilityLabel))
        }
    }
}

struct PopoverMetricStack: View {
    var snapshot: SystemSnapshot

    var body: some View {
        VStack(spacing: 0) {
            PopoverMetricRow(
                title: "CPU",
                value: formatTemperature(snapshot.thermal.cpuDisplayC),
                detail: cpuSourceLabel(snapshot.thermal.cpuTemperatureSource),
                tint: .orange
            )
            Divider().padding(.leading, 40)
            PopoverMetricRow(
                title: "Battery",
                value: formatTemperature(snapshot.thermal.batteryDisplayC),
                detail: batterySourceLabel(snapshot.thermal.batteryTemperatureSource),
                tint: batteryColor(snapshot.thermal.batteryWarningLevel)
            )
            Divider().padding(.leading, 40)
            PopoverMetricRow(
                title: "Memory",
                value: "\(snapshot.memory.usedPercent)%",
                detail: snapshot.memory.pressure.rawValue.capitalized,
                tint: Color.oceanAccent
            )
            Divider().padding(.leading, 40)
            PopoverMetricRow(
                title: "Load",
                value: "\(Int(snapshot.cpu.usagePercent.rounded()))%",
                detail: formatLoad(snapshot.cpu.loadAverage),
                tint: Color.plumAccent
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .softPanel()
    }
}

struct PopoverMetricRow: View {
    var title: String
    var value: String
    var detail: String
    var tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(value)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(value), \(detail)"))
    }
}

struct CompactProcessList: View {
    var processes: [ProcessSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Processes")
                .font(.headline)
            ForEach(processes) { process in
                HStack {
                    Text(process.name)
                        .lineLimit(1)
                    Spacer()
                Text("\(process.cpuPercent, specifier: "%.1f")%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(process.name))
            .accessibilityValue(Text("CPU \(process.cpuPercent, specifier: "%.1f") percent"))
        }
    }
        .padding(12)
        .softPanel()
    }
}

struct StatusTab: View {
    @ObservedObject var model: AppModel
    @State private var isShowingMemoryPurgeConfirmation = false

    private var memoryReport: MemoryDoctorReport {
        MemoryDoctorReport(
            memory: model.snapshot.memory,
            topProcesses: model.snapshot.topProcesses
        )
    }

    private var statusBrief: StatusBrief {
        StatusBrief(snapshot: model.snapshot)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    PageHeader(title: "Status", subtitle: "Battery heat, CPU warmth, and memory pressure without the noise.", symbol: "gauge.with.dots.needle.67percent")
                    Spacer()
                    FreshnessChip(sampledAt: model.snapshot.sampledAt)
                    Button {
                        model.refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                }

                StatusBriefPanel(brief: statusBrief)

                ThermalOverviewPanel(snapshot: model.snapshot)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                    TrendCard(title: "CPU Temp", value: formatTemperaturePrecise(model.snapshot.thermal.cpuDisplayC), series: model.statusHistory.cpuTemperatureSeries, tint: .orange)
                    TrendCard(title: "Battery Temp", value: formatTemperaturePrecise(model.snapshot.thermal.batteryDisplayC), series: model.statusHistory.batteryTemperatureSeries, tint: batteryColor(model.snapshot.thermal.batteryWarningLevel))
                    TrendCard(title: "Memory", value: "\(model.snapshot.memory.usedPercent)%", series: model.statusHistory.memoryPercentSeries, tint: Color.oceanAccent)
                    TrendCard(title: "CPU Load", value: "\(Int(model.snapshot.cpu.usagePercent.rounded()))%", series: model.statusHistory.cpuUsageSeries, tint: Color.plumAccent)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    MetricTile(title: "CPU Temperature", value: formatTemperature(model.snapshot.thermal.cpuDisplayC), detail: cpuSourceLabel(model.snapshot.thermal.cpuTemperatureSource), tint: .orange)
                    MetricTile(title: "Memory", value: "\(model.snapshot.memory.usedPercent)%", detail: model.snapshot.memory.pressure.rawValue.capitalized, tint: Color.oceanAccent)
                    MetricTile(title: "Disk", value: String(format: "%.0f%%", model.snapshot.disk.usedPercent), detail: "\(formatBytes(model.snapshot.disk.freeBytes)) free", tint: .teal)
                    MetricTile(title: "Network Down", value: "\(formatBytes(model.snapshot.network.receivedBytesPerSecond))/s", detail: "Up \(formatBytes(model.snapshot.network.sentBytesPerSecond))/s", tint: Color.leafAccent)
                    MetricTile(title: "Battery", value: "\(model.snapshot.battery.percent)%", detail: "\(model.snapshot.battery.healthPercent)% health · \(model.snapshot.battery.cycleCount) cycles", tint: .mint)
                    MetricTile(title: "Fan", value: model.snapshot.fanRPM > 0 ? "\(model.snapshot.fanRPM) RPM" : "Read-only", detail: "No fan control", tint: .gray)
                }

                MemoryDoctorPanel(
                    report: memoryReport,
                    state: model.memoryPurgeState,
                    runPurge: { isShowingMemoryPurgeConfirmation = true }
                )

                ProcessTable(processes: model.snapshot.topProcesses)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("Run advanced memory purge?", isPresented: $isShowingMemoryPurgeConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Run", role: .destructive) {
                model.runMemoryPurge()
            }
        } message: {
            Text(MemoryPurgePlan(report: memoryReport).confirmationMessage)
        }
    }
}

struct StatusBriefPanel: View {
    var brief: StatusBrief

    private var tint: Color {
        switch brief.mood {
        case .steady: Color.leafAccent
        case .watch: Color.amberAccent
        case .hot: .red
        }
    }

    private var symbol: String {
        switch brief.mood {
        case .steady: "checkmark.seal.fill"
        case .watch: "thermometer.medium"
        case .hot: "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(brief.title)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                    Text(brief.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], spacing: 8) {
                ForEach(brief.signals) { signal in
                    StatusBriefSignalPill(
                        signal: signal,
                        tint: signal.id == brief.prioritySignalID ? tint : Color.thermoAccent,
                        isPriority: signal.id == brief.prioritySignalID
                    )
                }
            }
        }
        .padding(16)
        .softPanel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Status summary \(brief.title)"))
        .accessibilityValue(Text(brief.detail))
    }
}

struct StatusBriefSignalPill: View {
    var signal: StatusBriefSignal
    var tint: Color
    var isPriority: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint.opacity(isPriority ? 0.9 : 0.55))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(signal.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(signal.value)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(signal.detail)
                .font(.caption2.weight(isPriority ? .semibold : .regular))
                .foregroundStyle(isPriority ? tint : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isPriority ? tint.opacity(0.10) : Color.insetFill)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isPriority ? tint.opacity(0.28) : Color.subtleStroke))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(signal.title))
        .accessibilityValue(Text("\(signal.value), \(signal.detail)"))
    }
}

struct MemoryDoctorPanel: View {
    var report: MemoryDoctorReport
    var state: OperationState
    var runPurge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Memory Doctor")
                        .font(.headline)
                    Text(report.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(report.level.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(tint)
                    Text("\(report.memory.usedPercent)% used")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if report.allowsPurge {
                    Button {
                        runPurge()
                    } label: {
                        if state.isRunning {
                            Label("Running", systemImage: "hourglass")
                        } else {
                            Label("Advanced Purge", systemImage: "exclamationmark.triangle")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.isRunning)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                SensorValueRow(title: "Pressure", value: report.memory.pressure.rawValue.capitalized)
                SensorValueRow(title: "Compressed", value: formatBytes(report.memory.compressedBytes))
                SensorValueRow(title: "Free + Cache", value: formatBytes(report.memory.freeBytes))
                SensorValueRow(title: "Top Process", value: report.topMemoryProcess?.name ?? "None")
            }

            Label(report.allowsPurge ? "Advanced purge is available only after critical pressure confirmation." : "No RAM cleanup action is exposed while pressure is below critical.", systemImage: report.allowsPurge ? "exclamationmark.triangle" : "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            if state.phase != .idle {
                OperationStatePill(state: state)
            }
        }
        .padding(14)
        .softPanel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Memory Doctor"))
    }

    private var tint: Color {
        switch report.level {
        case .calm: Color.leafAccent
        case .watch: Color.amberAccent
        case .critical: .red
        }
    }

    private var symbol: String {
        switch report.level {
        case .calm: "memorychip"
        case .watch: "memorychip.fill"
        case .critical: "exclamationmark.triangle.fill"
        }
    }
}

struct PageHeader: View {
    var title: String
    var subtitle: String
    var symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.thermoAccent)
                .frame(width: 32, height: 32)
                .background(Color.iconBadgeFill.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("ThermoMole")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.thermoAccent)
                Text(title)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ThermalOverviewPanel: View {
    var snapshot: SystemSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Real battery pack", systemImage: "battery.100percent")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(formatTemperaturePrecise(snapshot.thermal.batteryDisplayC))
                        .font(.system(size: 46, weight: .semibold, design: .rounded))
                        .foregroundStyle(batteryColor(snapshot.thermal.batteryWarningLevel))
                        .monospacedDigit()
                    Text("AppleSmartBattery Temperature is shown here. VirtualTemperature stays out of the reading.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        SourceChip(title: "Battery", value: batterySourceLabel(snapshot.thermal.batteryTemperatureSource))
                        SourceChip(title: "CPU", value: cpuSourceLabel(snapshot.thermal.cpuTemperatureSource))
                    }
                }

                Spacer(minLength: 12)

                VStack(alignment: .leading, spacing: 8) {
                    Label("CPU warmth", systemImage: "cpu")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(formatTemperaturePrecise(snapshot.thermal.cpuDisplayC))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange)
                        .monospacedDigit()
                    Text(cpuSourceLabel(snapshot.thermal.cpuTemperatureSource))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("\(snapshot.chipName) · \(snapshot.modelIdentifier)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .frame(width: 190, alignment: .leading)

                VStack(spacing: 4) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(healthColor(snapshot.health.band).opacity(0.14))
                        Text("\(snapshot.health.value)")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(healthColor(snapshot.health.band))
                            .monospacedDigit()
                    }
                    .frame(width: 74, height: 74)
                    Label(conditionTitle(systemCondition(for: snapshot)), systemImage: conditionSymbol(systemCondition(for: snapshot)))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(conditionColor(systemCondition(for: snapshot)))
                        .lineLimit(1)
                }
            }

            Divider()

            HStack(spacing: 12) {
                OverviewReading(title: "CPU", value: formatTemperaturePrecise(snapshot.thermal.cpuDisplayC), tint: .orange)
                OverviewReading(title: "Battery", value: formatTemperaturePrecise(snapshot.thermal.batteryIORegC), tint: batteryColor(snapshot.thermal.batteryWarningLevel))
                OverviewReading(title: "SMC TB Max", value: formatTemperaturePrecise(snapshot.thermal.batteryCellMaxC), tint: Color.plumAccent)
                OverviewReading(title: "Memory", value: "\(snapshot.memory.usedPercent)%", tint: Color.oceanAccent)
            }

            if snapshot.thermal.hasBatterySensorMismatch {
                Label("SMC TB differs from AppleSmartBattery. ThermoMole displays the physical AppleSmartBattery reading.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .softPanel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Thermal overview"))
    }
}

struct SourceChip: View {
    var title: String
    var value: String

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.caption)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.insetFill)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value))
    }
}

struct OverviewReading: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.insetFill)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value))
    }
}

struct BatteryProtectionPanel: View {
    var snapshot: SystemSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Battery Pack", systemImage: "battery.100percent.bolt")
                    .font(.headline)
                Spacer()
                Text(formatTemperaturePrecise(snapshot.thermal.batteryDisplayC))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(batteryColor(snapshot.thermal.batteryWarningLevel))
                    .monospacedDigit()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                SensorValueRow(title: "Displayed", value: batterySourceLabel(snapshot.thermal.batteryTemperatureSource))
                SensorValueRow(title: "AppleSmartBattery", value: formatTemperaturePrecise(snapshot.thermal.batteryIORegC))
                SensorValueRow(title: "SMC TB Max", value: formatTemperaturePrecise(snapshot.thermal.batteryCellMaxC))
                SensorValueRow(title: "Warning Lines", value: "35° / 40°")
            }

            if snapshot.thermal.hasBatterySensorMismatch {
                Label("Diagnostic: SMC TB differs; displaying AppleSmartBattery Temperature.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .softPanel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Battery pack"))
    }
}

struct SensorValueRow: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.insetFill)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value))
    }
}

struct CleanTab: View {
    @ObservedObject var model: AppModel
    @State private var isShowingCleanupConfirmation = false
    @State private var cleanupSearchQuery = ""
    @State private var selectedCleanupCategory: CleanupCategory?
    @State private var cleanupSort = CleanupReviewSort.largestFirst

    private var summary: CleanupReviewSummary {
        CleanupReviewSummary(model.cleanupResult)
    }

    private var filteredItems: [CleanupItem] {
        CleanupReviewFilter(
            query: cleanupSearchQuery,
            category: selectedCleanupCategory,
            sort: cleanupSort
        ).apply(to: model.cleanupResult.items)
    }

    private var filteredBytes: UInt64 {
        filteredItems.reduce(0) { $0 + $1.sizeBytes }
    }

    private var selectedVisibleCount: Int {
        filteredItems.filter { model.cleanupSelection.contains($0) }.count
    }

    private var confirmationSummary: CleanupConfirmationSummary {
        CleanupConfirmationSummary(result: model.cleanupResult, selection: model.cleanupSelection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                PageHeader(title: "Clean", subtitle: "Find safe cache clutter; nothing leaves without review.", symbol: "sparkles")
                Spacer()
                OperationStatePill(state: model.cleanupState)
                Button {
                    model.scanCleanup()
                } label: {
                    if model.cleanupState.isRunning {
                        Label("Scanning", systemImage: "hourglass")
                    } else {
                        Label("Review Scan", systemImage: "magnifyingglass")
                    }
                }
                .disabled(model.cleanupState.isRunning)
                Button {
                    model.prepareSmartCleanup()
                } label: {
                    if model.cleanupState.isRunning {
                        Label("Scanning", systemImage: "hourglass")
                    } else {
                        Label("Smart Clean", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.cleanupState.isRunning)
            }

            HStack(spacing: 12) {
                MetricTile(title: "Review Items", value: "\(summary.itemCount)", tint: Color.oceanAccent)
                MetricTile(title: "Visible", value: "\(filteredItems.count)", detail: formatBytes(filteredBytes), tint: .teal)
                MetricTile(title: "Selected for Trash", value: formatBytes(model.selectedCleanupBytes()), tint: Color.leafAccent)
                MetricTile(title: "Skipped", value: "\(summary.skippedCount)", tint: .yellow)
            }

            CleanSafetyNotice(skippedCount: summary.skippedCount)

            if model.cleanupState.isRunning {
                ProgressPanel(title: "Scanning", message: model.cleanupState.message)
            } else if model.cleanupResult.items.isEmpty {
                ContentUnavailableView(
                    "No Scan Results",
                    systemImage: "sparkles",
                    description: Text("Smart Clean finds safe cache clutter and asks once before moving it to Trash. Review Scan opens the full list.")
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredItems.isEmpty {
                CleanupReviewControls(
                    query: $cleanupSearchQuery,
                    category: $selectedCleanupCategory,
                    sort: $cleanupSort,
                    canSelectVisible: false,
                    selectVisible: {},
                    clearVisible: {}
                )
                ContentUnavailableView(
                    "No Matching Items",
                    systemImage: "magnifyingglass",
                    description: Text("Clear the search field or choose another category.")
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CleanupReviewControls(
                    query: $cleanupSearchQuery,
                    category: $selectedCleanupCategory,
                    sort: $cleanupSort,
                    canSelectVisible: !filteredItems.isEmpty,
                    selectVisible: { model.setCleanupItems(filteredItems, selected: true) },
                    clearVisible: { model.setCleanupItems(filteredItems, selected: false) }
                )
                HStack(alignment: .top, spacing: 12) {
                    CleanupCategorySummaryView(categories: summary.categories)
                        .frame(width: 260)
                    VStack(spacing: 10) {
                        List(filteredItems) { item in
                            HStack {
                                Toggle("", isOn: Binding {
                                    model.cleanupSelection.contains(item)
                                } set: { isSelected in
                                    model.setCleanupItem(item, selected: isSelected)
                                })
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                                .accessibilityLabel(Text("Select \(item.url.lastPathComponent)"))
                                .accessibilityValue(Text(formatBytes(item.sizeBytes)))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.url.lastPathComponent)
                                        .lineLimit(1)
                                    Text(item.category.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(item.url.deletingLastPathComponent().path)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(formatBytes(item.sizeBytes))
                                    .monospacedDigit()
                                IconButton(systemName: "folder", help: "Reveal in Finder") {
                                    revealInFinder(item.url)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        HStack {
                            Text("\(selectedVisibleCount) of \(filteredItems.count) visible selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Review rows before moving anything to Trash.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                isShowingCleanupConfirmation = true
                            } label: {
                                Label("Clean Selected", systemImage: "trash")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!confirmationSummary.hasSelection || model.cleanupState.isRunning)
                            .help("Moves selected items to Trash after confirmation.")
                        }
                    }
                }
            }

            if !model.cleanupLog.isEmpty {
                CleanupOperationLogView(entries: Array(model.cleanupLog.prefix(8)))
            }
        }
        .padding(22)
        .background(Color.appBackground)
        .alert("Move selected items to Trash?", isPresented: $isShowingCleanupConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                model.executeSelectedCleanup()
            }
        } message: {
            Text(confirmationSummary.confirmationMessage)
        }
        .alert(item: Binding(
            get: { model.smartCleanupPlan },
            set: { model.smartCleanupPlan = $0 }
        )) { plan in
            let summary = CleanupConfirmationSummary(result: model.cleanupResult, selection: plan.selection)
            return Alert(
                title: Text("Move Smart Clean items to Trash?"),
                message: Text(summary.confirmationMessage),
                primaryButton: .destructive(Text("Move to Trash")) {
                    model.executeSelectedCleanup()
                },
                secondaryButton: .cancel(Text("Review List")) {
                    model.smartCleanupPlan = nil
                }
            )
        }
    }
}

struct CleanupReviewControls: View {
    @Binding var query: String
    @Binding var category: CleanupCategory?
    @Binding var sort: CleanupReviewSort
    var canSelectVisible: Bool
    var selectVisible: () -> Void
    var clearVisible: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            SearchField(text: $query, placeholder: "Search cleanup items or paths")
            HStack(spacing: 10) {
                Picker("Category", selection: $category) {
                    Text("All Categories").tag(nil as CleanupCategory?)
                    ForEach(CleanupCategory.allCases) { category in
                        Text(category.title).tag(Optional(category))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 170)
                Picker("Sort", selection: $sort) {
                    ForEach(CleanupReviewSort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 230)
                Spacer()
                Button {
                    selectVisible()
                } label: {
                    Label("Select Visible", systemImage: "checklist.checked")
                }
                .disabled(!canSelectVisible)
                Button {
                    clearVisible()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .disabled(!canSelectVisible)
                .help("Clear visible selection")
                .accessibilityLabel(Text("Clear visible selection"))
            }
        }
    }
}

struct SoftwareTab: View {
    @ObservedObject var model: AppModel
    @State private var selectedView = SoftwareViewMode.apps
    @State private var pendingUninstallApp: InstalledApp?
    @State private var searchQuery = ""

    private var filteredApps: [InstalledApp] {
        SoftwareInventoryFilter(query: searchQuery).filter(model.installedApps)
    }

    private var filteredStartupItems: [StartupItem] {
        SoftwareInventoryFilter(query: searchQuery).filter(model.startupItems)
    }

    private var summary: SoftwareSummary {
        SoftwareSummary(apps: model.installedApps, startupItems: model.startupItems)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                PageHeader(title: "Software", subtitle: "Apps, versions, and launch items gathered in one quiet list.", symbol: "shippingbox")
                Spacer()
                OperationStatePill(state: model.softwareState)
                Button {
                    model.loadSoftware()
                } label: {
                    if model.softwareState.isRunning {
                        Label("Loading", systemImage: "hourglass")
                    } else if model.installedApps.isEmpty && model.startupItems.isEmpty {
                        Label("Gather Apps", systemImage: "arrow.down.circle")
                    } else {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.softwareState.isRunning)
            }

            HStack(spacing: 12) {
                MetricTile(title: "Installed Apps", value: "\(summary.appCount)", tint: Color.oceanAccent)
                MetricTile(title: "Startup Items", value: "\(summary.startupItemCount)", detail: "\(summary.enabledStartupItemCount) enabled", tint: Color.plumAccent)
                MetricTile(title: "Uninstall Candidates", value: "\(summary.uninstallCandidateCount)", detail: "Trash with confirmation", tint: .yellow)
            }

            Picker("Software View", selection: $selectedView) {
                ForEach(SoftwareViewMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            SearchField(
                text: $searchQuery,
                placeholder: "Search apps, bundle IDs, versions, startup labels, or paths"
            )

            if model.softwareState.isRunning {
                ProgressPanel(title: "Loading Apps", message: model.softwareState.message)
            } else if selectedView == .apps && model.installedApps.isEmpty {
                ContentUnavailableView("No App Inventory", systemImage: "shippingbox", description: Text("Load Apps to scan application bundles."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedView == .startup && model.startupItems.isEmpty {
                ContentUnavailableView("No Startup Items", systemImage: "powerplug", description: Text("Load Apps to scan LaunchAgent and LaunchDaemon plists."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedView == .apps && filteredApps.isEmpty {
                ContentUnavailableView("No Matching Apps", systemImage: "magnifyingglass", description: Text("Clear the search field or try a bundle identifier, version, or path."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedView == .startup && filteredStartupItems.isEmpty {
                ContentUnavailableView("No Matching Startup Items", systemImage: "magnifyingglass", description: Text("Clear the search field or try a label, program, domain, or path."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedView == .startup {
                StartupItemList(items: filteredStartupItems)
            } else {
                InstalledAppList(
                    apps: filteredApps,
                    uninstall: { pendingUninstallApp = $0 }
                )
            }

            if !model.appUninstallLog.isEmpty {
                AppUninstallLogView(results: Array(model.appUninstallLog.prefix(6)))
            }
        }
        .padding(22)
        .background(Color.appBackground)
        .task {
            if model.installedApps.isEmpty && model.startupItems.isEmpty && !model.softwareState.isRunning {
                model.loadSoftware()
            }
        }
        .alert(item: $pendingUninstallApp) { app in
            let summary = AppUninstallConfirmationSummary(app: app)
            return Alert(
                title: Text(summary.title),
                message: Text(summary.confirmationMessage),
                primaryButton: .destructive(Text("Move to Trash")) {
                    model.uninstallApp(app)
                },
                secondaryButton: .cancel()
            )
        }
    }
}

enum SoftwareViewMode: String, CaseIterable, Identifiable {
    case apps
    case startup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apps: "Apps"
        case .startup: "Startup"
        }
    }
}

struct InstalledAppList: View {
    var apps: [InstalledApp]
    var uninstall: (InstalledApp) -> Void

    var body: some View {
        List(apps) { app in
            HStack(spacing: 10) {
                Image(systemName: "app.dashed")
                    .foregroundStyle(Color.oceanAccent)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(app.name)
                            .font(.callout.weight(.semibold))
                        Text(app.version)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(app.bundleIdentifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(app.bundlePath)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                IconButton(systemName: "folder", help: "Reveal in Finder") {
                    revealInFinder(URL(fileURLWithPath: app.bundlePath))
                }
                IconButton(systemName: "arrow.up.right.square", help: "Open app") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: app.bundlePath))
                }
                IconButton(systemName: "trash", help: "Move app to Trash") {
                    uninstall(app)
                }
            }
            .padding(.vertical, 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct StartupItemList: View {
    var items: [StartupItem]

    var body: some View {
        List(items) { item in
            HStack(spacing: 10) {
                Image(systemName: item.isEnabled ? "powerplug.fill" : "powerplug")
                    .foregroundStyle(item.isEnabled ? Color.leafAccent : .secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.label)
                        .font(.callout.weight(.semibold))
                    Text(item.program)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("\(item.domain.title) · \(item.plistPath)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                Text(item.isEnabled ? "Enabled" : "Disabled")
                    .font(.caption)
                    .foregroundStyle(item.isEnabled ? Color.leafAccent : .secondary)
                IconButton(systemName: "folder", help: "Reveal plist") {
                    revealInFinder(URL(fileURLWithPath: item.plistPath))
                }
            }
            .padding(.vertical, 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct AppUninstallLogView: View {
    var results: [AppUninstallResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Uninstall Log")
                    .font(.headline)
                Spacer()
                Text("\(results.count) recent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(results) { result in
                HStack(spacing: 10) {
                    Image(systemName: result.status == .succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.status == .succeeded ? Color.leafAccent : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.app.name)
                            .lineLimit(1)
                        Text(result.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(result.status.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
        .padding(14)
        .softPanel()
    }
}

struct OptimizeTab: View {
    @ObservedObject var model: AppModel
    @State private var pendingTask: OptimizeTask?
    @State private var isShowingDefaultOptimizeConfirmation = false

    private var safetyPolicy: OptimizeSafetyPolicy {
        OptimizeSafetyPolicy(context: model.optimizeSafetyContext)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                PageHeader(title: "Optimize", subtitle: "Small maintenance tasks, shown before they run.", symbol: "wand.and.stars")
                Spacer()
                OperationStatePill(state: model.optimizeState)
                Button {
                    model.refreshOptimizeSafetyContext()
                    isShowingDefaultOptimizeConfirmation = true
                } label: {
                    if model.optimizeState.isRunning {
                        Label("Running", systemImage: "hourglass")
                    } else {
                        Label("Run Default", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.optimizeState.isRunning)
            }

            OptimizeSafetySummaryPanel(summary: OptimizeSafetySummary(context: model.optimizeSafetyContext))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                ForEach(OptimizeTask.allCases) { task in
                    let skipReason = safetyPolicy.decision(for: task).skipReason
                    OptimizeTaskCard(
                        task: task,
                        plan: OptimizePlan(task: task),
                        skipReason: skipReason,
                        isRunning: model.optimizeState.isRunning,
                        run: { pendingTask = task }
                    )
                }
            }

            if !model.optimizeLog.isEmpty {
                OptimizeOperationLogView(results: Array(model.optimizeLog.prefix(6)))
            }
        }
        .padding(22)
        .background(Color.appBackground)
        .onAppear {
            model.refreshOptimizeSafetyContext()
        }
        .alert("Run default maintenance?", isPresented: $isShowingDefaultOptimizeConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Run", role: .destructive) {
                model.runDefaultOptimize()
            }
        } message: {
            let batch = OptimizeBatchPlan.defaultMaintenance(safetyContext: model.optimizeSafetyContext)
            let summary = OptimizeBatchConfirmationSummary(batch: batch)
            Text(summary.confirmationMessage)
        }
        .alert(item: $pendingTask) { task in
            let plan = OptimizePlan(task: task)
            let summary = OptimizeTaskConfirmationSummary(plan: plan)
            return Alert(
                title: Text(summary.title),
                message: Text(summary.confirmationMessage),
                primaryButton: .destructive(Text("Run")) {
                    model.runOptimizeTask(task)
                },
                secondaryButton: .cancel()
            )
        }
    }
}

struct OptimizeSafetySummaryPanel: View {
    var summary: OptimizeSafetySummary

    private var tint: Color {
        summary.activeSignals.isEmpty ? Color.leafAccent : Color.amberAccent
    }

    private var symbol: String {
        summary.activeSignals.isEmpty ? "checkmark.seal.fill" : "shield.lefthalf.filled"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.title)
                        .font(.headline)
                    Text(summary.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                Spacer()
            }

            if summary.activeSignals.isEmpty {
                Label("Normal context", systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.leafAccent)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(summary.activeSignals) { signal in
                        OptimizeSafetySignalChip(signal: signal)
                    }
                }
            }
        }
        .padding(14)
        .softPanel()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Optimize safety \(summary.title)"))
        .accessibilityValue(Text(summary.detail))
    }
}

struct OptimizeSafetySignalChip: View {
    var signal: OptimizeSafetySignal

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.amberAccent)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(signal.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(signal.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.insetFill)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.subtleStroke))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch signal.id {
        case "batteryPower": "battery.50percent"
        case "activeVPN": "lock.shield"
        case "externalDisplay": "display"
        case "externalAudio": "speaker.wave.2"
        case "bluetoothInput": "keyboard"
        case "bluetoothAudio": "headphones"
        default: "shield"
        }
    }
}

struct AnalyzeTab: View {
    @ObservedObject var model: AppModel
    @State private var pendingTrashEntry: DiskEntry?

    private var summary: DiskAnalysisSummary {
        DiskAnalysisSummary(scopeURL: model.diskAnalysisPath.currentURL, entries: model.diskEntries)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                PageHeader(title: "Analyze", subtitle: "Follow storage from a wide branch into the heavy leaves.", symbol: "chart.pie")
                Spacer()
                OperationStatePill(state: model.analyzeState)
                if model.analyzeState.isRunning {
                    Button {
                        model.cancelAnalyze()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                }
                Button {
                    chooseFolder()
                } label: {
                    Label("Choose Folder", systemImage: "folder.badge.gearshape")
                }
                .disabled(model.analyzeState.isRunning)
                Button {
                    model.analyzeHome()
                } label: {
                    if model.analyzeState.isRunning {
                        Label("Analyzing", systemImage: "hourglass")
                    } else {
                        Label("Map Home", systemImage: "chart.pie")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.analyzeState.isRunning)
            }

            HStack(spacing: 12) {
                MetricTile(title: "Entries", value: "\(summary.entryCount)", tint: Color.oceanAccent)
                MetricTile(title: "Mapped Size", value: formatBytes(summary.totalBytes), detail: "visible safe roots", tint: Color.leafAccent)
                MetricTile(title: "Largest", value: summary.largestEntry?.url.lastPathComponent ?? "--", detail: formatBytes(summary.largestEntry?.sizeBytes ?? 0), tint: .gray)
            }

            DiskBreadcrumbBar(
                path: model.diskAnalysisPath,
                isBusy: model.analyzeState.isRunning,
                goUp: { model.analyzeParentDiskURL() },
                select: { model.analyzeDiskBreadcrumb($0) }
            )

            if model.analyzeState.isRunning {
                ProgressPanel(title: "Analyzing Disk", message: model.analyzeState.message)
            } else if model.diskEntries.isEmpty {
                ContentUnavailableView("No Disk Map", systemImage: "chart.pie", description: Text("Map Home or choose a folder to rank large files and folders."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    DiskTreemapView(items: DiskTreemapItem.items(from: model.diskEntries, limit: 18)) { item in
                        if item.entry.isDirectory {
                            model.analyzeDiskEntry(item.entry)
                        }
                    }
                    .frame(minWidth: 300)

                    List(model.diskEntries) { entry in
                        HStack {
                            Image(systemName: entry.isDirectory ? "folder" : "doc")
                                .foregroundStyle(entry.isDirectory ? Color.oceanAccent : .secondary)
                            Text(entry.url.lastPathComponent)
                                .lineLimit(1)
                            DiskUsageBar(value: entry.sizeBytes, maxValue: model.diskEntries.first?.sizeBytes ?? entry.sizeBytes)
                                .frame(width: 150)
                            Spacer()
                            Text(formatBytes(entry.sizeBytes))
                                .monospacedDigit()
                            if entry.isDirectory {
                                IconButton(systemName: "arrow.down.right.circle", help: "Analyze folder") {
                                    model.analyzeDiskEntry(entry)
                                }
                            }
                            IconButton(systemName: "folder", help: "Reveal in Finder") {
                                revealInFinder(entry.url)
                            }
                            if model.canTrashDiskEntry(entry) {
                                IconButton(systemName: "trash", help: "Move to Trash") {
                                    pendingTrashEntry = entry
                                }
                                .disabled(model.analyzeState.isRunning)
                            } else {
                                Image(systemName: "lock")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 26, height: 26)
                                    .help("Protected path")
                                    .accessibilityLabel(Text("Protected path"))
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(minWidth: 420)
                }
            }

            if !model.diskTrashLog.isEmpty {
                DiskEntryTrashLogView(results: Array(model.diskTrashLog.prefix(6)))
            }
        }
        .padding(22)
        .background(Color.appBackground)
        .alert(item: $pendingTrashEntry) { entry in
            let summary = DiskTrashConfirmationSummary(entry: entry)
            return Alert(
                title: Text(summary.title),
                message: Text(summary.confirmationMessage),
                primaryButton: .destructive(Text("Move to Trash")) {
                    model.trashDiskEntry(entry)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Analyze"
        panel.message = "Choose a folder to analyze."
        if panel.runModal() == .OK, let url = panel.url {
            model.analyzeFolder(url)
        }
    }
}

struct SettingsTab: View {
    @ObservedObject var model: AppModel

    private var doctorGuidance: DoctorGuidanceSummary {
        DoctorGuidanceSummary(report: model.doctorReport)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: "Settings", subtitle: "Menu bar readings, local permissions, and reversible defaults.", symbol: "gearshape")

                DoctorSettingsPanel(
                    report: model.doctorReport,
                    refresh: { model.refreshDoctorReport() },
                    refreshStatus: model.refresh,
                    openFullDiskAccess: model.openFullDiskAccessSettings
                )

                SettingsPanel(title: "Menu Bar Metrics", symbol: "menubar.rectangle") {
                    ForEach(metricRows) { metric in
                        SettingsRow {
                            Toggle(metric.label, isOn: binding(for: metric))
                                .toggleStyle(.checkbox)
                            Spacer()
                            if model.menuBarMetrics.contains(metric) {
                                Text("\((model.menuBarMetrics.firstIndex(of: metric) ?? 0) + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                IconButton(systemName: "chevron.up", help: "Move up") {
                                    model.moveMenuBarMetric(metric, direction: .up)
                                }
                                IconButton(systemName: "chevron.down", help: "Move down") {
                                    model.moveMenuBarMetric(metric, direction: .down)
                                }
                            }
                        }
                    }
                }

                SettingsPanel(title: "App Presence", symbol: "macwindow") {
                    SettingsRow {
                        Toggle("Show Dock Icon", isOn: Binding {
                            model.showsDockIcon
                        } set: { isOn in
                            model.setDockIconVisible(isOn)
                        })
                        .toggleStyle(.switch)
                        Spacer()
                    }
                    SettingsRow {
                        Toggle("Launch at Login", isOn: Binding {
                            model.launchAtLoginEnabled
                        } set: { isOn in
                            model.setLaunchAtLogin(isOn)
                        })
                        .toggleStyle(.switch)
                        Spacer()
                    }
                    SettingsInfoRow(title: "Launch Status", value: model.launchAtLoginStatusText)
                }

                SettingsPanel(title: "Temperature Policy", symbol: "thermometer.medium") {
                    SettingsInfoRow(title: "Battery source", value: "AppleSmartBattery first")
                    SettingsInfoRow(title: "Fallback", value: "SMC TB max diagnostic")
                    SettingsInfoRow(title: "VirtualTemperature", value: "Ignored")
                    SettingsInfoRow(title: "Warnings", value: "35°C caution · 40°C hot")
                }

                SettingsPanel(title: "Local App", symbol: "lock.laptopcomputer") {
                    SettingsInfoRow(title: "Dock", value: model.showsDockIcon ? "Visible" : "Hidden by default")
                    SettingsInfoRow(title: "Full Disk Access", value: doctorGuidance.fullDiskAccessStatus)
                    SettingsInfoRow(title: "Scan mode", value: "Local only")
                    Text(doctorGuidance.fullDiskAccessDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    SettingsRow {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Diagnostic report")
                                .font(.callout.weight(.semibold))
                            Text("\(doctorGuidance.diagnosticScopeTitle): \(doctorGuidance.diagnosticIncludedLines.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Excludes: \(doctorGuidance.diagnosticExcludedLines.joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(doctorGuidance.sharingNote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.diagnosticExportState.phase != .idle {
                            OperationStatePill(state: model.diagnosticExportState)
                        }
                        if model.diagnosticImportState.phase != .idle {
                            OperationStatePill(state: model.diagnosticImportState)
                        }
                        Button {
                            chooseDiagnosticReportURL()
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            chooseDiagnosticImportURL()
                        } label: {
                            Label("Import", systemImage: "square.and.arrow.down")
                        }
                    }
                    if let summary = model.importedDiagnosticSummary {
                        ImportedDiagnosticSummaryView(summary: summary)
                    }
                    if let lastError = model.lastError {
                        Text(lastError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                }

                ProtectedPathPolicyPanel(catalog: .default())

                AttributionPanel(catalog: .default)

                OperationHistoryPanel(
                    entries: model.operationHistoryEntries,
                    error: model.operationHistoryError,
                    refresh: model.loadOperationHistory,
                    revealLog: model.revealOperationHistoryLog
                )
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.appBackground)
    }

    private var metricRows: [MenuBarMetric] {
        model.menuBarMetrics + MenuBarMetric.allCases.filter { !model.menuBarMetrics.contains($0) }
    }

    private func binding(for metric: MenuBarMetric) -> Binding<Bool> {
        Binding {
            model.menuBarMetrics.contains(metric)
        } set: { isOn in
            model.setMenuBarMetric(metric, enabled: isOn)
        }
    }

    private func chooseDiagnosticReportURL() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ThermoMole-Diagnostic.json"
        panel.prompt = "Export"
        panel.message = "Save a local ThermoMole diagnostic report."
        if panel.runModal() == .OK, let url = panel.url {
            model.exportDiagnosticReport(to: url)
        }
    }

    private func chooseDiagnosticImportURL() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Import"
        panel.message = "Open a ThermoMole diagnostic report."
        if panel.runModal() == .OK, let url = panel.url {
            model.importDiagnosticReport(from: url)
        }
    }
}

struct ProtectedPathPolicyPanel: View {
    var catalog: ProtectedPathCatalog

    var body: some View {
        SettingsPanel(title: "Protected Items", symbol: "shield.lefthalf.filled") {
            Text(catalog.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ProtectedPathList(
                title: "Never Trash",
                value: "\(catalog.protectedRoots.count) roots",
                paths: catalog.protectedRoots
            )
            ProtectedPathList(
                title: "Trash Allowed Under",
                value: "\(catalog.allowedDeletePrefixes.count) prefixes",
                paths: catalog.allowedDeletePrefixes
            )
            ProtectedPathList(
                title: "Default Scan Skips",
                value: "\(catalog.defaultScanSkips.count) roots",
                paths: catalog.defaultScanSkips
            )
        }
    }
}

struct ProtectedPathList: View {
    var title: String
    var value: String
    var paths: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(paths, id: \.self) { path in
                    Text(displayPath(path))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.cardFill)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }
        }
        .padding(10)
        .background(Color.insetFill)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if path == home { return "~" }
        if path.hasPrefix("\(home)/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

struct ImportedDiagnosticSummaryView: View {
    var summary: DiagnosticReportSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("Imported Report", systemImage: "doc.text.magnifyingglass")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(summary.generatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                SensorValueRow(title: "Version", value: summary.appVersion)
                SensorValueRow(title: "Schema", value: "\(summary.schemaVersion)")
                SensorValueRow(title: "Health", value: "\(summary.healthScore)")
                SensorValueRow(title: "Operations", value: "\(summary.recentOperationCount)")
            }
            Text(summary.machine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(summary.doctorSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .background(Color.insetFill)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Imported diagnostic report"))
    }
}

struct AttributionPanel: View {
    var catalog: AttributionCatalog

    var body: some View {
        SettingsPanel(title: "Attribution", symbol: "text.book.closed") {
            Text(catalog.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(catalog.entries) { entry in
                AttributionRow(entry: entry)
            }

            Label(catalog.licenseNotice, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(Color.amberAccent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.insetFill)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct AttributionRow: View {
    var entry: AttributionEntry

    var body: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.callout.weight(.semibold))
                Text(entry.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.url)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            if let url = URL(string: entry.url) {
                Link(destination: url) {
                    Label("Open", systemImage: "arrow.up.right.square")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct OperationHistoryPanel: View {
    var entries: [OperationHistoryEntry]
    var error: String?
    var refresh: () -> Void
    var revealLog: () -> Void

    var body: some View {
        SettingsPanel(title: "Operation History", symbol: "clock.arrow.circlepath") {
            HStack {
                Text("\(entries.count) recent operations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Button {
                    revealLog()
                } label: {
                    Label("Reveal Log", systemImage: "folder")
                }
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.insetFill)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if entries.isEmpty {
                Text("No operations logged yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.insetFill)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 8) {
                    ForEach(entries.prefix(8)) { entry in
                        OperationHistoryRow(entry: entry)
                    }
                }
            }
        }
    }
}

struct OperationHistoryRow: View {
    var entry: OperationHistoryEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(entry.kind.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.insetFill)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Text(entry.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.status.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Text("\(entry.itemCount) · \(formatBytes(entry.bytes))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(entry.executedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(10)
        .background(Color.insetFill)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var symbol: String {
        switch entry.status {
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .skipped: "minus.circle.fill"
        case .mixed: "exclamationmark.circle.fill"
        }
    }

    private var color: Color {
        switch entry.status {
        case .succeeded: Color.leafAccent
        case .failed: .red
        case .skipped: .secondary
        case .mixed: Color.amberAccent
        }
    }
}

struct DoctorSettingsPanel: View {
    var report: DoctorReport
    var refresh: () -> Void
    var refreshStatus: () -> Void
    var openFullDiskAccess: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: report.isAllClear ? "checkmark.seal.fill" : "stethoscope")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(report.isAllClear ? Color.leafAccent : Color.amberAccent)
                    .frame(width: 34, height: 34)
                    .background((report.isAllClear ? Color.leafAccent : Color.amberAccent).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Doctor")
                        .font(.headline)
                    Text(report.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

            VStack(spacing: 8) {
                ForEach(report.checks) { check in
                    DoctorCheckRow(
                        check: check,
                        refreshStatus: refreshStatus,
                        openFullDiskAccess: openFullDiskAccess
                    )
                }
            }
        }
        .padding(14)
        .softPanel()
    }
}

struct DoctorCheckRow: View {
    var check: DoctorCheck
    var refreshStatus: () -> Void
    var openFullDiskAccess: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.title)
                    .font(.callout.weight(.semibold))
                Text(check.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if check.action == .openFullDiskAccess {
                Button {
                    openFullDiskAccess()
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                }
            } else if check.action == .refreshStatusSnapshot {
                Button {
                    refreshStatus()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            } else if check.action != .none {
                Text(doctorActionLabel(check.action))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.insetFill)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var color: Color {
        switch check.severity {
        case .ok: Color.leafAccent
        case .warning: Color.amberAccent
        }
    }
}

struct SettingsPanel<Content: View>: View {
    var title: String
    var symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)
            VStack(spacing: 8) {
                content
            }
        }
        .padding(14)
        .softPanel()
    }
}

struct SettingsRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .padding(10)
        .background(Color.insetFill)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SettingsInfoRow: View {
    var title: String
    var value: String

    var body: some View {
        SettingsRow {
            Text(title)
                .font(.callout.weight(.medium))
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct OperationStatePill: View {
    var state: OperationState

    var body: some View {
        HStack(spacing: 6) {
            if state.phase == .running {
                ProgressView()
                    .controlSize(.small)
            } else {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
            }
            Text(state.message)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(tint.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.16)))
        .foregroundStyle(tint)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Operation status"))
        .accessibilityValue(Text(state.message))
    }

    private var tint: Color {
        switch state.phase {
        case .idle: .secondary
        case .running: Color.oceanAccent
        case .finished: Color.leafAccent
        case .failed: .red
        }
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear search")
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.insetFill)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.subtleStroke))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct OptimizeTaskCard: View {
    var task: OptimizeTask
    var plan: OptimizePlan
    var skipReason: String?
    var isRunning: Bool
    var run: () -> Void

    private var isStaged: Bool {
        plan.commands.isEmpty || skipReason != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.headline)
                    Text(plan.riskLevel.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(tint)
                }
                Spacer()
            }

            Text(plan.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            if let skipReason {
                Label(skipReason, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color.amberAccent)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(plan.effects.prefix(3), id: \.self) { effect in
                    Label(effect, systemImage: "checkmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            HStack {
                Text("\(plan.commands.count) command\(plan.commands.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    run()
                } label: {
                    Label(isStaged ? "Staged" : "Run", systemImage: isStaged ? "lock" : "play.fill")
                }
                .disabled(isRunning || isStaged)
            }
        }
        .padding(14)
        .softPanel()
    }

    private var tint: Color {
        switch plan.riskLevel {
        case .low: Color.leafAccent
        case .medium: Color.amberAccent
        }
    }

    private var symbol: String {
        switch task {
        case .quickLook: "eye"
        case .launchServices: "app.badge"
        case .periodicMaintenance: "calendar.badge.clock"
        case .savedApplicationState: "clock.arrow.circlepath"
        case .dockRefresh: "rectangle.bottomthird.inset.filled"
        }
    }
}

struct OptimizeOperationLogView: View {
    var results: [OptimizeExecutionResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Maintenance Log")
                    .font(.headline)
                Spacer()
                Text("\(results.count) recent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(results, id: \.executedAt) { result in
                HStack(spacing: 10) {
                    Image(systemName: result.status == .succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.status == .succeeded ? Color.leafAccent : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.task.title)
                            .lineLimit(1)
                        Text(result.entries.first?.output.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? result.status.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("\(result.entries.count) command\(result.entries.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
        .padding(14)
        .softPanel()
    }
}

struct ProgressPanel: View {
    var title: String
    var message: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softPanel()
    }
}

struct CleanupOperationLogView: View {
    var entries: [CleanupOperationLogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Operation Log")
                    .font(.headline)
                Spacer()
                Text("\(entries.count) recent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                HStack(spacing: 10) {
                    Image(systemName: symbol(for: entry.status))
                        .foregroundStyle(color(for: entry.status))
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.item.url.lastPathComponent)
                            .lineLimit(1)
                        Text(entry.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(formatBytes(entry.item.sizeBytes))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
        .padding(14)
        .softPanel()
    }

    private func symbol(for status: CleanupOperationStatus) -> String {
        switch status {
        case .succeeded: "checkmark.circle.fill"
        case .skipped: "exclamationmark.triangle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    private func color(for status: CleanupOperationStatus) -> Color {
        switch status {
        case .succeeded: Color.leafAccent
        case .skipped: .yellow
        case .failed: .red
        }
    }
}

struct DiskEntryTrashLogView: View {
    var results: [DiskEntryTrashResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Analyze Trash Log")
                    .font(.headline)
                Spacer()
                Text("\(results.count) recent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(results) { result in
                HStack(spacing: 10) {
                    Image(systemName: symbol(for: result.status))
                        .foregroundStyle(color(for: result.status))
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.entry.url.lastPathComponent)
                            .lineLimit(1)
                        Text(result.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(formatBytes(result.entry.sizeBytes))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
        .padding(14)
        .softPanel()
    }

    private func symbol(for status: CleanupOperationStatus) -> String {
        switch status {
        case .succeeded: "checkmark.circle.fill"
        case .skipped: "exclamationmark.triangle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    private func color(for status: CleanupOperationStatus) -> Color {
        switch status {
        case .succeeded: Color.leafAccent
        case .skipped: Color.amberAccent
        case .failed: .red
        }
    }
}

struct CleanSafetyNotice: View {
    var skippedCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.leafAccent)
                .frame(width: 30, height: 30)
                .background(Color.leafAccent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text("Calm cleanup policy")
                    .font(.callout.weight(.semibold))
                Text("Review first. Trash only. Protected media cache roots are skipped\(skippedCount > 0 ? " (\(skippedCount))" : "").")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(12)
        .softPanel()
    }
}

struct DiskBreadcrumbBar: View {
    var path: DiskAnalysisPath
    var isBusy: Bool
    var goUp: () -> Void
    var select: (DiskBreadcrumb) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: goUp) {
                Image(systemName: "chevron.up")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .disabled(!path.canGoUp || isBusy)
            .help("Analyze parent folder")
            .accessibilityLabel(Text("Analyze parent folder"))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(path.breadcrumbs) { breadcrumb in
                        Button {
                            select(breadcrumb)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: breadcrumb.url == path.rootURL ? "house" : "folder")
                                    .font(.caption)
                                Text(breadcrumb.title)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isBusy || breadcrumb.url == path.currentURL)
                        .accessibilityLabel(Text("Open \(breadcrumb.title)"))
                        .accessibilityHint(Text(breadcrumb.url == path.currentURL ? "Current folder" : "Analyze this folder"))
                    }
                }
            }
        }
        .padding(10)
        .softPanel()
    }
}

struct DiskTreemapView: View {
    var items: [DiskTreemapItem]
    var select: (DiskTreemapItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Treemap")
                .font(.headline)
            GeometryReader { proxy in
                let columns = treemapColumns(for: proxy.size.width)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(items) { item in
                        Button {
                            select(item)
                        } label: {
                            DiskTreemapCell(item: item)
                                .frame(height: treemapCellHeight(item, in: proxy.size))
                        }
                        .buttonStyle(.plain)
                        .disabled(!item.entry.isDirectory)
                        .help(item.entry.isDirectory ? "Analyze folder" : "File")
                        .accessibilityLabel(Text(item.entry.isDirectory ? "Analyze folder \(item.entry.url.lastPathComponent)" : "File \(item.entry.url.lastPathComponent)"))
                        .accessibilityValue(Text(formatBytes(item.entry.sizeBytes)))
                    }
                }
            }
        }
        .padding(14)
        .softPanel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Disk treemap"))
        .accessibilityValue(Text("\(items.count) entries"))
    }

    private func treemapColumns(for width: CGFloat) -> [GridItem] {
        let count = max(2, min(4, Int(width / 150)))
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    private func treemapCellHeight(_ item: DiskTreemapItem, in size: CGSize) -> CGFloat {
        let base = max(66, min(120, size.height / 4))
        if item.isLargest { return base + 34 }
        return base + CGFloat(item.ratio) * 64
    }
}

struct DiskTreemapCell: View {
    var item: DiskTreemapItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: item.entry.isDirectory ? "folder.fill" : "doc.fill")
                    .foregroundStyle(item.entry.isDirectory ? Color.oceanAccent : .secondary)
                Spacer()
                Text("\(Int((item.ratio * 100).rounded()))%")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.entry.url.lastPathComponent)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(formatBytes(item.entry.sizeBytes))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(item.entry.isDirectory ? Color.oceanAccent.opacity(0.11) : Color.insetFill)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(item.isLargest ? Color.thermoAccent.opacity(0.55) : Color.subtleStroke))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(item.entry.url.lastPathComponent))
        .accessibilityValue(Text("\(formatBytes(item.entry.sizeBytes)), \(Int((item.ratio * 100).rounded())) percent of shown items"))
    }
}

struct TrendCard: View {
    var title: String
    var value: String
    var series: [Double]
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            SparklineView(values: series, tint: tint)
                .frame(height: 42)
        }
        .padding(14)
        .softPanel()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(value), \(series.count) samples"))
    }
}

struct SparklineView: View {
    var values: [Double]
    var tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(tint.opacity(0.08))
                sparklinePath(in: proxy.size)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }

    private func sparklinePath(in size: CGSize) -> Path {
        var path = Path()
        guard values.count > 1, size.width > 0, size.height > 0 else { return path }

        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let spread = max(maxValue - minValue, 1)

        for index in values.indices {
            let x = CGFloat(index) / CGFloat(values.count - 1) * size.width
            let normalized = (values[index] - minValue) / spread
            let y = size.height - CGFloat(normalized) * size.height
            let point = CGPoint(x: x, y: y)
            if index == values.startIndex {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

struct CleanupCategorySummaryView: View {
    var categories: [CleanupCategorySummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Categories")
                .font(.headline)
            ForEach(categories, id: \.category) { category in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(category.category.title)
                            .lineLimit(1)
                        Spacer()
                        Text(formatBytes(category.bytes))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    DiskUsageBar(value: category.bytes, maxValue: categories.first?.bytes ?? category.bytes)
                        .frame(height: 7)
                }
            }
        }
        .padding(14)
        .softPanel()
    }
}

struct DiskUsageBar: View {
    var value: UInt64
    var maxValue: UInt64

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * ratio
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.16))
                Capsule()
                    .fill(Color.thermoAccent)
                    .frame(width: width)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    private var ratio: CGFloat {
        guard maxValue > 0 else { return 0 }
        return min(max(CGFloat(Double(value) / Double(maxValue)), 0), 1)
    }
}

struct IconButton: View {
    var systemName: String
    var help: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(Text(help))
    }
}

struct HealthHeader: View {
    var snapshot: SystemSnapshot

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(healthColor(snapshot.health.band).opacity(0.14))
                Text("\(snapshot.health.value)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(healthColor(snapshot.health.band))
            }
            .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text("ThermoMole")
                    .font(.title2.bold())
                Text("\(snapshot.chipName) · \(snapshot.modelIdentifier)")
                    .foregroundStyle(.secondary)
                Text("Uptime \(formatUptime(snapshot.uptimeSeconds)) · \(snapshot.macOSVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .softPanel()
    }
}

struct MetricTile: View {
    var title: String
    var value: String
    var detail: String = ""
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint.opacity(0.85))
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.cardFill)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.subtleStroke))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.panelShadow, radius: 2, x: 0, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(detail.isEmpty ? value : "\(value), \(detail)"))
    }
}

struct ProcessTable: View {
    var processes: [ProcessSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Processes")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Name").foregroundStyle(.secondary)
                    Text("PID").foregroundStyle(.secondary)
                    Text("CPU").foregroundStyle(.secondary)
                    Text("Memory").foregroundStyle(.secondary)
                }
                ForEach(processes) { process in
                    GridRow {
                        Text(process.name).lineLimit(1)
                        Text("\(process.pid)").monospacedDigit()
                        Text("\(process.cpuPercent, specifier: "%.1f")%").monospacedDigit()
                        Text(formatBytes(process.memoryBytes)).monospacedDigit()
                    }
                }
            }
            .font(.caption)
        }
        .padding(14)
        .softPanel()
    }
}

extension Color {
    static let appBackground = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedRed: 0.965, green: 0.955, blue: 0.925, alpha: 1),
        dark: NSColor(calibratedRed: 0.085, green: 0.083, blue: 0.073, alpha: 1)
    ))
    static let appSidebar = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedRed: 0.895, green: 0.925, blue: 0.875, alpha: 1),
        dark: NSColor(calibratedRed: 0.115, green: 0.118, blue: 0.098, alpha: 1)
    ))
    static let cardFill = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedRed: 0.992, green: 0.982, blue: 0.948, alpha: 1),
        dark: NSColor(calibratedRed: 0.145, green: 0.137, blue: 0.118, alpha: 1)
    ))
    static let insetFill = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.895, alpha: 1),
        dark: NSColor(calibratedRed: 0.108, green: 0.108, blue: 0.096, alpha: 1)
    ))
    static let selectionFill = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedRed: 0.972, green: 0.855, blue: 0.70, alpha: 1),
        dark: NSColor(calibratedRed: 0.235, green: 0.152, blue: 0.105, alpha: 1)
    ))
    static let iconBadgeFill = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedRed: 0.985, green: 0.84, blue: 0.62, alpha: 1),
        dark: NSColor(calibratedRed: 0.265, green: 0.164, blue: 0.108, alpha: 1)
    ))
    static let subtleStroke = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedRed: 0.48, green: 0.39, blue: 0.28, alpha: 0.14),
        dark: NSColor(calibratedRed: 0.85, green: 0.78, blue: 0.66, alpha: 0.12)
    ))
    static let panelShadow = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedWhite: 0, alpha: 0.035),
        dark: NSColor(calibratedWhite: 0, alpha: 0.18)
    ))
    static let thermoAccent = Color(red: 0.68, green: 0.27, blue: 0.16)
    static let oceanAccent = Color(red: 0.22, green: 0.44, blue: 0.54)
    static let leafAccent = Color(red: 0.28, green: 0.52, blue: 0.36)
    static let amberAccent = Color(red: 0.76, green: 0.52, blue: 0.21)
    static let plumAccent = Color(red: 0.46, green: 0.37, blue: 0.50)
}

extension NSColor {
    static func thermoAdaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        }
    }
}

struct SoftPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.cardFill)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.subtleStroke))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: Color.panelShadow, radius: 2, x: 0, y: 1)
    }
}

extension View {
    func softPanel() -> some View {
        modifier(SoftPanelModifier())
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

func formatTemperature(_ value: Double?) -> String {
    guard let value else { return "--°" }
    return "\(Int(value.rounded()))°"
}

func formatTemperaturePrecise(_ value: Double?) -> String {
    guard let value else { return "--°" }
    return String(format: "%.1f°", value)
}

func batterySourceLabel(_ source: BatteryTemperatureSource) -> String {
    switch source {
    case .unavailable: "Unavailable"
    case .smcCellMax: "SMC TB Max"
    case .ioregTemperature: "AppleSmartBattery"
    }
}

func cpuSourceLabel(_ source: CPUTemperatureSource) -> String {
    switch source {
    case .unavailable: "Unavailable"
    case .cpuDieHotspot: "CPU Die Hotspot"
    case .cpuAverage: "CPU Average"
    }
}

func formatLoad(_ loadAverage: [Double]) -> String {
    guard let first = loadAverage.first else { return "--" }
    return String(format: "%.2f", first)
}

func revealInFinder(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
}

func formatBytes(_ value: UInt64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var amount = Double(value)
    var index = 0
    while amount >= 1024, index < units.count - 1 {
        amount /= 1024
        index += 1
    }
    return index == 0 ? "\(Int(amount)) \(units[index])" : String(format: "%.1f %@", amount, units[index])
}

func formatUptime(_ seconds: UInt64) -> String {
    let days = seconds / 86_400
    let hours = (seconds % 86_400) / 3_600
    let minutes = (seconds % 3_600) / 60
    if days > 0 { return "\(days)d \(hours)h" }
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m"
}

func batteryColor(_ level: TemperatureWarningLevel) -> Color {
    switch level {
    case .normal: Color.leafAccent
    case .caution: Color.amberAccent
    case .hot: .red
    }
}

func healthColor(_ band: HealthBand) -> Color {
    switch band {
    case .excellent: Color.leafAccent
    case .good: Color.oceanAccent
    case .fair: Color.amberAccent
    case .needsAttention: .red
    }
}

func systemCondition(for snapshot: SystemSnapshot) -> SystemConditionLevel {
    SystemConditionPolicy.resolve(
        cpuTemperatureC: snapshot.thermal.cpuDisplayC,
        batteryWarningLevel: snapshot.thermal.batteryWarningLevel,
        memoryPressure: snapshot.memory.pressure,
        healthBand: snapshot.health.band
    )
}

func conditionColor(_ condition: SystemConditionLevel) -> Color {
    switch condition {
    case .normal: Color.leafAccent
    case .caution: Color.amberAccent
    case .hot: .red
    }
}

func nsColor(for condition: SystemConditionLevel) -> NSColor {
    switch condition {
    case .normal: NSColor(calibratedRed: 0.22, green: 0.56, blue: 0.36, alpha: 1)
    case .caution: NSColor(calibratedRed: 0.84, green: 0.58, blue: 0.20, alpha: 1)
    case .hot: .systemRed
    }
}

func conditionTitle(_ condition: SystemConditionLevel) -> String {
    switch condition {
    case .normal: "All clear"
    case .caution: "Watch"
    case .hot: "Needs attention"
    }
}

func conditionSymbol(_ condition: SystemConditionLevel) -> String {
    switch condition {
    case .normal: "checkmark.circle.fill"
    case .caution: "exclamationmark.triangle.fill"
    case .hot: "flame.fill"
    }
}

func freshnessColor(_ level: StatusFreshnessLevel) -> Color {
    switch level {
    case .live: Color.leafAccent
    case .updating: Color.amberAccent
    case .stale: .red
    }
}

func freshnessSymbol(_ level: StatusFreshnessLevel) -> String {
    switch level {
    case .live: "circle.fill"
    case .updating: "clock.fill"
    case .stale: "exclamationmark.triangle.fill"
    }
}

func doctorActionLabel(_ action: DoctorAction) -> String {
    switch action {
    case .none: ""
    case .openFullDiskAccess: "Open Settings"
    case .reduceMemoryLoad: "Review processes"
    case .reviewStorage: "Use Clean or Analyze"
    case .reviewBatteryHealth: "Check service"
    case .repairOperationLog: "Check Logs folder"
    case .reviewRecentFailures: "Review logs"
    case .refreshStatusSnapshot: "Refresh status"
    }
}
