import SwiftUI
import ThermoMoleCore

struct LongevityTab: View {
    @ObservedObject var model: AppModel

    private var assessment: LongevityAssessment { model.longevityAssessment }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TabHeader(subtitle: "What's helping and what's hurting your Mac's lifespan.") {}

                HStack(alignment: .center, spacing: 18) {
                    LongevityScoreRing(score: assessment.score, tint: scoreTint)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(verdictTitle)
                            .font(.system(.title2, design: .rounded).weight(.semibold))
                        Text(verdictDetail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                }
                .padding(18)
                .softPanel()

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                    ForEach(assessment.factors) { factor in
                        LongevityFactorCard(factor: factor)
                    }
                }

                LongevityActionsCard(actions: assessment.actions)
                LongevityInsightsSection(model: model)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var scoreTint: Color {
        if assessment.score >= 85 { return Color.leafAccent }
        if assessment.score >= 65 { return Color.amberAccent }
        return .red
    }

    private var verdictTitle: String {
        if assessment.score >= 85 { return "In great shape" }
        if assessment.score >= 65 { return "Doing okay" }
        return "Needs attention"
    }

    private var verdictDetail: String {
        if assessment.score >= 85 { return "Keep doing what you're doing — heat, charge, and storage all look healthy." }
        if assessment.score >= 65 { return "A few habits below could extend your Mac's life." }
        return "Address the flagged items to slow aging."
    }
}

struct LongevityScoreRing: View {
    let score: Int
    let tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color.insetFill, lineWidth: 11)
            Circle()
                .trim(from: 0, to: max(0.02, CGFloat(score) / 100))
                .stroke(tint, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text("\(score)")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary)
                    .monospacedDigit()
                Text("/ 100").font(.thermoCaption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 118, height: 118)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Longevity score \(score) of 100")
    }
}

struct LongevityFactorCard: View {
    let factor: LongevityFactor

    private var tint: Color {
        switch factor.status {
        case .good: Color.leafAccent
        case .watch: Color.amberAccent
        case .poor: .red
        }
    }

    private var statusWord: String {
        switch factor.status {
        case .good: "Good"
        case .watch: "Watch"
        case .poor: "Attention"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(factor.title)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(statusWord)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.14))
                    .clipShape(Capsule())
            }
            Text(factor.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .softPanel()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(factor.title): \(statusWord)"))
        .accessibilityValue(Text(factor.summary))
    }
}

struct LongevityActionsCard: View {
    let actions: [LongevityAction]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommended actions").font(.headline)
            if actions.isEmpty {
                Label("You're all set — nothing to do right now.", systemImage: "checkmark.seal.fill")
                    .font(.callout)
                    .foregroundStyle(Color.leafAccent)
            } else {
                ForEach(actions) { action in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: symbol(action.severity))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(tint(action.severity))
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title).font(.callout.weight(.medium))
                            Text(action.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .softPanel()
    }

    private func symbol(_ s: LongevityActionSeverity) -> String {
        switch s {
        case .urgent: "exclamationmark.triangle.fill"
        case .suggest: "lightbulb.fill"
        case .info: "info.circle.fill"
        }
    }

    private func tint(_ s: LongevityActionSeverity) -> Color {
        switch s {
        case .urgent: .red
        case .suggest: Color.amberAccent
        case .info: Color.thermoAccent
        }
    }
}

// MARK: - Heat pattern

/// Maps a mean battery temp to a cool→amber(35°)→red(40°) fill; nil = no data.
private func heatCellColor(_ meanC: Double?) -> Color {
    guard let t = meanC else { return Color.insetFill }
    let caution = ThermalThresholds.batteryCautionC // 35
    let hot = ThermalThresholds.batteryHotC         // 40
    if t <= caution - 8 { return Color.oceanAccent.opacity(0.25) }
    if t < caution {
        let f = (t - (caution - 8)) / 8                       // 0..1 across 27..35
        return Color.oceanAccent.opacity(0.25 + 0.35 * f)
    }
    if t < hot {
        let f = (t - caution) / (hot - caution)               // 0..1 across 35..40
        return Color.amberAccent.opacity(0.5 + 0.45 * f)
    }
    return Color.red.opacity(0.9)
}

