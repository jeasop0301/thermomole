import Foundation
import os

/// Owns the pure CPU-exposure tracker + persistence + flush throttle. Mirrors
/// ThermalExposureCoordinator.
public actor CPUExposureCoordinator {
    private var tracker: CPUExposureTracker
    private let store: CPUExposurePersisting
    private let flushInterval: TimeInterval
    private var lastFlushAt: Date?
    public private(set) var lastWriteError: String?
    private(set) var flushCountForTesting = 0

    private static let logger = Logger(subsystem: "com.thermomole", category: "cpu-exposure")

    public init(store: CPUExposurePersisting = CPUExposureStore(), flushInterval: TimeInterval = 60) {
        self.tracker = CPUExposureTracker()
        self.store = store
        self.flushInterval = flushInterval
    }

    public func bootstrap() {
        guard let record = try? store.load() else { return }
        var seeded: [String: DailyCPUExposure] = [:]
        for day in record.days { seeded[day.day] = day }
        tracker = CPUExposureTracker(days: seeded)
    }

    public func record(temperatureC: Double?, at sampledAt: Date, calendar: Calendar) {
        tracker.ingest(temperatureC: temperatureC, at: sampledAt, calendar: calendar)
        if shouldFlush(at: sampledAt) { flush(at: sampledAt) }
    }

    public func summary(at date: Date, calendar: Calendar) -> CPUExposureSummary {
        CPUExposureSummary(
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
        let record = CPUExposureRecord(days: Array(tracker.days.values)).pruned(toDays: 30)
        do {
            try store.save(record)
            lastFlushAt = date
            lastWriteError = nil
            flushCountForTesting += 1
        } catch {
            lastWriteError = error.localizedDescription
            Self.logger.error("cpu-exposure write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
