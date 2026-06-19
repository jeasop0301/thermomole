import SwiftUI
import AppKit
import ThermoMoleCore

// MARK: - PatinaAgingCard
//
// The Dark Jewel aging card. Lives in the menu-bar popover (see PopoverViews).
// Fixed 392pt content width — matches the Claude Design spec and the popover box.

struct PatinaAgingCard: View {
    @ObservedObject var model: AppModel
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // 1. Header
            PatinaHeader(statusColor: Color.agingWarmth(model.agingRate?.multiplier ?? 1.0))
                .padding(.bottom, 22)

            // 2. Aging hero
            AgingHeroSection(rate: model.agingRate, snapshot: model.snapshot)
                .padding(.bottom, 22)

            // 3. Drivers
            hairline
            DriversRow(snapshot: model.snapshot)
                .padding(.top, 14)
                .padding(.bottom, 22)

            // 4. Strain
            hairline
            StrainSection(strain: model.agingStrain)
                .padding(.top, 14)
                .padding(.bottom, 18)

            // 5. Outlook
            OutlookLine(projection: model.healthProjection)
                .padding(.bottom, 18)

            // 6. Action chip
            if let action = model.longevityAssessment.actions.first {
                ActionChip(action: action)
                    .padding(.bottom, 18)
            }

            // 7. Details expander
            hairline
            DetailsToggleRow(showDetails: $showDetails)
                .padding(.bottom, showDetails ? 14 : 0)

            if showDetails {
                // Bound the (long) details so the auto-sized popover can't grow past the
                // screen and clip the score/factors off the bottom — scroll within instead.
                ScrollView { DetailsContent(model: model) }
                    .frame(height: detailsViewportHeight)
            }
        }
        .padding(24)
        .frame(width: 392, alignment: .leading)
        .background(Color.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.subtleStroke, lineWidth: 1))
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.subtleStroke)
            .frame(height: 1)
    }

    /// Cap the expanded details to what fits under the menu bar on the current screen,
    /// leaving room for the collapsed card + footer. DetailsContent is longer than this,
    /// so it always scrolls — no wasted space.
    private var detailsViewportHeight: CGFloat {
        let screenH = NSScreen.main?.visibleFrame.height ?? 900
        return max(220, min(380, screenH - 760))
    }
}

// MARK: - 1. Header

private struct PatinaHeader: View {
    /// Live aging-state tint (cream / amber / garnet) — a small status light, not décor,
    /// so amber stays strictly semantic and never doubles as a brand accent.
    let statusColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Text("Patina")
                    .font(.patinaDisplay(26, .semibold))
                    .foregroundStyle(Color.textPrimary)
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Spacer()
            }
            Text("See your battery age, honestly.")
                .font(.patinaBody(13))
                .foregroundStyle(Color.textSecondary)
        }
    }
}

// MARK: - 2. Aging Hero

private struct AgingHeroSection: View {
    let rate: BatteryAgingRate?
    let snapshot: SystemSnapshot

    private var multiplier: Double { rate?.multiplier ?? 1.0 }
    /// Cold-charge plating risk dominates the calendar rate, which floors to ~1.0×.
    /// Tint the hero garnet so the number agrees with the plating caution below
    /// instead of reading as a calm "ideal".
    private var warmth: Color {
        rate?.coldChargeCaution == true ? Color.garnetAccent : Color.agingWarmth(multiplier)
    }

    private var formattedNumber: String {
        guard let rate else { return "" }
        let m = rate.multiplier
        return m >= 10 ? "\(Int(m.rounded()))" : String(format: "%.1f", m)
    }

