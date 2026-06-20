import SwiftUI
import ThermoMoleCore

struct StatusTab: View {
    @ObservedObject var model: AppModel

    private var statusBrief: StatusBrief {
        StatusBrief(snapshot: model.snapshot)
    }

    private var batteryPackDetail: String {
        let source = batterySourceLabel(model.snapshot.thermal.batteryTemperatureSource)
        if let power = formatBatteryPower(model.snapshot.battery.instantPowerW) {
            return "\(source) · \(power)"
        }
        return source
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TabHeader(subtitle: NSLocalizedString("Battery heat, CPU warmth, and memory pressure without the noise.", comment: "")) {}

                if statusBrief.isChargingWhileHot {
                    ChargeWhileHotBanner()
                }

                HStack(alignment: .top, spacing: 12) {
                    BatteryTemperatureRing(temperatureC: model.snapshot.thermal.batteryDisplayC, diameter: 132)
                        .frame(width: 188)
                        .frame(maxHeight: .infinity)
                        .padding(16)
                        .softPanel()
                    StatusBriefPanel(brief: statusBrief)
                        .frame(maxWidth: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    TrendTile(
                        title: "Real battery pack",
                        value: formatTemperaturePrecise(model.snapshot.thermal.batteryDisplayC),
                        detail: batteryPackDetail,
                        series: model.statusHistory.batteryTemperatureSeries,
                        tint: batteryColor(model.snapshot.thermal.batteryWarningLevel)
                    )
                    TrendTile(
                        title: "CPU warmth",
                        value: formatTemperaturePrecise(model.snapshot.thermal.cpuDisplayC),
                        detail: cpuSourceLabel(model.snapshot.thermal.cpuTemperatureSource),
                        series: model.statusHistory.cpuTemperatureSeries,
                        tint: .orange
                    )
                }

                HStack(alignment: .top, spacing: 12) {
                    CPUCoreGridView(cpu: model.snapshot.cpu)
                        .frame(maxWidth: .infinity)
                    TrendTile(
                        title: "Battery power",
                        value: formatBatteryPower(model.snapshot.battery.instantPowerW) ?? "--",
                        detail: batteryPowerDirection(model.snapshot.battery),
                        series: model.statusHistory.batteryPowerSeries,
                        tint: Color.thermoAccent
                    )
                    .frame(maxWidth: .infinity)
                }

                HStack(alignment: .top, spacing: 12) {
                    ThermalExposureCard(
                        summary: model.todayExposure,
                        warningLevel: model.snapshot.thermal.batteryWarningLevel
                    )
                    .frame(maxWidth: .infinity)
                    ChargeExposureCard(summary: model.todayChargeExposure)
                        .frame(maxWidth: .infinity)
                }

                HStack(alignment: .top, spacing: 12) {
                    BatteryHealthCard(report: model.batteryLongevity, health: model.latestBatteryHealth, series: model.batteryHealthSeries)
                        .frame(maxWidth: .infinity)
                    CompactProcessList(processes: Array(model.snapshot.topProcesses.prefix(5)))
                        .frame(maxWidth: .infinity)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                    MetricTile(title: "Battery", value: "\(model.snapshot.battery.percent)%", detail: String(format: NSLocalizedString("%d%% health · %d cycles", comment: ""), model.snapshot.battery.healthPercent, model.snapshot.battery.cycleCount), tint: .mint)
                    MetricTile(title: "SSD Temp", value: formatTemperature(model.snapshot.thermal.ssdTemperatureC), detail: "Internal drive", tint: Color.plumAccent)
                    MetricTile(title: "Fan", value: model.snapshot.fanRPM > 0 ? "\(model.snapshot.fanRPM) RPM" : NSLocalizedString("Read-only", comment: ""), detail: "No fan control", tint: .gray)
                }

                BatterySensorDetailCard(summary: BatterySensorSummary(thermal: model.snapshot.thermal))
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ThermalLevelGlyph: View {
    let level: TemperatureWarningLevel
    var body: some View {
        Image(systemName: level == .hot ? "flame.fill" : "thermometer.medium")
            .foregroundStyle(level == .normal ? Color.secondary : Color.amberAccent)
    }
}

struct ChargeWhileHotBanner: View {
    var body: some View {
        Label("Charging while hot — unplug to let the battery cool. Heat plus charging accelerates aging.",
              systemImage: "bolt.trianglebadge.exclamationmark.fill")
            .font(.callout)
            .foregroundStyle(.primary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.amberAccent.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityAddTraits(.updatesFrequently)
    }
}

struct ThermalExposureCard: View {
    let summary: ThermalExposureSummary
    let warningLevel: TemperatureWarningLevel

    private func minutes(_ seconds: TimeInterval) -> Int { Int((seconds / 60).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ThermalLevelGlyph(level: warningLevel)
                Text("Today's battery heat exposure").font(.headline)
            }
            HStack(spacing: 16) {
                exposureStat("Above 40°", minutes(summary.today.secondsAbove40))
                exposureStat("Above 45°", minutes(summary.today.secondsAbove45))
                if let peak = summary.today.peakC {
                    VStack(alignment: .leading) {
                        Text("Peak").font(.caption).foregroundStyle(.secondary)
                        Text(String(format: "%.1f°", peak)).font(.title3).monospacedDigit()
                    }
                }
            }
            ThermalExposureWeekStrip(days: summary.recent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .softPanel()
        .accessibilityElement(children: .contain)
    }

    private func exposureStat(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading) {
            Text(LocalizedStringKey(label)).font(.caption).foregroundStyle(.secondary)
            Text(String(format: NSLocalizedString("%d min", comment: ""), value)).font(.title3).monospacedDigit()
        }
    }
}

struct ThermalExposureWeekStrip: View {
    let days: [DailyThermalExposure]   // descending (today first); displayed chronologically

    private func minutes(_ s: TimeInterval) -> Int { Int((s / 60).rounded()) }

    var body: some View {
        let chronological = Array(days.reversed())
        let maxMinutes = max(1, chronological.map { minutes($0.secondsAbove40) }.max() ?? 1)
        let hasAnyExposure = chronological.contains { minutes($0.secondsAbove40) > 0 }
        VStack(alignment: .leading, spacing: 4) {
            Text("Last 7 days (min ≥40°)").font(.caption2).foregroundStyle(.secondary)
            if hasAnyExposure {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(chronological, id: \.day) { day in
                        let m = minutes(day.secondsAbove40)
                        let tint: Color = day.secondsAbove45 > 0 ? Color.garnetAccent : (m > 0 ? .amberAccent : Color.secondary.opacity(0.3))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(tint)
                            .frame(width: 14, height: max(3, CGFloat(m) / CGFloat(maxMinutes) * 28))
                            .accessibilityLabel(Text(String(format: NSLocalizedString("%@: %d minutes above 40 degrees", comment: ""), day.day, m)))
                    }
                }
                .frame(height: 28, alignment: .bottom)
            } else {
                Text("No heat above 40° in the last 7 days")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(height: 28, alignment: .center)
                    .accessibilityLabel(Text("No battery heat above 40 degrees in the last 7 days"))
            }
        }
    }
}

struct ChargeExposureCard: View {
    let summary: ChargeExposureSummary

    private func minutes(_ s: TimeInterval) -> Int { Int((s / 60).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "powerplug.fill").foregroundStyle(Color.thermoAccent)
                Text("High-charge dwell (on AC)").font(.headline)
            }
            HStack(spacing: 16) {
                stat("≥80%", minutes(summary.today.secondsAbove80OnAC))
                stat("≥95%", minutes(summary.today.secondsAbove95OnAC))
                if let peak = summary.today.peakPercentOnAC {
                    VStack(alignment: .leading) {
                        Text("Peak").font(.caption).foregroundStyle(.secondary)
                        Text("\(peak)%").font(.title3).monospacedDigit()
                    }
                }
            }
            ChargeDwellWeekStrip(days: summary.recent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .softPanel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("High charge dwell on AC today"))
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading) {
            Text(LocalizedStringKey(label)).font(.caption).foregroundStyle(.secondary)
            Text(String(format: NSLocalizedString("%d min", comment: ""), value)).font(.title3).monospacedDigit()
        }
    }
}

struct ChargeDwellWeekStrip: View {
    let days: [DailyChargeExposure]    // descending (today first); displayed chronologically

