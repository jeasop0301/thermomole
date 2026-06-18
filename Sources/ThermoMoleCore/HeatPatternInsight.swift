// Sources/ThermoMoleCore/HeatPatternInsight.swift

/// Pure builder: turns an hour-of-day heat grid (oldest → newest days) into a heatmap matrix,
/// a 24-slot weighted hourly profile, and the hottest contiguous window. Gated on >=3 days of data.
///
/// `cells` and `hourlyProfile` are always populated (slots may be nil for hours without data);
/// only `hottestWindow` is nil when `hasEnoughData == false`.
public struct HeatPatternInsight: Equatable, Sendable {
    public struct HottestWindow: Equatable, Sendable {
        public var startHour: Int
        public var endHour: Int
        public var meanC: Double
        public init(startHour: Int, endHour: Int, meanC: Double) {
            self.startHour = startHour; self.endHour = endHour; self.meanC = meanC
        }
    }

    public var cells: [[Double?]]        // rows = days (old→new), cols = 24 hours (meanC or nil)
    public var hourlyProfile: [Double?]  // 24 weighted means across the whole grid
    public var hottestWindow: HottestWindow?
    public var hasEnoughData: Bool

    public init(cells: [[Double?]], hourlyProfile: [Double?], hottestWindow: HottestWindow?, hasEnoughData: Bool) {
        self.cells = cells
        self.hourlyProfile = hourlyProfile
        self.hottestWindow = hottestWindow
        self.hasEnoughData = hasEnoughData
    }

    public static let empty = HeatPatternInsight(
        cells: [],
        hourlyProfile: Array(repeating: nil, count: 24),
        hottestWindow: nil,
        hasEnoughData: false
    )

    public static func build(_ grid: [DailyHourlyHeat]) -> HeatPatternInsight {
        let cells = grid.map { day in day.hours.map { $0.meanC } }

        var sum = [Double](repeating: 0, count: 24)
        var cnt = [Int](repeating: 0, count: 24)
        for day in grid {
            for h in 0..<24 {
                sum[h] += day.hours[h].sumC
                cnt[h] += day.hours[h].count
            }
        }
        let profile: [Double?] = (0..<24).map { cnt[$0] > 0 ? sum[$0] / Double(cnt[$0]) : nil }

        let daysWithData = grid.filter { day in day.hours.contains { $0.count > 0 } }.count
        let hasEnough = daysWithData >= 3

        var window: HottestWindow?
        // Ties resolve to the earliest hour (Array.max keeps the first max).
        if hasEnough,
           let peak = (0..<24).compactMap({ h in profile[h].map { (hour: h, mean: $0) } }).max(by: { $0.mean < $1.mean }) {
            var start = peak.hour, end = peak.hour
            while start - 1 >= 0, let m = profile[start - 1], peak.mean - m <= 1.0 { start -= 1 }
            while end + 1 < 24, let m = profile[end + 1], peak.mean - m <= 1.0 { end += 1 }
            var ws = 0.0, wc = 0
            for day in grid { for h in start...end { ws += day.hours[h].sumC; wc += day.hours[h].count } }
            window = HottestWindow(startHour: start, endHour: end, meanC: wc > 0 ? ws / Double(wc) : peak.mean)
        }

        return HeatPatternInsight(cells: cells, hourlyProfile: profile, hottestWindow: window, hasEnoughData: hasEnough)
    }
}