    private var driverLine: String {
        guard let rate else { return "" }
        // Driver attribution only makes sense once aging is actually elevated;
        // at the low band the multiplier is ~1.0× so naming a "main driver" misleads.
        if rate.band == .low { return "Aging at the ideal idle rate" }
        switch rate.dominantDriver {
        case .temperature: return "Heat is the main driver right now"
        case .charge: return "High charge is the main driver right now"
        case .balanced: return "High charge + heat"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AGING SPEED NOW")
                .font(.patinaBody(11, .semibold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(Color.textTertiary)
                .padding(.bottom, 10)

            if rate == nil {
                Text("Collecting…")
                    .font(.patinaBody(15))
                    .foregroundStyle(Color.textSecondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    // "≈ " prefix
                    Text("≈ ")
                        .font(.patinaDisplay(40, .medium))
                        .foregroundStyle(warmth)

                    // Hero numeral
                    Text(formattedNumber)
                        .font(.patinaDisplay(86, .medium))
                        .foregroundStyle(warmth)
                        .shadow(color: warmth.opacity(0.5), radius: 10)
                        .monospacedDigit()

                    // "×" suffix
                    Text("×")
                        .font(.patinaDisplay(40, .medium))
                        .foregroundStyle(warmth)

                    // Companion arc
                    CompanionArc(color: warmth)
                        .frame(width: 48, height: 80)
                        .padding(.leading, 14)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Aging speed now: about \(formattedNumber) times an ideal idle"))

                Text("aging vs an ideal idle (25° / 50%)")
                    .font(.patinaBody(12))
                    .foregroundStyle(Color.textTertiary)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                HStack(spacing: 7) {
                    Circle()
                        .fill(warmth)
                        .frame(width: 7, height: 7)
                    Text(driverLine)
                        .font(.patinaBody(13))
                        .foregroundStyle(Color.textSecondary)
                }

                if rate?.coldChargeCaution == true {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(Color.garnetAccent)
                            .frame(width: 7, height: 7)
                        Text("Charging while cold — risk of lithium plating")
                            .font(.patinaBody(13))
                            .foregroundStyle(Color.garnetAccent)
                    }
                    .padding(.top, 4)
                }
            }

            Text("Relative estimate from published kinetics — not a capacity measurement.")
                .font(.patinaBody(11))
                .foregroundStyle(Color.textTertiary)
                .padding(.top, 10)
        }
        .padding(EdgeInsets(top: 22, leading: 22, bottom: 20, trailing: 22))
        .heroPanel()
    }
}

/// Decorative arc beside the hero number — purely visual, not a progress gauge.
private struct CompanionArc: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let r: CGFloat = min(w, h) * 0.45
            let cx = w * 0.12, cy = h * 0.5
            Path { p in
                p.addArc(
                    center: CGPoint(x: cx, y: cy),
                    radius: r,
                    startAngle: .degrees(240),
                    endAngle: .degrees(120),
                    clockwise: false
                )
            }
            .stroke(color.opacity(0.30), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 3. Drivers Row

private struct DriversRow: View {
    let snapshot: SystemSnapshot

    private var hottestC: Double? {
        let candidates: [Double?] = [
            snapshot.thermal.batteryIORegC,
            snapshot.thermal.batteryCellMaxC,
        ]
        if let best = candidates.compactMap({ $0 }).max() { return best }
        return snapshot.thermal.batteryDisplayC
    }

    /// 3-state power label. "On battery" only when genuinely off AC — an AC-connected
    /// pack that isn't charging (held by a limiter, or full) must NOT read as on-battery.
    private var powerLabel: String {
        let b = snapshot.battery
        if !b.isOnACPower { return "On battery" }
        if b.isCharging { return "Charging" }
        return b.isCharged ? "Full · AC" : "Held · AC"
    }

    var body: some View {
        HStack(spacing: 0) {
            DriverCell(value: hottestC.map { "\(Int($0.rounded()))°" } ?? "—",
                       label: "CELL TEMP")
            driverDivider
            DriverCell(value: "\(snapshot.battery.percent)%",
                       label: "CHARGE")
            driverDivider
            DriverCell(value: powerLabel,
                       label: "POWER")
        }
        .frame(maxWidth: .infinity)
    }

    private var driverDivider: some View {
        Rectangle()
            .fill(Color.subtleStroke)
            .frame(width: 1, height: 28)
            .padding(.horizontal, 4)
    }
}

private struct DriverCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.patinaBody(21, .medium))
                .foregroundStyle(Color.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.patinaBody(10, .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(label): \(value)"))
    }
}

// MARK: - 4. Strain

private struct StrainSection: View {
    let strain: AgingStrainSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !strain.hasData {
                Text("This week · Collecting…")
                    .font(.patinaBody(13.5))
                    .foregroundStyle(Color.textSecondary)
            } else {
                let ratioTint = Color.agingWarmth(strain.ratio7d)
                let displayDays = max(0.0, strain.extraAgingDays7d)

                HStack(spacing: 4) {
                    Text("This week ran")
                        .font(.patinaBody(13.5))
                        .foregroundStyle(Color.textSecondary)
                    Text(String(format: "%.1f×", strain.ratio7d))
                        .font(.patinaBody(13.5, .semibold))
                        .foregroundStyle(ratioTint)
                    Text("ideal · +\(String(format: "%.1f", displayDays)) aging-days")
                        .font(.patinaBody(13.5))
                        .foregroundStyle(Color.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)

                if !strain.recent7.isEmpty {
                    StrainSparkline(ratios: strain.recent7)
                        .frame(height: 28)
                }
            }

            Text("Relative estimate — not a capacity measurement.")
                .font(.patinaBody(11))
                .foregroundStyle(Color.textTertiary)
        }
    }
}

/// 7-point polyline; neutral taupe line, last dot tinted by agingWarmth (cream/amber/garnet).
private struct StrainSparkline: View {
    let ratios: [Double]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let count = ratios.count
            guard count >= 2 else { return AnyView(EmptyView()) }
            let yMax = max(ratios.max() ?? 2.0, 2.0)
            let yMin = 0.0