    private func minutes(_ s: TimeInterval) -> Int { Int((s / 60).rounded()) }

    var body: some View {
        let chronological = Array(days.reversed())
        let maxMinutes = max(1, chronological.map { minutes($0.secondsAbove80OnAC) }.max() ?? 1)
        let hasAny = chronological.contains { minutes($0.secondsAbove80OnAC) > 0 }
        VStack(alignment: .leading, spacing: 4) {
            Text("Last 7 days (min ≥80% on AC)").font(.caption2).foregroundStyle(.secondary)
            if hasAny {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(chronological, id: \.day) { day in
                        let m = minutes(day.secondsAbove80OnAC)
                        let tint: Color = day.secondsAbove95OnAC > 0 ? Color.amberAccent : (m > 0 ? Color.thermoAccent : Color.secondary.opacity(0.3))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(tint)
                            .frame(width: 14, height: max(3, CGFloat(m) / CGFloat(maxMinutes) * 28))
                            .accessibilityLabel(Text(String(format: NSLocalizedString("%@: %d minutes at or above 80 percent on AC", comment: ""), day.day, m)))
                    }
                }
                .frame(height: 28, alignment: .bottom)
            } else {
                Text("No high-charge dwell on AC in the last 7 days")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(height: 28, alignment: .center)
                    .accessibilityLabel(Text("No high charge dwell on AC in the last 7 days"))
            }
        }
    }
}

