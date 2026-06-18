import Foundation
import os

public struct AgingStrainSummary: Equatable, Sendable {
    public var today: DailyAgingStrain
    public var ratio7d: Double
    public var extraAgingDays7d: Double
    public var ratio30d: Double
    /// Per-day strain ratios for the last 7 days, oldest→newest.
    /// ratio = effectiveSeconds / calendarSeconds if calendarSeconds > 0, else 1.0.
    /// Carries RATIOS only — not a capacity measurement.
    public var recent7: [Double]
    /// True if any of the last 7 days have calendarSeconds > 0.
    public var hasData: Bool

    public init(
        today: DailyAgingStrain,
        ratio7d: Double,
        extraAgingDays7d: Double,
        ratio30d: Double,
        recent7: [Double] = [],
        hasData: Bool = false
    ) {
        self.today = today
        self.ratio7d = ratio7d
        self.extraAgingDays7d = extraAgingDays7d
        self.ratio30d = ratio30d
        self.recent7 = recent7
        self.hasData = hasData
    }

    public static let empty = AgingStrainSummary(
        today: .empty(day: ""),
        ratio7d: 1.0,
        extraAgingDays7d: 0,
        ratio30d: 1.0,
        recent7: [],
        hasData: false
    )
}

/// Owns the pure tracker + persistence + flush throttle.
public actor AgingStrainCoordinator {
    private var tracker: AgingStrainTracker
    private let store: AgingStrainPersisting
    private let flushInterval: TimeInterval
    private var lastFlushAt: Date?
    public private(set) var lastWriteError: String?
    private(set) var flushCountForTesting = 0

    private static let logger = Logger(subsystem: "com.thermomole", category: "aging-strain")

    public init(store: AgingStrainPersisting = AgingStrainStore(), flushInterval: TimeInterval = 60) {
        self.tracker = AgingStrainTracker()
        self.store = store
        self.flushInterval = flushInterval
    }

    public func bootstrap() {
        guard let record = try? store.load() else { return }
        var seeded: [String: DailyAgingStrain] = [:]
        for day in record.days { seeded[day.day] = day }
        tracker = AgingStrainTracker(days: seeded)
    }

    public func record(rawMultiplier: Double, at sampledAt: Date, calendar: Calendar) {
        tracker.ingest(rawMultiplier: rawMultiplier, at: sampledAt, calendar: calendar)
        if shouldFlush(at: sampledAt) { flush(at: sampledAt) }
    }

    public func summary(at date: Date, calendar: Calendar) -> AgingStrainSummary {
        let window7 = tracker.recentDays(7, endingAt: date, calendar: calendar)
        let window30 = tracker.recentDays(30, endingAt: date, calendar: calendar)
        // recentDays returns newest-first; sort by day key (yyyy-MM-dd) to get oldest→newest.
        let sorted7 = window7.sorted { $0.day < $1.day }
        let recent7 = sorted7.map { d -> Double in
            d.calendarSeconds > 0 ? d.effectiveSeconds / d.calendarSeconds : 1.0
        }
        let hasData = window7.contains { $0.calendarSeconds > 0 }
        return AgingStrainSummary(
            today: tracker.today(at: date, calendar: calendar),
            ratio7d: strainRatio(over: window7),
            extraAgingDays7d: extraAgingDays(over: window7),
            ratio30d: strainRatio(over: window30),
            recent7: recent7,
            hasData: hasData
        )
    }

    public func flushNow(at date: Date) { flush(at: date) }

    // MARK: - Private

    private func shouldFlush(at date: Date) -> Bool {
        guard let last = lastFlushAt else { return true }
        return date.timeIntervalSince(last) >= flushInterval
    }

    private func flush(at date: Date) {
        let record = AgingStrainRecord(days: Array(tracker.days.values)).pruned(toDays: 30)
        do {
            try store.save(record)
            lastFlushAt = date
            lastWriteError = nil
            flushCountForTesting += 1
        } catch {
            lastWriteError = error.localizedDescription
            Self.logger.error("aging-strain write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func strainRatio(over days: [DailyAgingStrain]) -> Double {
        let sumCal = days.reduce(0) { $0 + $1.calendarSeconds }
        guard sumCal > 0 else { return 1.0 }
        let sumEff = days.reduce(0) { $0 + $1.effectiveSeconds }
        return sumEff / sumCal
    }

    private func extraAgingDays(over days: [DailyAgingStrain]) -> Double {
        let sumCal = days.reduce(0) { $0 + $1.calendarSeconds }
        let sumEff = days.reduce(0) { $0 + $1.effectiveSeconds }
        return (sumEff - sumCal) / 86400
    }
}
