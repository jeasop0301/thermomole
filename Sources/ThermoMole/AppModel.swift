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
    @Published var lastError: String?
    @Published var todayExposure = ThermalExposureSummary.empty
    @Published var todayChargeExposure = ChargeExposureSummary.empty
    @Published var sinceInstall = SinceInstallExposure.empty
    @Published var batteryHealthSeries: [Double] = []
    @Published var latestBatteryHealth: DailyBatteryHealth?
    @Published var batteryLongevity: BatteryLongevityReport?
    @Published var batteryCalibration: BatteryCalibrationResult = .modeled
    @Published var todayCPUExposure = CPUExposureSummary.empty
    @Published var longevityAssessment = LongevityAssessment(score: 100, factors: [], actions: [])
    @Published var heatPattern = HeatPatternInsight.empty
    @Published var heatHealthInsight = HeatHealthInsight.empty
    @Published var healthProjection = HealthProjectionResult.empty
    @Published var notificationsEnabled = false
    @Published var agingRate: BatteryAgingRate?
    @Published var agingStrain = AgingStrainSummary.empty

    private let provider = NativeSensorProvider()
    private let statusSnapshotStore = StatusSnapshotStore.live
    private let metricsExportStore = MetricsExportStore.live
    private let exposureCoordinator = ThermalExposureCoordinator()
    private let chargeCoordinator = ChargeExposureCoordinator()
    private let cpuExposureCoordinator = CPUExposureCoordinator()
    private let hourlyHeatCoordinator = HourlyHeatCoordinator()
    private let agingStrainCoordinator = AgingStrainCoordinator()
    private let notifier = NotificationCenterClient()
    private var lastNotified: [LongevityNotification: Date] = [:]
    private let quietHours = QuietHours(startHour: 22, endHour: 7)
    private let batteryHealthStore = BatteryHealthStore()
    private var batteryHealthLog = BatteryHealthLog()
    private var lastSavedHealthRecord: BatteryHealthRecord?
    private var timer: Timer?
    private var samplingGate = SamplingGate(timeout: 8)

    private(set) lazy var settings = SettingsModel(
        reportError: { [weak self] message in self?.lastError = message },
        launchStatus: { LaunchAgentStatus(SMAppService.mainApp.status) },
        registerLaunch: { try SMAppService.mainApp.register() },
        unregisterLaunch: { try SMAppService.mainApp.unregister() },
        applyDockVisibility: { visible in
            NSApp.setActivationPolicy(visible ? .regular : .accessory)
            if visible { NSApp.activate(ignoringOtherApps: true) }
        }
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
            await agingStrainCoordinator.bootstrap()
            agingStrain = await agingStrainCoordinator.summary(at: Date(), calendar: .current)
            recomputeCalibration(history: batteryHealthLog.all())
            heatPattern = HeatPatternInsight.build(
                await hourlyHeatCoordinator.grid(endingAt: Date(), calendar: .current)
            )
            todayExposure = await exposureCoordinator.summary(at: Date(), calendar: .current)
            todayChargeExposure = await chargeCoordinator.summary(at: Date(), calendar: .current)
            todayCPUExposure = await cpuExposureCoordinator.summary(at: Date(), calendar: .current)
            await refreshSinceInstall()
            healthProjection = HealthProjection.evaluate(batteryHealthLog.all())
            heatHealthInsight = HeatHealthCorrelation.evaluate(
                thermal: await exposureCoordinator.allDays(),
                health: batteryHealthLog.all()
            )
            recomputeLongevity()
        }
        notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        if notificationsEnabled { notifier.requestAuthorization() }
    }

    func start() {
        refresh()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
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
            await refreshSinceInstall()
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
            // Use the canonical BMS pack temperature (= batteryDisplayC, what AlDente/Apple
            // report and what calendar-aging kinetics are characterized at), NOT the SMC
            // board-thermistor max — feeding that hotter/noisier value into the 2×-per-10°C
            // Arrhenius would systematically over-state aging. The hottest-cell max stays the
            // (conservative) basis for the warning level only.
            agingRate = BatteryAgingRate.evaluate(
                cellTempC: next.thermal.batteryDisplayC,
                socPercent: Double(next.battery.percent),
                isCharging: next.battery.isCharging
            )
            await agingStrainCoordinator.record(
                rawMultiplier: agingRate?.rawMultiplier ?? 1.0,
                at: next.sampledAt,
                calendar: .current
            )
            agingStrain = await agingStrainCoordinator.summary(at: next.sampledAt, calendar: .current)
            recordBatteryHealth(from: next)
            // Machine-readable longevity export for headless/remote Macs. Assembled from the
            // values just computed for THIS sample so it matches the card; uses the snapshot's
            // sampledAt (Core never reads the wall clock). Same fire-and-forget pattern as the
            // snapshot save above.
            let export = FleetMetricsExport.from(
                battery: next.battery,
                agingRate: agingRate,
                calibration: batteryCalibration,
                chargeExposure: todayChargeExposure,
                dailyMaxSoc: next.battery.dailyMaxSoc,
                dailyMinSoc: next.battery.dailyMinSoc,
                batteryTempC: next.thermal.batteryDisplayC,
                nativeChargeLimitAvailable: Self.nativeChargeLimitAvailable,
                appVersion: Self.appVersion,
                generatedAt: next.sampledAt
            )
            Task.detached { [metricsExportStore] in try? metricsExportStore.save(export) }
            heatHealthInsight = HeatHealthCorrelation.evaluate(
                thermal: await exposureCoordinator.allDays(),
                health: batteryHealthLog.all()
            )
            recomputeLongevity()
            evaluateNotifications(for: next)
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
            batteryLongevity: batteryLongevity,
            dailyMaxSoc: snapshot.battery.dailyMaxSoc
        )
        let due = NotificationPolicy.due(
            active: active,
            lastSent: lastNotified,
            now: snapshot.sampledAt,
            quietHours: quietHours,
            calendar: .current
        )
        for notification in due {
            notifier.post(notification, nativeChargeLimitAvailable: Self.nativeChargeLimitAvailable)
            lastNotified[notification] = snapshot.sampledAt
        }
    }

    /// macOS shipped a native Charge Limit toggle in 26.4. Detect it at runtime via the OS version
    /// rather than `#available(macOS 26.4,*)` — the build SDK may not yet know that version. Stable
    /// for the process lifetime, so compute once.
    static let nativeChargeLimitAvailable: Bool = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return (v.majorVersion, v.minorVersion) >= (26, 4)
    }()

    /// Marketing version for the machine-readable metrics export (CFBundleShortVersionString).
    static let appVersion: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"

    /// Assemble the forward-only "since install" exposure totals from both coordinators' cumulatives.
    /// Cheap reads; the cumulative only changes on flush.
    private func refreshSinceInstall() async {
        sinceInstall = SinceInstallExposure.from(
            thermal: await exposureCoordinator.sinceInstall(),
            charge: await chargeCoordinator.sinceInstall()
        )
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
            ssdTempC: snapshot.thermal.ssdTemperatureC,
            dailyMaxSoc: snapshot.battery.dailyMaxSoc,
            nativeChargeLimitAvailable: Self.nativeChargeLimitAvailable
        )
        longevityAssessment = LongevityAdvisor.assess(signals)
    }

    /// Anchor the calendar-aging model to the user's measured capacity fade (un-clamped
    /// maxCapacity/designCapacity trend), removing the cycle-wear share. Stays `.modeled`
    /// until ~8 weeks of data clear the gates.
    private func recomputeCalibration(history: [DailyBatteryHealth]) {
        guard let firstDate = Self.parseDay(history.first?.day) else {
            batteryCalibration = .modeled
            return
        }
        let points: [(day: Double, ratio: Double)] = history.compactMap { d in
            guard d.designCapacityMAh > 0, d.maxCapacityMAh > 0,
                  let date = Self.parseDay(d.day) else { return nil }
            return (day: date.timeIntervalSince(firstDate) / 86_400.0,
                    ratio: Double(d.maxCapacityMAh) / Double(d.designCapacityMAh))
        }
        let cycleWearPerWeek = (batteryLongevity?.cyclesPerWeek)
            .map { $0 * BatteryLongevity.capacityLossPerEFCCentralPct } ?? 0
        batteryCalibration = BatteryCalibration.evaluate(
            points: points,
            strainRatio: agingStrain.ratio30d,
            cycleWearPctPerWeek: cycleWearPerWeek
        )
    }

    private static func parseDay(_ day: String?) -> Date? {
        guard let day else { return nil }
        let p = day.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
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
        recomputeCalibration(history: history)
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
        await agingStrainCoordinator.flushNow(at: Date())
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
}