struct BatteryHealthCard: View {
    let report: BatteryLongevityReport?
    let health: DailyBatteryHealth?
    let series: [Double]

    private var tint: Color {
        guard let s = report?.score else { return Color.oceanAccent }
        if s >= 85 { return Color.leafAccent }
        if s >= 65 { return Color.amberAccent }
        return Color.garnetAccent
    }

    private var detailLine: String {
        guard let h = health else { return NSLocalizedString("Collecting daily readings…", comment: "") }
        return String(format: NSLocalizedString("%d%% health · %d cycles · %d mAh", comment: ""), h.healthPercent, h.cycleCount, h.maxCapacityMAh)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(tint.opacity(0.85)).frame(width: 7, height: 7)
                Text("Battery longevity").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let months = report?.projectedMonthsTo80 {
                    Text(String(format: NSLocalizedString("~%d mo to 80%%", comment: ""), Int(months.rounded())))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(report.map { "\($0.score)" } ?? "--")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Text("/ 100").font(.caption).foregroundStyle(.secondary)
            }
            SparklineView(values: series, tint: tint)
                .frame(height: 36)
            if let alerts = report?.alerts, !alerts.isEmpty {
                HStack(spacing: 6) {
                    ForEach(alerts, id: \.self) { alert in
                        Label(alertText(alert), systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.amberAccent)
                            .lineLimit(1)
                    }
                }
                .minimumScaleFactor(0.8)
            }
            Text(detailLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .softPanel()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Battery longevity"))
        .accessibilityValue(Text(report.map { String(format: NSLocalizedString("score %d of 100, %d percent health, %d cycles", comment: ""), $0.score, $0.healthPercent, $0.cycleCount) } ?? NSLocalizedString("collecting", comment: "")))
    }

    private func alertText(_ alert: BatteryLongevityAlert) -> String {
        switch alert {
        case .fastFade: NSLocalizedString("Fading fast", comment: "")
        case .healthBelow80: NSLocalizedString("Below 80%", comment: "")
        case .healthBelow60: NSLocalizedString("Below 60%", comment: "")
        case .highCycleRate: NSLocalizedString("High cycle rate", comment: "")
        }
    }
}

struct StatusBriefPanel: View {
    var brief: StatusBrief

