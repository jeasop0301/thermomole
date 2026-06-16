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

    func applicationWillTerminate(_ notification: Notification) {
        freshnessTimer?.invalidate()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached { [model] in
            await model.flushExposureForTermination()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
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
        let prefixColor = presentation.freshnessLevel == .stale ? NSColor.systemRed : nsColor(for: condition)

        let attributed = NSMutableAttributedString(string: presentation.visibleTitle)
        attributed.addAttribute(.foregroundColor, value: prefixColor, range: NSRange(location: 0, length: 1))

        let level = snapshot.thermal.batteryWarningLevel
        if presentation.freshnessLevel != .stale, level != .normal, let segment = presentation.batterySegment {
            let prefixLength = (presentation.visibleTitle as NSString).length - (presentation.title as NSString).length
            let tintRange = NSRange(location: segment.range.location + prefixLength, length: segment.range.length)
            if NSMaxRange(tintRange) <= attributed.length {
                attributed.addAttribute(
                    .foregroundColor,
                    value: nsColor(for: SystemConditionPolicy.batteryTint(for: level)),
                    range: tintRange
                )
            }
        }

        if level == .hot, snapshot.battery.isCharging {
            let attachment = NSTextAttachment()
            attachment.image = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: "charging while hot")?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
            attachment.bounds = NSRect(x: 0, y: -2, width: 12, height: 12)
            attributed.insert(NSAttributedString(string: " "), at: 0)
            attributed.insert(NSAttributedString(attachment: attachment), at: 0)
        }

        button.attributedTitle = attributed
        button.toolTip = presentation.toolTip
        if level == .hot, snapshot.battery.isCharging {
            button.setAccessibilityLabel("Charging while hot. " + presentation.accessibilityLabel)
        } else {
            button.setAccessibilityLabel(presentation.accessibilityLabel)
        }
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
    @Published var todayExposure = ThermalExposureSummary.empty

    private let provider = NativeSensorProvider()
    private let historyStore = OperationHistoryStore.live
    private let statusSnapshotStore = StatusSnapshotStore.live
    private let exposureCoordinator = ThermalExposureCoordinator()
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
        Task {
            await exposureCoordinator.bootstrap()
            todayExposure = await exposureCoordinator.summary(at: Date(), calendar: .current)
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
            refreshDoctorReport()
            samplingGate.finish(startedAt: sampleStartedAt)
        }
    }

    nonisolated func flushExposureForTermination() async {
        await exposureCoordinator.flushNow(at: Date())
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
                    SettingsInfoRow(title: "Warnings", value: "\(Int(ThermalThresholds.batteryCautionC))°C caution · \(Int(ThermalThresholds.batteryHotC))°C hot")
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