            func x(_ i: Int) -> CGFloat {
                CGFloat(i) / CGFloat(count - 1) * w
            }
            func y(_ v: Double) -> CGFloat {
                h - CGFloat((v - yMin) / (yMax - yMin)) * h * 0.85 - h * 0.075
            }

            return AnyView(ZStack {
                // Polyline — calm neutral; color is reserved for the latest point
                Path { p in
                    p.move(to: CGPoint(x: x(0), y: y(ratios[0])))
                    for i in 1..<count {
                        p.addLine(to: CGPoint(x: x(i), y: y(ratios[i])))
                    }
                }
                .stroke(Color.textSecondary, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))

                // Dots
                ForEach(Array(ratios.enumerated()), id: \.offset) { idx, val in
                    let isLast = idx == count - 1
                    let dotColor = isLast ? Color.agingWarmth(val) : Color.textTertiary
                    Circle()
                        .fill(dotColor)
                        .frame(width: isLast ? 7 : 4, height: isLast ? 7 : 4)
                        .position(x: x(idx), y: y(val))
                        .shadow(color: isLast ? dotColor.opacity(0.6) : .clear, radius: 4)
                }
            })
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 5. Outlook

private struct OutlookLine: View {
    let projection: HealthProjectionResult

    private var outlookText: String {
        switch projection.status {
        case .projecting:
            if let r = projection.monthsTo80Range {
                return "Outlook · ~80% health in \(Int(r.min.rounded()))–\(Int(r.max.rounded())) months"
            }
            // Already at/below 80%: months-to-80 is undefined, so don't sit on "projecting…".
            if projection.currentHealthPercent <= 80 {
                return "Outlook · already below 80% — tracking further fade"
            }
            return "Outlook · projecting…"
        case .flat:
            return "Outlook · holding steady at the current trend"
        case .insufficient:
            return "Outlook · collecting data…"
        }
    }

    var body: some View {
        Text(outlookText)
            .font(.patinaBody(13))
            .foregroundStyle(Color.textSecondary)
    }
}

// MARK: - 6. Action Chip

private struct ActionChip: View {
    let action: LongevityAction