    private var tint: Color {
        switch brief.mood {
        case .steady: Color.leafAccent
        case .watch: Color.amberAccent
        case .hot: Color.garnetAccent
        }
    }

    private var symbol: String {
        switch brief.mood {
        case .steady: "checkmark.seal.fill"
        case .watch: "thermometer.medium"
        case .hot: "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(brief.title))
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                    Text(LocalizedStringKey(brief.detail))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], spacing: 8) {
                ForEach(brief.signals) { signal in
                    StatusBriefSignalPill(
                        signal: signal,
                        tint: signal.id == brief.prioritySignalID ? tint : Color.thermoAccent,
                        isPriority: signal.id == brief.prioritySignalID
                    )
                }
            }
        }
        .padding(16)
        .softPanel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(String(format: NSLocalizedString("Status summary %@", comment: ""), NSLocalizedString(brief.title, comment: ""))))
        .accessibilityValue(Text(LocalizedStringKey(brief.detail)))
    }
}

struct StatusBriefSignalPill: View {
    var signal: StatusBriefSignal
    var tint: Color
    var isPriority: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint.opacity(isPriority ? 0.9 : 0.55))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(signal.title))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(LocalizedStringKey(signal.value))
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(LocalizedStringKey(signal.detail))
                .font(.caption2.weight(isPriority ? .semibold : .regular))
                .foregroundStyle(isPriority ? tint : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isPriority ? tint.opacity(0.10) : Color.insetFill)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isPriority ? tint.opacity(0.28) : Color.subtleStroke))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(signal.title)))
        .accessibilityValue(Text("\(signal.value), \(signal.detail)"))
    }
}

struct CPUCoreGridView: View {
    let cpu: CPUStatus

    private var summary: String {
        var parts = [String(format: NSLocalizedString("%d cores", comment: ""), cpu.logicalCoreCount)]
        if cpu.performanceCoreCount > 0 || cpu.efficiencyCoreCount > 0 {
            parts.append(String(format: NSLocalizedString("%dP + %dE", comment: ""), cpu.performanceCoreCount, cpu.efficiencyCoreCount))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("CPU Cores", systemImage: "cpu")
                    .font(.headline)
                Spacer()
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if cpu.perCorePercent.isEmpty {
                Text("Sampling…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 48)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 30), spacing: 6)], spacing: 6) {
                    ForEach(Array(cpu.perCorePercent.enumerated()), id: \.offset) { _, percent in
                        CPUCoreBar(percent: percent)
                    }
                }
            }
        }
        .padding(14)
        .softPanel()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("CPU per-core usage"))
        .accessibilityValue(Text(summary))
    }
}

struct CPUCoreBar: View {
    let percent: Double

    private var tint: Color {
        if percent >= 80 { return Color.garnetAccent }
        if percent >= 50 { return Color.amberAccent }
        return Color.thermoAccent
    }

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { proxy in
                let fraction = min(max(percent / 100, 0), 1)
                let height = max(2, proxy.size.height * CGFloat(fraction))
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3).fill(tint).frame(height: height)
                }
            }
            .frame(height: 34)
            Text("\(Int(percent.rounded()))")
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

