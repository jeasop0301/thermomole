import Foundation
import os

/// Owns the pure tracker + persistence + flush throttle. Being an actor, overlapping
/// record(...) calls are serialized automatically, and its store I/O runs off the main actor.
public actor ThermalExposureCoordinator {
    private var tracker: ThermalExposureTracker
    private var cumulative = CumulativeThermalExposure()  // forward-only since-install totals
    private var calendar = Calendar.current              // last recording calendar (for flush day-key)
    private let store: ThermalExposurePersisting
    private let flushInterval: TimeInterval
    private var lastFlushAt: Date?
    public private(set) var lastWriteError: String?
    private(set) var flushCountForTesting = 0

    private static let logger = Logger(subsystem: "com.thermomole", category: "exposure")

    public init(store: ThermalExposurePersisting = ThermalExposureStore(), flushInterval: TimeInterval = 60) {
        self.tracker = ThermalExposureTracker()
        self.store = store
        self.flushInterval = flushInterval
    }

    public func bootstrap() {
        guard let record = try? store.load() else { return }
        // Old 35/40 data is incompatible with new 40/45 bands — start fresh.
        guard record.schemaVersion >= 2 else { return }
        var seeded: [String: DailyThermalExposure] = [:]
        for day in record.days { seeded[day.day] = day }
        tracker = ThermalExposureTracker(days: seeded)
        cumulative = record.cumulative  // empty for pre-cumulative v2; populated for v3+
    }

    /// Forward-only since-install thermal totals (seconds). Combined with the charge side into
    /// the user-facing SinceInstallExposure by AppModel.
    public func sinceInstall() -> CumulativeThermalExposure { cumulative }

    public func record(temperatureC: Double?, at sampledAt: Date, calendar: Calendar) {
        self.calendar = calendar
        tracker.ingest(temperatureC: temperatureC, at: sampledAt, calendar: calendar)
        if shouldFlush(at: sampledAt) { flush(at: sampledAt) }
    }

    public func summary(at date: Date, calendar: Calendar) -> ThermalExposureSummary {
        ThermalExposureSummary(
            today: tracker.today(at: date, calendar: calendar),
            recent: tracker.recentDays(7, endingAt: date, calendar: calendar)
        )
    }

    /// Every tracked day (unordered). Used by cross-store insights (heat-vs-health correlation).
    public func allDays() -> [DailyThermalExposure] {
        Array(tracker.days.values)
    }

    public func flushNow(at date: Date) { flush(at: date) }

    private func shouldFlush(at date: Date) -> Bool {
        guard let last = lastFlushAt else { return true }
        return date.timeIntervalSince(last) >= flushInterval
    }

    private func flush(at date: Date) {
        // Fold completed days into the since-install cumulative on the FULL day set BEFORE pruning,
        // so days about to be dropped are captured. Then persist the pruned days + intact cumulative.
        let allDays = Array(tracker.days.values)
        let today = ThermalExposureTracker.dayKey(for: date, calendar: calendar)
        cumulative = cumulative.accumulating(days: allDays, today: today)
        let record = ThermalExposureRecord(days: allDays, cumulative: cumulative).pruned(toDays: 30)
        do {
            try store.save(record)
            lastFlushAt = date
            lastWriteError = nil
            flushCountForTesting += 1
        } catch {
            lastWriteError = error.localizedDescription
            Self.logger.error("thermal-exposure write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