    private var chipColor: Color {
        switch action.severity {
        case .urgent:  Color.garnetAccent
        case .suggest: Color.amberAccent
        case .info:    Color.textSecondary
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(chipColor)
                .frame(width: 7, height: 7)
            Text(action.title)
                .font(.patinaBody(13))
                .foregroundStyle(chipColor)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 8)
        .background(chipColor.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

// MARK: - 7. Details Expander

private struct DetailsToggleRow: View {
    @Binding var showDetails: Bool

    var body: some View {
        HStack {
            Text("Details · Patterns")
                .font(.patinaBody(12.5))
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Button(showDetails ? "Hide" : "Show") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showDetails.toggle()
                }
            }
            .font(.patinaBody(12.5))
            .foregroundStyle(Color.textSecondary)
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

private struct DetailsContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // Heat strip section
            VStack(alignment: .leading, spacing: 6) {
                Text("WHEN IT RUNS HOT")
                    .font(.patinaBody(11, .semibold))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.textTertiary)
                Text("Cell temperature by hour of day")
                    .font(.patinaBody(12))
                    .foregroundStyle(Color.textTertiary)

                if model.heatPattern.hasEnoughData {
                    HeatStrip(profile: model.heatPattern.hourlyProfile)
                        .frame(height: 34)
                } else {
                    Text("Collecting…")
                        .font(.patinaBody(13))
                        .foregroundStyle(Color.textSecondary)
                }
            }

            // Heat vs health
            VStack(alignment: .leading, spacing: 4) {
                Text("Heat vs health.")
                    .font(.patinaBody(13))
                    .foregroundStyle(Color.textSecondary)
                Text(verdictCopy)
                    .font(.patinaBody(12))
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Health outlook
            VStack(alignment: .leading, spacing: 8) {
                Text("HEALTH OUTLOOK")
                    .font(.patinaBody(11, .semibold))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.textTertiary)

                switch model.healthProjection.status {
                case .projecting:
                    HealthProjectionChart(
                        history: model.batteryHealthSeries,
                        points: model.healthProjection.points
                    )
                    Text("Projection band · relative estimate, not a capacity measurement.")
                        .font(.patinaBody(11))
                        .foregroundStyle(Color.textTertiary)
                case .flat:
                    Text("Battery health is holding steady at the current trend.")
                        .font(.patinaBody(13))
                        .foregroundStyle(Color.textSecondary)
                case .insufficient:
                    Text("Collecting data… a trend appears after ~2 weeks of readings.")
                        .font(.patinaBody(13))
                        .foregroundStyle(Color.textSecondary)
                }
            }

            // Longevity factors
            VStack(alignment: .leading, spacing: 10) {
                Text("LONGEVITY FACTORS")
                    .font(.patinaBody(11, .semibold))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.textTertiary)

                ForEach(model.longevityAssessment.factors) { factor in
                    FactorRow(factor: factor)
                }
            }

            // Score
            let score = model.longevityAssessment.score
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(score)")
                    .font(.patinaDisplay(38, .medium))
                    .foregroundStyle(scoreTint(score))
                    .shadow(color: scoreTint(score).opacity(0.45), radius: 6)
                    .monospacedDigit()
                Text("/ 100 longevity score")
                    .font(.patinaBody(13))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.top, 4)
        }
    }

    private var verdictCopy: String {
        switch model.heatHealthInsight.verdict {
        case .warmFadesFaster:    "Warmer hours track with faster aging in your readings."
        case .noClearDifference:  "No clear link between heat and aging yet."
        case .insufficientData:   "Collecting data…"
        }
    }

    private func scoreTint(_ score: Int) -> Color {
        if score >= 85 { return Color.textPrimary }
        if score >= 65 { return Color.amberAccent }
        return Color.garnetAccent
    }
}

private struct FactorRow: View {
    let factor: LongevityFactor

    private var tint: Color {
        switch factor.status {
        case .good:  Color.textPrimary
        case .watch: Color.amberAccent
        case .poor:  Color.garnetAccent
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(factor.title)
                .font(.patinaBody(13))
                .foregroundStyle(Color.textSecondary)
            Spacer()
            // Pill bar on the right
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.insetFill)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(tint)
                        .frame(width: barWidth(geo.size.width), height: 6)
                }
            }
            .frame(width: 80, height: 6)
        }
    }

    private func barWidth(_ totalWidth: CGFloat) -> CGFloat {
        switch factor.status {
        case .good:  totalWidth
        case .watch: totalWidth * 0.55
        case .poor:  totalWidth * 0.25
        }
    }
}

// MARK: - HeatStrip

/// Horizontal row of 24 cells colored by hour-of-day mean temperature.
struct HeatStrip: View {
    let profile: [Double?]   // 24 hourly weighted-mean temps (nil = no data)

    private let tickHours = [0, 6, 12, 18, 24]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                ForEach(0..<24, id: \.self) { h in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(heatCellColor(h < profile.count ? profile[h] : nil))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                }
            }
            HStack(spacing: 0) {
                ForEach(0..<25, id: \.self) { h in
                    if tickHours.contains(h) {
                        Text("\(h)")
                            .font(.patinaBody(10))
                            .foregroundStyle(Color.textTertiary)
                    } else {
                        Color.clear
                    }
                    if h < 24 { Spacer(minLength: 0) }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery temperature by hour of day")
    }
}

// MARK: - Shared helpers (kept for HeatStrip and HealthProjectionChart)

