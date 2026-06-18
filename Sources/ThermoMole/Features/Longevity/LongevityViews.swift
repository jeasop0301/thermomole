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
