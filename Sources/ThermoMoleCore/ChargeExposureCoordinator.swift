import Foundation
import os

/// Owns the pure SoC-dwell tracker + persistence + flush throttle. As an actor, overlapping
/// record(...) calls serialize automatically and store I/O runs off the main actor.
/// Mirrors ThermalExposureCoordinator.
public actor ChargeExposureCoordinator {
    private var tracker: ChargeExposureTracker
    private var cumulative = CumulativeChargeExposure()  // forward-only since-install totals
    private var calendar = Calendar.current             // last recording calendar (for flush day-key)
    private let store: ChargeExposurePersisting
    private let flushInterval: TimeInterval
    private var lastFlushAt: Date?
    public private(set) var lastWriteError: String?
    private(set) var flushCountForTesting = 0

    private static let logger = Logger(subsystem: "com.thermomole", category: "charge-exposure")

    public init(store: ChargeExposurePersisting = ChargeExposureStore(), flushInterval: TimeInterval = 60) {
        self.tracker = ChargeExposureTracker()
        self.store = store
        self.flushInterval = flushInterval
    }

    public func bootstrap() {
        guard let record = try? store.load() else { return }
        var seeded: [String: DailyChargeExposure] = [:]
        for day in record.days { seeded[day.day] = day }
        tracker = ChargeExposureTracker(days: seeded)
        cumulative = record.cumulative
    }

    /// Forward-only since-install high-SoC totals (seconds). Combined with the thermal side into
    /// the user-facing SinceInstallExposure by AppModel.
    public func sinceInstall() -> CumulativeChargeExposure { cumulative }

    public func record(percent: Int, isOnACPower: Bool, at sampledAt: Date, calendar: Calendar) {
        self.calendar = calendar
        tracker.ingest(percent: percent, isOnACPower: isOnACPower, at: sampledAt, calendar: calendar)
        if shouldFlush(at: sampledAt) { flush(at: sampledAt) }
    }

    public func summary(at date: Date, calendar: Calendar) -> ChargeExposureSummary {
        ChargeExposureSummary(
            today: tracker.today(at: date, calendar: calendar),
            recent: tracker.recentDays(7, endingAt: date, calendar: calendar)
        )
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
        let today = ChargeExposureTracker.dayKey(for: date, calendar: calendar)
        cumulative = cumulative.accumulating(days: allDays, today: today)
        let record = ChargeExposureRecord(days: allDays, cumulative: cumulative).pruned(toDays: 30)
        do {
            try store.save(record)
            lastFlushAt = date
            lastWriteError = nil
            flushCountForTesting += 1
        } catch {
            lastWriteError = error.localizedDescription
            Self.logger.error("charge-exposure write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