/// Maps a mean battery temp to a quiet-neutral → amber(42°) → garnet(48°) fill; nil = no data.
/// Cool hours stay a calm warm-neutral (on the Dark Jewel palette) — no teal/blue.
private func heatCellColor(_ meanC: Double?) -> Color {
    guard let t = meanC else { return Color.insetFill }
    let caution = ThermalThresholds.batteryCautionC // 42
    let hot = ThermalThresholds.batteryHotC         // 48
    let coolFloor = caution - 14                    // 28 — wider gradient window
    if t <= coolFloor { return Color.textTertiary.opacity(0.18) }
    if t < caution {
        let f = (t - coolFloor) / 14
        return Color.amberAccent.opacity(0.12 + 0.33 * f)
    }
    if t < hot {
        let f = (t - caution) / (hot - caution)
        return Color.amberAccent.opacity(0.55 + 0.40 * f)
    }
    return Color.garnetAccent.opacity(0.92)
}

// MARK: - HealthProjectionChart (unchanged — reused)

struct HealthProjectionChart: View {
    let history: [Double]                          // recent actual health %, oldest→newest
    let points: [HealthProjectionResult.Point]     // monthOffset ascending (projection)

    private func py(_ v: Double, height: CGFloat, yMin: Double, yMax: Double) -> CGFloat {
        height - CGFloat((v - yMin) / (yMax - yMin)) * height
    }
    private func histX(_ i: Int, count: Int, splitX: CGFloat) -> CGFloat {
        count >= 2 ? CGFloat(Double(i) / Double(count - 1)) * splitX : 0
    }
    private func projX(_ m: Int, maxMonth: Int, splitX: CGFloat, width: CGFloat) -> CGFloat {
        splitX + CGFloat(Double(m) / Double(maxMonth)) * (width - splitX)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let maxMonth = max(1, points.last?.monthOffset ?? 1)
            let projLo = points.map { $0.low }.min() ?? 80
            let histLo = history.min() ?? 100
            let yMin = min(80, min(projLo, histLo)) - 2
            let yMax = 100.0
            let splitX: CGFloat = history.count >= 2 ? w * 0.38 : 0

            ZStack {
                // projection band (low..high)
                Path { p in
                    guard let f = points.first else { return }
                    p.move(to: CGPoint(x: projX(f.monthOffset, maxMonth: maxMonth, splitX: splitX, width: w), y: py(f.high, height: h, yMin: yMin, yMax: yMax)))
                    for pt in points { p.addLine(to: CGPoint(x: projX(pt.monthOffset, maxMonth: maxMonth, splitX: splitX, width: w), y: py(pt.high, height: h, yMin: yMin, yMax: yMax))) }
                    for pt in points.reversed() { p.addLine(to: CGPoint(x: projX(pt.monthOffset, maxMonth: maxMonth, splitX: splitX, width: w), y: py(pt.low, height: h, yMin: yMin, yMax: yMax))) }
                    p.closeSubpath()
                }
                .fill(Color.textTertiary.opacity(0.16))

                // historical actual line (solid) — gold data series
                Path { p in
                    guard history.count >= 2 else { return }
                    p.move(to: CGPoint(x: histX(0, count: history.count, splitX: splitX), y: py(history[0], height: h, yMin: yMin, yMax: yMax)))
                    for i in 1..<history.count {
                        p.addLine(to: CGPoint(x: histX(i, count: history.count, splitX: splitX), y: py(history[i], height: h, yMin: yMin, yMax: yMax)))
                    }
                }
                .stroke(Color.textSecondary, style: StrokeStyle(lineWidth: 1.5))

                // central dashed (projection)
                Path { p in
                    guard let f = points.first else { return }
                    p.move(to: CGPoint(x: projX(f.monthOffset, maxMonth: maxMonth, splitX: splitX, width: w), y: py(f.central, height: h, yMin: yMin, yMax: yMax)))
                    for pt in points { p.addLine(to: CGPoint(x: projX(pt.monthOffset, maxMonth: maxMonth, splitX: splitX, width: w), y: py(pt.central, height: h, yMin: yMin, yMax: yMax))) }
                }
                .stroke(Color.textSecondary.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))

                // 80% reference (full width)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: py(80, height: h, yMin: yMin, yMax: yMax)))
                    p.addLine(to: CGPoint(x: w, y: py(80, height: h, yMin: yMin, yMax: yMax)))
                }
                .stroke(Color.garnetAccent.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
        }
        .frame(height: 80)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery health: recent history and projected range over coming months")
    }
}