struct BatterySensorDetailCard: View {
    let summary: BatterySensorSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Battery Sensors", systemImage: "thermometer.medium")
                    .font(.headline)
                Spacer()
                if summary.hasMismatch {
                    Label("differ ≥2°C", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.amberAccent)
                }
            }
            ForEach(summary.rows, id: \.kind) { row in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(label(row.kind))
                            .font(.callout.weight(.semibold))
                        Text(detail(row.kind))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(formatTemperaturePrecise(row.temperatureC))
                        .font(.callout)
                        .monospacedDigit()
                }
            }
            Text(LocalizedStringKey(summary.hasMismatch
                 ? "Sensors read different spots (pack vs hottest cell). ~1°C difference is normal."
                 : "BMS pack is the trend basis; hottest cell is the conservative upper bound."))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .softPanel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Battery temperature sensors"))
    }

    private func label(_ kind: BatterySensorKind) -> String {
        switch kind {
        case .bms: NSLocalizedString("BMS pack", comment: "")
        case .cellMax: NSLocalizedString("Hottest cell", comment: "")
        case .virtual: NSLocalizedString("Virtual", comment: "")
        }
    }

    private func detail(_ kind: BatterySensorKind) -> String {
        switch kind {
        case .bms: NSLocalizedString("shown · trend basis", comment: "")
        case .cellMax: NSLocalizedString("SMC thermistor max", comment: "")
        case .virtual: NSLocalizedString("BMS estimate", comment: "")
        }
    }
}


struct SensorValueRow: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.insetFill)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value))
    }
}

struct TrendTile: View {
    var title: String
    var value: String
    var detail: String
    var series: [Double]
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint.opacity(0.85))
                    .frame(width: 7, height: 7)
                Text(LocalizedStringKey(title))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            SparklineView(values: series, tint: tint)
                .frame(height: 40)
            Text(LocalizedStringKey(detail))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .softPanel()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(title)))
        .accessibilityValue(Text("\(value), \(detail)"))
    }
}

struct SparklineView: View {
    var values: [Double]
    var tint: Color

    private let lineWidth: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(tint.opacity(0.08))
                sparklinePath(in: proxy.size)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }

    private func sparklinePath(in size: CGSize) -> Path {
        var path = Path()
        guard size.width > 0, size.height > 0 else { return path }
        let fractions = SparklineScale.fractions(values)
        guard !fractions.isEmpty else { return path }

        // Inset the vertical range by the stroke width so a line at either
        // extreme (or a centered flat line) is never clipped by the rounded frame.
        let inset = lineWidth / 2
        let usableHeight = max(size.height - lineWidth, 0)
        func y(for fraction: Double) -> CGFloat {
            size.height - inset - CGFloat(fraction) * usableHeight
        }

        // A single sample has no horizontal extent: draw a flat line across the width
        // so a freshly-started series still shows something instead of a blank box.
        guard fractions.count > 1 else {
            let midY = y(for: fractions[0])
            path.move(to: CGPoint(x: 0, y: midY))
            path.addLine(to: CGPoint(x: size.width, y: midY))
            return path
        }

        for index in fractions.indices {
            let x = CGFloat(index) / CGFloat(fractions.count - 1) * size.width
            let point = CGPoint(x: x, y: y(for: fractions[index]))
            if index == fractions.startIndex {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

struct MetricTile: View {
    var title: String
    var value: String
    var detail: String = ""
    var tint: Color
    /// Free-form name values (e.g. a filename) keep full size and middle-truncate
    /// instead of shrinking via monospacedDigit + scaling, so numeric siblings in a
    /// row keep matching value baselines.
    var valueIsName: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint.opacity(0.85))
                    .frame(width: 7, height: 7)
                Text(LocalizedStringKey(title))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Group {
                if valueIsName {
                    Text(value)
                        .truncationMode(.middle)
                } else {
                    Text(value)
                        .monospacedDigit()
                        .minimumScaleFactor(0.72)
                }
            }
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .lineLimit(1)
            if !detail.isEmpty {
                Text(LocalizedStringKey(detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.cardFill)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.subtleStroke))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.panelShadow, radius: 2, x: 0, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(title)))
        .accessibilityValue(Text(detail.isEmpty ? value : "\(value), \(detail)"))
    }
}