struct HourHeatmapGrid: View {
    let cells: [[Double?]]   // rows = days (old→new), cols = 24 hours

    private let tickHours = [0, 6, 12, 18]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            VStack(spacing: 2) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 2) {
                        ForEach(0..<24, id: \.self) { h in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(heatCellColor(h < row.count ? row[h] : nil))
                                .frame(height: 10)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            HStack(spacing: 2) {
                ForEach(0..<24, id: \.self) { h in
                    Text(tickHours.contains(h) ? "\(h)" : "")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery heat by hour of day over recent days")
    }
}

/// 24 vertical bars (one per hour) whose height encodes the hour's mean battery temp,
/// colored on the same scale as the heatmap. Complements the day×hour grid with the
/// aggregate hour-of-day shape. nil hours render as a minimal stub.
struct HourProfileBars: View {
    let profile: [Double?]   // 24 hourly weighted-mean temps (nil = no data)

    var body: some View {
        let vals = profile.compactMap { $0 }
        let lo = vals.min() ?? 0
        let hi = vals.max() ?? 1
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<24, id: \.self) { h in
                RoundedRectangle(cornerRadius: 1)
                    .fill(heatCellColor(h < profile.count ? profile[h] : nil))
                    .frame(maxWidth: .infinity)
                    .frame(height: barHeight(h < profile.count ? profile[h] : nil, lo: lo, hi: hi))
            }
        }
        .frame(height: 26)
        .accessibilityHidden(true)
    }

    private func barHeight(_ v: Double?, lo: Double, hi: Double) -> CGFloat {
        guard let v else { return 2 }            // no data: minimal stub
        guard hi > lo else { return 14 }          // all equal: mid height
        let f = (v - lo) / (hi - lo)
        return 3 + CGFloat(max(0, min(1, f))) * 23
    }
}

struct HeatPatternCard: View {
    let insight: HeatPatternInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(Color.amberAccent)
                Text("When it runs hot").font(.callout.weight(.semibold))
                Spacer()
            }
            if insight.hasEnoughData {
                if let w = insight.hottestWindow {
                    Text("Hottest hours: \(hourRange(w.startHour, w.endHour)) · avg \(Int(w.meanC.rounded()))°")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HourHeatmapGrid(cells: insight.cells)
                HourProfileBars(profile: insight.hourlyProfile)
            } else {
                Text("Collecting data… patterns appear after a few days of use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .softPanel()
    }

    private func hourRange(_ start: Int, _ end: Int) -> String {
        start == end ? hour12(start) : "\(hour12(start))–\(hour12(end))"
    }
    private func hour12(_ h: Int) -> String {
        let period = h < 12 ? "AM" : "PM"
        let h12 = h % 12 == 0 ? 12 : h % 12
        return "\(h12) \(period)"
    }
}

// MARK: - Heat vs health correlation

struct HeatHealthCorrelationCard: View {
    let insight: HeatHealthInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "thermometer.variable.and.figure")
                    .foregroundStyle(Color.oceanAccent)
                Text("Heat vs battery health").font(.callout.weight(.semibold))
                Spacer()
            }
            switch insight.verdict {
            case .insufficientData:
                Text("Collecting data… (warm \(insight.warmDays) · cool \(insight.coolDays) days)")
                    .font(.caption).foregroundStyle(.secondary)
            case .warmFadesFaster, .noClearDifference:
                HStack(spacing: 18) {
                    fadeStat("Warm days", insight.warmFadePerWeek)
                    fadeStat("Cool days", insight.coolFadePerWeek)
                }
                Text(insight.verdict == .warmFadesFaster
                     ? "Health fades faster on warmer days. Observed link, not proof — keeping cool helps."
                     : "No clear difference yet between warm and cool days.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .softPanel()
    }

    private func fadeStat(_ title: String, _ perWeek: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(perWeek.map { String(format: "−%.1f%%/wk", max(0, $0)) } ?? "--")
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .monospacedDigit()
        }
    }
}

