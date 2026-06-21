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
            AgingHeroSection(rate: model.agingRate, snapshot: model.snapshot,
                             calibration: model.batteryCalibration)
                .padding(.bottom, 22)

            // 3. Drivers
            hairline
            DriversRow(snapshot: model.snapshot)
                .padding(.top, 14)
                .padding(.bottom, 22)

            // 4. Strain (calendar) + cycle throughput
            hairline
            StrainSection(strain: model.agingStrain,
                          cyclesPerWeek: model.batteryLongevity?.cyclesPerWeek,
                          cycleWearLow: model.batteryLongevity?.cycleWearPctPerYearLow,
                          cycleWearHigh: model.batteryLongevity?.cycleWearPctPerYearHigh,
                          ratedCycle: RatedCycleContext.make(
                              cycleCount: model.snapshot.battery.cycleCount,
                              ratedCycleCount: model.snapshot.battery.ratedCycleCount))
                .padding(.top, 14)
                .padding(.bottom, 18)

            // Recent charge range — surfaces high-SoC dwell, the lever behind the charge-limit nudge.
            // Guard at the parent so firmware that doesn't report daily SoC reserves no phantom gap.
            if let minSoc = model.snapshot.battery.dailyMinSoc, let maxSoc = model.snapshot.battery.dailyMaxSoc {
                ChargeRangeLine(minSoc: minSoc, maxSoc: maxSoc,
                                nativeChargeLimitAvailable: AppModel.nativeChargeLimitAvailable)
                    .padding(.bottom, 18)
            }

            // 5. When it runs hot — promoted from Details: the one pattern no competitor shows.
            if model.heatPattern.hasEnoughData {
                hairline
                HeatPatternSection(hourlyProfile: model.heatPattern.hourlyProfile)
                    .padding(.top, 14)
                    .padding(.bottom, 18)
            }

            // 6. Outlook
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
    /// so it always scrolls — no wasted space. The reservation grows when the heat-pattern
    /// section is promoted onto the collapsed card (~150pt) so the popover can't overrun a
    /// 14" screen and clip the score/factors off the bottom.
    private var detailsViewportHeight: CGFloat {
        let screenH = NSScreen.main?.visibleFrame.height ?? 900
        let reserved: CGFloat = model.heatPattern.hasEnoughData ? 900 : 760
        return max(220, min(380, screenH - reserved))
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
    let calibration: BatteryCalibrationResult

    private var multiplier: Double { rate?.multiplier ?? 1.0 }

    /// When the model has been anchored to the user's measured fade, a short verdict line.
    private var calibrationLine: (text: String, tint: Color)? {
        guard calibration.status == .calibrated, let band = calibration.band else { return nil }
        switch band {
        case .slower: return (NSLocalizedString("Calibrated to your battery — aging slower than the model", comment: ""), Color.textPrimary)
        case .about:  return (NSLocalizedString("Calibrated to your battery — about as the model predicts", comment: ""), Color.textPrimary)
        case .faster: return (NSLocalizedString("Calibrated to your battery — aging faster than the model", comment: ""), Color.amberAccent)
        }
    }

    /// Qualitative takeaway: is the measured wear driven by calendar (time at high charge)
    /// or by cycles? Names the user's main lever. Informational, never alarming — textSecondary.
    /// Deliberately no number/bar: the split is a coarse tag, not a published percentage.
    private var attributionLine: String? {
        guard calibration.status == .calibrated, let a = calibration.attribution else { return nil }
        switch a {
        case .calendarDominant: return NSLocalizedString("Wear is mostly calendar (time at high charge) — Apple’s Charge Limit is your main lever.", comment: "")
        case .cycleDominant:    return NSLocalizedString("Wear is mostly cycles (charge/discharge) — fewer full swings help most.", comment: "")
        case .balanced:         return NSLocalizedString("Wear is a mix of calendar and cycles.", comment: "")
        }
    }

    /// Before calibration unlocks (≥56-day window) but with a window already accruing, a quiet
    /// progress line so the user knows it's working toward a verdict. windowDays 0 → no line.
    private var calibrationProgressLine: String? {
        guard calibration.status == .modeled, calibration.windowDays > 0 else { return nil }
        let fmt = NSLocalizedString("Calibrating to your battery · %d/%d days", comment: "")
        return String(format: fmt, calibration.windowDays, BatteryCalibration.minWindowDays)
    }

    /// The one-decimal value the user actually sees. Band word, tint, and the "≈ N×"
    /// numeral all derive from THIS, so they can never disagree at a rounding boundary
    /// (e.g. 1.48 must not show "LOW" next to "1.5×").
    private var shownMultiplier: Double { (multiplier * 10).rounded() / 10 }

    /// Hero numeral tint. Cold-charge plating risk floors the rate to ~1.0×, so override
    /// to garnet there so the number agrees with the plating caution below.
    private var warmth: Color {
        rate?.coldChargeCaution == true ? Color.garnetAccent : Color.agingWarmth(shownMultiplier)
    }
    /// The band pill keeps its semantic color even under the cold-charge garnet override,
    /// so a floored ~1.0× never renders an alarming garnet "LOW".
    private var pillColor: Color { Color.agingWarmth(shownMultiplier) }

    private var formattedNumber: String {
        guard rate != nil else { return "" }
        let m = shownMultiplier
        return m >= 10 ? "\(Int(m.rounded()))" : String(format: "%.1f", m)
    }

    private var isLowBand: Bool { shownMultiplier < 1.5 }

    private var driverLine: String {
        guard let rate else { return "" }
        // Driver attribution only makes sense once aging is actually elevated;
        // at the low band the multiplier is ~1.0× so naming a "main driver" misleads.
        if isLowBand { return NSLocalizedString("Aging at the ideal idle rate", comment: "") }
        switch rate.dominantDriver {
        case .temperature: return NSLocalizedString("Heat is the main driver right now", comment: "")
        case .charge: return NSLocalizedString("High charge is the main driver right now", comment: "")
        case .balanced: return NSLocalizedString("High charge + heat", comment: "")
        }
    }

    /// Categorical truth alongside the precise-looking numeral, so the headline
    /// doesn't lean on one-decimal precision the noisy inputs can't support.
    /// Derived from shownMultiplier so it always matches the displayed number.
    private var bandWord: String {
        if shownMultiplier >= 3.0 { return NSLocalizedString("HIGH", comment: "aging band") }
        if shownMultiplier >= 1.5 { return NSLocalizedString("ELEVATED", comment: "aging band") }
        return NSLocalizedString("LOW", comment: "aging band")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("AGING SPEED NOW")
                    .font(.patinaBody(11, .semibold))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.textTertiary)
                if rate != nil {
                    Text(bandWord)
                        .font(.patinaBody(10, .semibold))
                        .tracking(1.0)
                        .foregroundStyle(pillColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(pillColor.opacity(0.18))
                        .clipShape(Capsule())
                        .accessibilityHidden(true) // folded into the hero number's a11y label
                }
                Spacer()
            }
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
                .accessibilityLabel(Text("Aging speed now: about \(formattedNumber) times an ideal idle, \(bandWord) band"))

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

                // Anti-gaming: a low SoC genuinely lowers calendar aging, but chasing a
                // lower number by running the pack down trades it for extra cycle wear.
                if snapshot.battery.percent < 25 {
                    Text("Low charge isn’t “better” — mid charge (~50%) is healthiest.")
                        .font(.patinaBody(12))
                        .foregroundStyle(Color.textTertiary)
                        .padding(.top, 4)
                }

                if rate?.coldChargeCaution == true {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(Color.garnetAccent)
                            .frame(width: 7, height: 7)
                        Text("Charging while cold — risk of lithium plating")
                            .font(.patinaBody(13))
                            .foregroundStyle(Color.textPrimary) // garnet text under-contrasts on the hero panel; dot carries the color
                    }
                    .padding(.top, 4)
                }
            }

            // Disclaimer raised to secondary contrast so the visual hierarchy matches the
            // model's actual (modest) precision rather than letting the big numeral oversell it.
            Text("Relative estimate from published kinetics — not a capacity measurement.")
                .font(.patinaBody(11))
                .foregroundStyle(Color.textSecondary)
                .padding(.top, 10)

            if let cal = calibrationLine {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(cal.tint)
                    Text(cal.text)
                        .font(.patinaBody(11))
                        .foregroundStyle(cal.tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 6)
            }

            // Qualitative calendar-vs-cycle takeaway — names the main lever, no number/bar.
            if let attribution = attributionLine {
                Text(attribution)
                    .font(.patinaBody(11))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }

            // Quiet progress toward calibration once a window is accruing.
            if let progress = calibrationProgressLine {
                Text(progress)
                    .font(.patinaBody(11))
                    .foregroundStyle(Color.textTertiary)
                    .padding(.top, 6)
            }
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

    /// Canonical BMS pack temperature (= what AlDente/Apple report, = the menu-bar/Status
    /// reading, = the aging-model input). The SMC hottest-cell max stays an upper-bound shown
    /// only in the battery-sensor detail card and used for the (conservative) warning level.
    private var batteryTempC: Double? {
        snapshot.thermal.batteryDisplayC
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
            DriverCell(value: batteryTempC.map { "\(Int($0.rounded()))°" } ?? "—",
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
            // LocalizedStringKey so text values (power state) and labels localize;
            // numeric values (30°, 52%) have no key and fall back verbatim.
            Text(LocalizedStringKey(value))
                .font(.patinaBody(21, .medium))
                .foregroundStyle(Color.textPrimary)
                .monospacedDigit()
            Text(LocalizedStringKey(label))
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
    /// Cycle throughput is a SEPARATE wear mechanism the calendar multiplier doesn't capture;
    /// surfacing it stops heavy-cyclers (cool + mid-SoC) from being silently under-warned.
    let cyclesPerWeek: Double?
    /// Estimated capacity loss/yr from cycle throughput (range; measured cycles × published per-EFC loss).
    let cycleWearLow: Double?
    let cycleWearHigh: Double?
    /// Apple's rated-cycle context ("N · ~M rated"). nil when the BMS doesn't report a rating.
    let ratedCycle: RatedCycleContext?

    private var heavyCycling: Bool { (cyclesPerWeek ?? 0) >= 15 }   // matches BatteryLongevity.highCycleRate

    private var cycleWearText: String? {
        guard let lo = cycleWearLow, let hi = cycleWearHigh else { return nil }
        if hi < 0.1 { return NSLocalizedString("→ < 0.1%/yr capacity (est.)", comment: "") }
        return String(format: NSLocalizedString("→ ~%.1f–%.1f%%/yr capacity (est.)", comment: ""), lo, hi)
    }

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

            // Cycle throughput — the dominant wear mode for heavy users, invisible to the
            // calendar multiplier above.
            if let cw = cyclesPerWeek, cw >= 0.5 {
                HStack(spacing: 4) {
                    Text("Cycling ·")
                        .font(.patinaBody(13))
                        .foregroundStyle(Color.textSecondary)
                    Text(String(format: NSLocalizedString("~%.0f/week", comment: "cycles per week"), cw))
                        .font(.patinaBody(13, heavyCycling ? .semibold : .regular))
                        .foregroundStyle(heavyCycling ? Color.amberAccent : Color.textSecondary)
                    // cyclesPerWeek is averaged over the whole health log, NOT the last 7 days —
                    // label it so it isn't misread as "this week" under the header above.
                    Text(heavyCycling ? "lifetime avg · heavy" : "lifetime avg")
                        .font(.patinaBody(13))
                        .foregroundStyle(heavyCycling ? Color.amberAccent : Color.textTertiary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

                if let wear = cycleWearText {
                    Text(wear)
                        .font(.patinaBody(11.5))
                        .foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Rated-cycle context — one honest line: where the count sits vs Apple's spec. Apple
            // rates Apple Silicon packs ~M cycles to 80% health; it's an expectation, NOT a hard
            // limit. Shown only when the BMS reports a rating (some Macs don't).
            if let rated = ratedCycle {
                Text(String(format: NSLocalizedString("Cycle count %d · ~%d rated", comment: "battery cycle count vs Apple's rated count"),
                            rated.cycleCount, rated.ratedCycleCount))
                    .font(.patinaBody(13))
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }

            Text("Relative estimate — calendar aging only; cycle wear is tracked separately.")
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

// MARK: - Charge range (high-SoC exposure)

/// Unobtrusive line: the recent charge window the BMS recorded, plus a state-aware second clause —
/// a positive confirmation when a limit appears active, or a subtle high-SoC hint when the pack
/// routinely sits near full. The actionable nudge (with the %) lives in the ActionChip; this is
/// context. The parent only instantiates this when both values are present, so params are non-optional.
private struct ChargeRangeLine: View {
    let minSoc: Int
    let maxSoc: Int
    /// Gates the positive "limit active" confirmation — only meaningful where macOS exposes the
    /// native Charge Limit (26.4+). Without it, a low max SoC is just a habit, not a confirmed limit.
    let nativeChargeLimitAvailable: Bool

    private var state: ChargeLimitInsight.State {
        ChargeLimitInsight.classify(dailyMaxSoc: maxSoc)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(String(format: NSLocalizedString("Charge range %d–%d%% recently", comment: ""), minSoc, maxSoc))
                .font(.patinaBody(12))
                .foregroundStyle(Color.textTertiary)

            switch state {
            case .limitActive where nativeChargeLimitAvailable:
                // Reassurance that the user's action worked — a limit being active is GOOD, so this
                // is cream/secondary, never garnet. (Inferred from a recent max ≤82%; no public API
                // exposes the native limit state.) Not a LongevityAction — there's nothing to do.
                Text(NSLocalizedString("Charge limit active ✓ — high-charge aging minimized", comment: ""))
                    .font(.patinaBody(12, .semibold))
                    .foregroundStyle(Color.textSecondary)
            case .highExposure(let reductionPct):
                // Surface the quantified benefit ON the visible card line — the ActionChip renders
                // only the action title, so this is the only place the user actually SEES the %.
                // amber = the "you could do better" hint. Fall back to the static label at 0% gain.
                Text(reductionPct > 0
                     ? String(format: NSLocalizedString("high-SoC exposure · ~%d%% less high-charge aging if capped at 80%%", comment: ""), reductionPct)
                     : NSLocalizedString("high-SoC exposure", comment: ""))
                    .font(.patinaBody(12, .semibold))
                    .foregroundStyle(Color.amberAccent)
            default:
                // .normal, or .limitActive on older macOS — just the range, no second clause.
                EmptyView()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 5. Outlook

private struct OutlookLine: View {
    let projection: HealthProjectionResult

    private var outlookText: String {
        switch projection.status {
        case .projecting:
            if let r = projection.monthsTo80Range {
                return String(format: NSLocalizedString("Outlook · ~80%% health in %d–%d months", comment: ""),
                              Int(r.min.rounded()), Int(r.max.rounded()))
            }
            // Already at/below 80%: months-to-80 is undefined, so don't sit on "projecting…".
            if projection.currentHealthPercent <= 80 {
                return NSLocalizedString("Outlook · already below 80% — tracking further fade", comment: "")
            }
            return NSLocalizedString("Outlook · projecting…", comment: "")
        case .flat:
            return NSLocalizedString("Outlook · holding steady at the current trend", comment: "")
        case .insufficient:
            return NSLocalizedString("Outlook · collecting data…", comment: "")
        }
    }

    var body: some View {
        Text(outlookText)
            .font(.patinaBody(13))
            .foregroundStyle(Color.textSecondary)
    }
}

// MARK: - When It Runs Hot (promoted unique surface)

/// The hour-of-day heat strip — a fixable, non-obvious pattern no competitor surfaces.
/// Shown on the main card (caller gates on hasEnoughData) rather than buried in Details.
private struct HeatPatternSection: View {
    let hourlyProfile: [Double?]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WHEN IT RUNS HOT")
                .font(.patinaBody(11, .semibold))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(Color.textTertiary)
            Text("Cell temperature by hour of day")
                .font(.patinaBody(12))
                .foregroundStyle(Color.textTertiary)
            HeatStrip(profile: hourlyProfile)
                .frame(height: 34)
        }
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

    /// Title legibility: garnet at 13pt under-contrasts on the tinted chip, so the urgent
    /// title is rendered cream (the garnet dot/chevron still carry the severity color).
    private var titleColor: Color {
        action.severity == .urgent ? Color.textPrimary : chipColor
    }

    /// Close the action loop: route only genuinely ACTIONABLE charge advice to the
    /// automated lever (macOS Optimized Charging). Pure-status ids (battery-low,
    /// battery-fade) and heat advice get no chevron — the destination can't act on them.
    private var deepLink: URL? {
        switch action.id {
        case "high-soc", "charge-hot", "high-soc-limit":
            return URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")
        default:
            return action.id.contains("storage")
                ? URL(string: "x-apple.systempreferences:com.apple.settings.Storage")
                : nil
        }
    }

    var body: some View {
        if let url = deepLink {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                chip(showChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens System Settings"))
        } else {
            chip(showChevron: false)
        }
    }

    private func chip(showChevron: Bool) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(chipColor)
                .frame(width: 7, height: 7)
            Text(LocalizedStringKey(action.title)) // Core returns English; localize via key lookup
                .font(.patinaBody(13))
                .foregroundStyle(titleColor)
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(chipColor.opacity(0.7))
            }
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

            // (The hour-of-day heat strip is promoted to the main card; see HeatPatternSection.)

            // Accelerating-fade (knee) hint — RARE, advanced, Details-only signal. Shown only
            // when the conservative detector clears its long-baseline + separated-CI bar. Soft,
            // informational (textSecondary): no replace/months claim, no alarm color, no
            // notification. `.steady`/`.insufficient` render nothing.
            if model.fadeTrend == .accelerating {
                Text(NSLocalizedString("Capacity fade may be speeding up — worth watching.",
                                       comment: "rare in-UI knee/acceleration hint, informational not alarm"))
                    .font(.patinaBody(12))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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

            // Rated cycles — the fuller, honest note. Apple's spec/expectation, explicitly NOT a
            // hard limit and not a "replace at N" threshold. Shown only when the BMS reports it.
            if let rated = RatedCycleContext.make(
                cycleCount: model.snapshot.battery.cycleCount,
                ratedCycleCount: model.snapshot.battery.ratedCycleCount) {
                VStack(alignment: .leading, spacing: 4) {
                    // Show the percent-through only once it rounds to ≥1% — a near-new pack reading
                    // "(0%)" looks like a bug, so it falls back to the plain card phrasing.
                    Text(rated.percentThrough >= 1
                         ? String(format: NSLocalizedString("Cycle count %d · ~%d rated (%d%%)", comment: "cycle count, Apple rated count, percent through rating"),
                                  rated.cycleCount, rated.ratedCycleCount, rated.percentThrough)
                         : String(format: NSLocalizedString("Cycle count %d · ~%d rated", comment: "battery cycle count vs Apple's rated count"),
                                  rated.cycleCount, rated.ratedCycleCount))
                        .font(.patinaBody(13))
                        .monospacedDigit()
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(String(format: NSLocalizedString("Apple rates this pack for ~%d cycles to 80%% health — a spec, not a hard limit. Batteries keep working past it.", comment: "honest rated-cycle caption"),
                                rated.ratedCycleCount))
                        .font(.patinaBody(12))
                        .foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Health reconciliation — explain the intraday % swing honestly.
            let reconciliation = HealthReconciliation.from(
                series: model.batteryHealthSeries,
                reported: model.snapshot.battery.healthPercent
            )
            if reconciliation.sampleCount >= 2 {
                HealthReconciliationSection(reconciliation: reconciliation)
            }

            // Charge-limit options — compact comparison of native cap levels (80/85/90/95).
            // Pure insight: each row is the high-charge AGING reduction at that cap, never a
            // "recommended" pick. Shown only where macOS exposes the native Charge Limit and the
            // pack actually sits above 80% (otherwise there's nothing below the habit to compare).
            if AppModel.nativeChargeLimitAvailable,
               let maxSoc = model.snapshot.battery.dailyMaxSoc, maxSoc > 80 {
                let steps = ChargeLimitInsight.chargeLimitComparison(currentMaxSoc: maxSoc)
                if !steps.isEmpty {
                    ChargeLimitOptionsSection(steps: steps)
                }
            }

            // Since install — forward-only cumulative exposure totals. Honest "since install"
            // (not "lifetime"); shown only once at least one completed day has been counted.
            if model.sinceInstall.sinceDay != nil {
                SinceInstallSection(exposure: model.sinceInstall)
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
        case .warmFadesFaster:    NSLocalizedString("Warmer hours track with faster aging in your readings.", comment: "")
        case .noClearDifference:  NSLocalizedString("No clear link between heat and aging yet.", comment: "")
        case .insufficientData:   NSLocalizedString("Collecting data…", comment: "")
        }
    }

    private func scoreTint(_ score: Int) -> Color {
        if score >= 85 { return Color.textPrimary }
        if score >= 65 { return Color.amberAccent }
        return Color.garnetAccent
    }
}

/// Honest explainer for the intraday battery-health % swing. The gauge re-estimates capacity
/// through the day (other apps show e.g. 83% then 98% same day); that's noise, not real loss.
/// We surface Patina's robust TREND read (median of recent readings) and a coarse steady/variable
/// flag — never a fabricated decimal confidence, and never a 4th "true" number.
private struct HealthReconciliationSection: View {
    let reconciliation: HealthReconciliation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Health readings swing intraday — that's the battery gauge, not real loss.")
                .font(.patinaBody(13))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let smoothed = reconciliation.smoothedPercent {
                Text(trendLine(smoothed))
                    .font(.patinaBody(12))
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("macOS may report a different % — both are views of the same battery.")
                .font(.patinaBody(12))
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "Patina's trend reading: ~N% · steady" — flag word, not a percent confidence.
    private func trendLine(_ smoothed: Int) -> String {
        let template = NSLocalizedString(
            "Patina's trend reading: ~%d%% · %@",
            comment: "Smoothed (median) battery-health trend read with a steady/variable flag word"
        )
        return String(format: template, smoothed, flagWord)
    }

    private var flagWord: String {
        switch reconciliation.stability {
        case .stable:   NSLocalizedString("steady", comment: "Health reading is stable across recent days")
        case .variable: NSLocalizedString("variable", comment: "Health reading swings across recent days")
        }
    }
}

/// Compact comparison of the native macOS Charge Limit cap levels. Each row states the high-charge
/// AGING reduction at that cap vs the current daily max — honest, no "best fit" / "recommended" row.
private struct ChargeLimitOptionsSection: View {
    let steps: [ChargeLimitInsight.ChargeLimitStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CHARGE-LIMIT OPTIONS")
                .font(.patinaBody(11, .semibold))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(Color.textTertiary)

            ForEach(steps, id: \.cap) { step in
                Text(rowText(step))
                    .font(.patinaBody(12))
                    .foregroundStyle(Color.textSecondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("High-charge aging only — not total battery life.")
                .font(.patinaBody(11))
                .foregroundStyle(Color.textTertiary)
        }
    }

    private func rowText(_ step: ChargeLimitInsight.ChargeLimitStep) -> String {
        String(format: NSLocalizedString("Cap %d%% → ~%d%% less high-charge aging", comment: ""),
               step.cap, step.reductionPct)
    }
}

/// Compact "since install" cumulative-exposure panel. Forward-only totals that survive the 30-day
/// prune, so users see the real long-run stressors. Honest label: "since install" (we only measure
/// since the app first started recording), never "lifetime". Rows are hours above each band; only
/// non-zero rows are shown to keep it tight.
private struct SinceInstallSection: View {
    let exposure: SinceInstallExposure

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headerText)
                .font(.patinaBody(11, .semibold))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(Color.textTertiary)

            if exposure.hoursAbove80OnAC >= 0.05 { row("≥80% on AC", hours: exposure.hoursAbove80OnAC) }
            if exposure.hoursAbove95OnAC >= 0.05 { row("≥95% on AC", hours: exposure.hoursAbove95OnAC) }
            if exposure.hoursAbove40 >= 0.05 { row("Above 40°C", hours: exposure.hoursAbove40) }
            if exposure.hoursAbove45 >= 0.05 { row("Above 45°C", hours: exposure.hoursAbove45) }

            Text("Cumulative stressors since install — not a lifetime total.")
                .font(.patinaBody(11))
                .foregroundStyle(Color.textTertiary)
        }
    }

    private var headerText: String {
        guard let day = exposure.sinceDay else { return NSLocalizedString("SINCE INSTALL", comment: "since-install panel header") }
        return String(format: NSLocalizedString("SINCE INSTALL (%@)", comment: "since-install panel header with start date"),
                      Self.displayDate(day))
    }

    @ViewBuilder
    private func row(_ label: String, hours: Double) -> some View {
        HStack {
            Text(LocalizedStringKey(label))
                .font(.patinaBody(13))
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(String(format: NSLocalizedString("%@ h", comment: "hours value, e.g. '140 h'"), Self.hoursText(hours)))
                .font(.patinaBody(13))
                .foregroundStyle(Color.textPrimary)
                .monospacedDigit()
        }
    }

    /// "140" for whole, "3.5" below 10 h so short exposures aren't all rounded to the same number.
    private static func hoursText(_ hours: Double) -> String {
        hours < 10 ? String(format: "%.1f", hours) : String(format: "%.0f", hours)
    }

    /// "2026-06-01" → localized medium date. Falls back to the raw string if it can't parse.
    private static func displayDate(_ day: String) -> String {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return day }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return fmt.string(from: date)
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
            Text(LocalizedStringKey(factor.title)) // Core returns English; localize via key lookup
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
