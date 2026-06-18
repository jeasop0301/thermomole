import Foundation
import os

/// Owns the pure tracker + persistence + flush throttle. Mirrors ThermalExposureCoordinator:
/// overlapping record(...) calls serialize, store I/O runs off the main actor.
public actor HourlyHeatCoordinator {
    private var tracker: HourlyHeatTracker
    private let store: HourlyHeatPersisting
    private let flushInterval: TimeInterval
    private var lastFlushAt: Date?
    public private(set) var lastWriteError: String?
    private(set) var flushCountForTesting = 0

    private static let logger = Logger(subsystem: "com.thermomole", category: "hourlyheat")

    public init(store: HourlyHeatPersisting = HourlyHeatStore(), flushInterval: TimeInterval = 60) {
        self.tracker = HourlyHeatTracker()
        self.store = store
        self.flushInterval = flushInterval
    }

    public func bootstrap() {
        guard let record = try? store.load() else { return }
        var seeded: [String: DailyHourlyHeat] = [:]
        for day in record.days { seeded[day.day] = day }
        tracker = HourlyHeatTracker(days: seeded)
    }

    public func record(temperatureC: Double?, at sampledAt: Date, calendar: Calendar) {
        tracker.ingest(temperatureC: temperatureC, at: sampledAt, calendar: calendar)
        if shouldFlush(at: sampledAt) { flush(at: sampledAt) }
    }

    public func grid(maxDays: Int = 14, endingAt date: Date, calendar: Calendar) -> [DailyHourlyHeat] {
        tracker.recentDays(maxDays, endingAt: date, calendar: calendar)
    }

    public func flushNow(at date: Date) { flush(at: date) }

    private func shouldFlush(at date: Date) -> Bool {
        guard let last = lastFlushAt else { return true }
        return date.timeIntervalSince(last) >= flushInterval
    }

    private func flush(at date: Date) {
        let record = HourlyHeatRecord(days: Array(tracker.days.values)).pruned(toDays: 30)
        do {
            try store.save(record)
            lastFlushAt = date
            lastWriteError = nil
            flushCountForTesting += 1
        } catch {
            lastWriteError = error.localizedDescription
            Self.logger.error("hourly-heat write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
