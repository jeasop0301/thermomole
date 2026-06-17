import Foundation
import Combine
import SwiftUI
import AppKit
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
    @Published var statusHistory = BoundedStatusHistory(limit: 30)
    @Published var operationHistoryEntries = [OperationHistoryEntry]()
    @Published var operationHistoryError: String?
    @Published var lastError: String?
    @Published var doctorReport = DoctorReport.make(inputs: .placeholder)
    @Published var todayExposure = ThermalExposureSummary.empty
    @Published var todayChargeExposure = ChargeExposureSummary.empty
    @Published var batteryHealthSeries: [Double] = []
    @Published var latestBatteryHealth: DailyBatteryHealth?
    @Published var batteryLongevity: BatteryLongevityReport?
    @Published var todayCPUExposure = CPUExposureSummary.empty
    @Published var longevityAssessment = LongevityAssessment(score: 100, factors: [], actions: [])
    @Published var notificationsEnabled = false

    private let provider = NativeSensorProvider()
    private let historyStore = OperationHistoryStore.live
    private let statusSnapshotStore = StatusSnapshotStore.live
    private let exposureCoordinator = ThermalExposureCoordinator()
    private let chargeCoordinator = ChargeExposureCoordinator()
    private let cpuExposureCoordinator = CPUExposureCoordinator()
    private let notifier = NotificationCenterClient()
    private var lastNotified: [LongevityNotification: Date] = [:]
    private let quietHours = QuietHours(startHour: 22, endHour: 7)
    private let batteryHealthStore = BatteryHealthStore()
    private var batteryHealthLog = BatteryHealthLog()
    private var lastSavedHealthRecord: BatteryHealthRecord?
    private var timer: Timer?
    private var doctorFreshnessTimer: Timer?
    private var samplingGate = SamplingGate(timeout: 8)

    private(set) lazy var clean = CleanModel(
        scan: { CleanupScanner().scan(preselection: $0) },
        execute: { items, selection in CleanupExecutor().execute(items: items, selection: selection, mode: .trash) },
        logOperation: { [weak self] entry in self?.appendHistory(entry) },
        onCleaned: { [weak self] in self?.refreshDoctorReport() }
    )

    private(set) lazy var analyze = AnalyzeModel(
        analyze: { DiskAnalyzer().analyze($0, shouldCancel: $1) },
        trash: { DiskEntryTrashExecutor().moveToTrash($0) },
        logOperation: { [weak self] entry in self?.appendHistory(entry) },
        onChanged: { [weak self] in self?.refreshDoctorReport() }
    )

    private(set) lazy var software = SoftwareModel(
        loadInventory: { let inventory = SoftwareInventory(); return (inventory.installedApps(), inventory.startupItems()) },
        uninstall: { AppUninstallExecutor().moveToTrash($0) },
        logOperation: { [weak self] entry in self?.appendHistory(entry) },
        onChanged: { [weak self] in self?.refreshDoctorReport() }
    )

    private(set) lazy var optimize = OptimizeModel(
        currentSnapshot: { [weak self] in self?.snapshot ?? .placeholder },
        logOperation: { [weak self] entry in self?.appendHistory(entry) },
        onChanged: { [weak self] in self?.refreshDoctorReport() }
    )

    private(set) lazy var memory = MemoryModel(
        currentSnapshot: { [weak self] in self?.snapshot ?? .placeholder },
        purge: { MemoryPurgeExecutor().execute(plan: $0) },
        logOperation: { [weak self] entry in self?.appendHistory(entry) },
        onChanged: { [weak self] in self?.refreshDoctorReport() }
    )

    private(set) lazy var settings = SettingsModel(
        currentSnapshot: { [weak self] in self?.snapshot ?? .placeholder },
        currentDoctorReport: { [weak self] in self?.doctorReport ?? DoctorReport.make(inputs: .placeholder) },
        currentHistory: { [weak self] in self?.operationHistoryEntries ?? [] },
        reportError: { [weak self] message in self?.lastError = message }
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
            batteryLongevity = BatteryLongevity.evaluate(history: batteryHealthLog.all())
        }
        Task {
            await exposureCoordinator.bootstrap()
            await chargeCoordinator.bootstrap()
            await cpuExposureCoordinator.bootstrap()
            todayExposure = await exposureCoordinator.summary(at: Date(), calendar: .current)
            todayChargeExposure = await chargeCoordinator.summary(at: Date(), calendar: .current)
            todayCPUExposure = await cpuExposureCoordinator.summary(at: Date(), calendar: .current)
            recomputeLongevity()
        }
        notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        if notificationsEnabled { notifier.requestAuthorization() }
        loadOperationHistory()
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
            await cpuExposureCoordinator.record(
                temperatureC: next.thermal.cpuDisplayC,
                at: next.sampledAt,
                calendar: .current
            )
            todayCPUExposure = await cpuExposureCoordinator.summary(at: next.sampledAt, calendar: .current)
            recordBatteryHealth(from: next)
            recomputeLongevity()
            evaluateNotifications(for: next)
            refreshDoctorReport()
            samplingGate.finish(startedAt: sampleStartedAt)
        }
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "notificationsEnabled")
        if enabled { notifier.requestAuthorization() }
    }

    private func evaluateNotifications(for snapshot: SystemSnapshot) {
        guard notificationsEnabled else { return }
        var active: Set<LongevityNotification> = []
        if StatusBrief(snapshot: snapshot).isChargingWhileHot { active.insert(.chargingWhileHot) }
        if snapshot.thermal.batteryWarningLevel == .hot { active.insert(.sustainedHotBattery) }
        if todayChargeExposure.today.secondsAbove95OnAC >= 2 * 3600 { active.insert(.highSoCDwell) }
        if (100 - snapshot.disk.usedPercent) < 10 { active.insert(.lowStorage) }

        let due = NotificationPolicy.due(
            active: active,
            lastSent: lastNotified,
            now: snapshot.sampledAt,
            quietHours: quietHours,
            calendar: .current
        )
        for notification in due {
            notifier.post(notification)
            lastNotified[notification] = snapshot.sampledAt
        }
    }

    private func recomputeLongevity() {
        let signals = LongevitySignals(
            batteryLongevity: batteryLongevity,
            batteryExposure: todayExposure,
            cpuExposure: todayCPUExposure,
            chargeExposure: todayChargeExposure,
            diskFreePercent: max(0, 100 - snapshot.disk.usedPercent),
            diskUsedPercent: snapshot.disk.usedPercent,
            memoryPressure: snapshot.memory.pressure.rawValue,
            isChargingWhileHot: StatusBrief(snapshot: snapshot).isChargingWhileHot,
            batteryTempC: snapshot.thermal.batteryDisplayC,
            ssdTempC: snapshot.thermal.ssdTemperatureC
        )
        longevityAssessment = LongevityAdvisor.assess(signals)
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
        batteryLongevity = BatteryLongevity.evaluate(history: batteryHealthLog.all())
        let record = BatteryHealthRecord(days: batteryHealthLog.all()).pruned()
        if record != lastSavedHealthRecord {
            lastSavedHealthRecord = record
            Task.detached { [batteryHealthStore] in try? batteryHealthStore.save(record) }
        }
    }

    nonisolated func flushExposureForTermination() async {
        await exposureCoordinator.flushNow(at: Date())
        await chargeCoordinator.flushNow(at: Date())
        await cpuExposureCoordinator.flushNow(at: Date())
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

    private func recentOperationFailureCount() -> Int {
        operationHistoryEntries.filter { $0.status == .failed }.count
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

}
