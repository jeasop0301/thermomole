import Foundation
import Combine
import SwiftUI
import AppKit
import ServiceManagement
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
    @Published var heatPattern = HeatPatternInsight.empty
    @Published var heatHealthInsight = HeatHealthInsight.empty
    @Published var healthProjection = HealthProjectionResult.empty
    @Published var notificationsEnabled = false

    private let provider = NativeSensorProvider()
    private let historyStore = OperationHistoryStore.live
    private let statusSnapshotStore = StatusSnapshotStore.live
    private let exposureCoordinator = ThermalExposureCoordinator()
    private let chargeCoordinator = ChargeExposureCoordinator()
    private let cpuExposureCoordinator = CPUExposureCoordinator()
    private let hourlyHeatCoordinator = HourlyHeatCoordinator()
    private let notifier = NotificationCenterClient()
    private var lastNotified: [LongevityNotification: Date] = [:]
    private let quietHours = QuietHours(startHour: 22, endHour: 7)
    private let batteryHealthStore = BatteryHealthStore()
    private var batteryHealthLog = BatteryHealthLog()
    private var lastSavedHealthRecord: BatteryHealthRecord?
    private var timer: Timer?
    private var doctorFreshnessTimer: Timer?
    private var samplingGate = SamplingGate(timeout: 8)

    private(set) lazy var settings = SettingsModel(
        currentSnapshot: { [weak self] in self?.snapshot ?? .placeholder },
        currentDoctorReport: { [weak self] in self?.doctorReport ?? DoctorReport.make(inputs: .placeholder) },
        currentHistory: { [weak self] in self?.operationHistoryEntries ?? [] },
        reportError: { [weak self] message in self?.lastError = message },
        launchStatus: { LaunchAgentStatus(SMAppService.mainApp.status) },
        registerLaunch: { try SMAppService.mainApp.register() },
        unregisterLaunch: { try SMAppService.mainApp.unregister() },
        applyDockVisibility: { visible in
            NSApp.setActivationPolicy(visible ? .regular : .accessory)
            if visible { NSApp.activate(ignoringOtherApps: true) }
        },
        writeReport: { try DiagnosticReportStore().write($0, to: $1) },
        readReport: { try DiagnosticReportStore().read(from: $0) }
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
            await hourlyHeatCoordinator.bootstrap()
            heatPattern = HeatPatternInsight.build(
                await hourlyHeatCoordinator.grid(endingAt: Date(), calendar: .current)
            )
            todayExposure = await exposureCoordinator.summary(at: Date(), calendar: .current)
            todayChargeExposure = await chargeCoordinator.summary(at: Date(), calendar: .current)
            todayCPUExposure = await cpuExposureCoordinator.summary(at: Date(), calendar: .current)
            healthProjection = HealthProjection.evaluate(batteryHealthLog.all())
            heatHealthInsight = HeatHealthCorrelation.evaluate(
                thermal: await exposureCoordinator.allDays(),
                health: batteryHealthLog.all()
            )
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
            await hourlyHeatCoordinator.record(
                temperatureC: next.thermal.batteryDisplayC,
                at: next.sampledAt,
                calendar: .current
            )
            heatPattern = HeatPatternInsight.build(
                await hourlyHeatCoordinator.grid(endingAt: next.sampledAt, calendar: .current)
            )
            recordBatteryHealth(from: next)
            heatHealthInsight = HeatHealthCorrelation.evaluate(
                thermal: await exposureCoordinator.allDays(),
                health: batteryHealthLog.all()
            )
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
        let active = NotificationPolicy.activeNotifications(
            snapshot: snapshot,
            todayChargeExposure: todayChargeExposure,
            todayCPUExposure: todayCPUExposure,
            batteryLongevity: batteryLongevity
        )
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
        let history = batteryHealthLog.all()
        batteryHealthSeries = batteryHealthLog.healthSeries()
        latestBatteryHealth = batteryHealthLog.latest
        batteryLongevity = BatteryLongevity.evaluate(history: history)
        healthProjection = HealthProjection.evaluate(history)
        let record = BatteryHealthRecord(days: history).pruned()
        if record != lastSavedHealthRecord {
            lastSavedHealthRecord = record
            Task.detached { [batteryHealthStore] in try? batteryHealthStore.save(record) }
        }
    }

    nonisolated func flushExposureForTermination() async {
        await exposureCoordinator.flushNow(at: Date())
        await chargeCoordinator.flushNow(at: Date())
        await cpuExposureCoordinator.flushNow(at: Date())
        await hourlyHeatCoordinator.flushNow(at: Date())
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