// MARK: - Health projection

struct HealthProjectionChart: View {
    let points: [HealthProjectionResult.Point]   // monthOffset ascending

    private func px(_ m: Int, width: CGFloat, maxMonth: Int) -> CGFloat {
        CGFloat(Double(m) / Double(maxMonth)) * width
    }

    private func py(_ v: Double, height: CGFloat, yMin: Double, yMax: Double) -> CGFloat {
        height - CGFloat((v - yMin) / (yMax - yMin)) * height
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let maxMonth = max(1, points.last?.monthOffset ?? 1)
            let lo = (points.map { $0.low }.min() ?? 80)
            let yMin = min(80, lo) - 2
            let yMax = 100.0

            ZStack {
                // band (low..high)
                Path { p in
                    guard let f = points.first else { return }
                    p.move(to: CGPoint(x: px(f.monthOffset, width: w, maxMonth: maxMonth), y: py(f.high, height: h, yMin: yMin, yMax: yMax)))
                    for pt in points { p.addLine(to: CGPoint(x: px(pt.monthOffset, width: w, maxMonth: maxMonth), y: py(pt.high, height: h, yMin: yMin, yMax: yMax))) }
                    for pt in points.reversed() { p.addLine(to: CGPoint(x: px(pt.monthOffset, width: w, maxMonth: maxMonth), y: py(pt.low, height: h, yMin: yMin, yMax: yMax))) }
                    p.closeSubpath()
                }
                .fill(Color.oceanAccent.opacity(0.18))

                // central dashed
                Path { p in
                    guard let f = points.first else { return }
                    p.move(to: CGPoint(x: px(f.monthOffset, width: w, maxMonth: maxMonth), y: py(f.central, height: h, yMin: yMin, yMax: yMax)))
                    for pt in points { p.addLine(to: CGPoint(x: px(pt.monthOffset, width: w, maxMonth: maxMonth), y: py(pt.central, height: h, yMin: yMin, yMax: yMax))) }
                }
                .stroke(Color.oceanAccent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))

                // 80% reference
                Path { p in
                    p.move(to: CGPoint(x: 0, y: py(80, height: h, yMin: yMin, yMax: yMax)))
                    p.addLine(to: CGPoint(x: w, y: py(80, height: h, yMin: yMin, yMax: yMax)))
                }
                .stroke(Color.red.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
        }
        .frame(height: 80)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Projected battery health over the next months")
    }
}

struct LongevityInsightsSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Insights").font(.headline)
            HeatPatternCard(insight: model.heatPattern)
            HeatHealthCorrelationCard(insight: model.heatHealthInsight)
            HealthProjectionCard(result: model.healthProjection)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HealthProjectionCard: View {
    let result: HealthProjectionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.downtrend.xyaxis")
                    .foregroundStyle(Color.oceanAccent)
                Text("Health outlook").font(.callout.weight(.semibold))
                Spacer()
                if let r = result.monthsTo80Range {
                    Text("80% in \(Int(r.min.rounded()))–\(Int(r.max.rounded())) mo")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            switch result.status {
            case .insufficient:
                Text("Collecting data… a trend appears after ~2 weeks of readings.")
                    .font(.caption).foregroundStyle(.secondary)
            case .flat:
                Text("No meaningful decline at the current trend — battery health is holding steady.")
                    .font(.caption).foregroundStyle(.secondary)
            case .projecting:
                HealthProjectionChart(points: result.points)
                Text("Range spans your recent vs long-term fade rate.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .softPanel()
    }
}
