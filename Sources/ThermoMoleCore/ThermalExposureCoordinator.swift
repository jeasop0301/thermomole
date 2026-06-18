import Foundation
import os

/// Owns the pure tracker + persistence + flush throttle. Being an actor, overlapping
/// record(...) calls are serialized automatically, and its store I/O runs off the main actor.
public actor ThermalExposureCoordinator {
    private var tracker: ThermalExposureTracker
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
    }

    public func record(temperatureC: Double?, at sampledAt: Date, calendar: Calendar) {
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
        let record = ThermalExposureRecord(days: Array(tracker.days.values)).pruned(toDays: 30)
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
