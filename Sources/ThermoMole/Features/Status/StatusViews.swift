import SwiftUI
import ThermoMoleCore

struct StatusTab: View {
    @ObservedObject var model: AppModel
    @State private var isShowingMemoryPurgeConfirmation = false

    private var memoryReport: MemoryDoctorReport {
        MemoryDoctorReport(
            memory: model.snapshot.memory,
            topProcesses: model.snapshot.topProcesses
        )
    }

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
                TabHeader(subtitle: "Battery heat, CPU warmth, and memory pressure without the noise.") {}

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
                    TrendTile(
                        title: "Memory",
                        value: "\(model.snapshot.memory.usedPercent)%",
                        detail: model.snapshot.memory.pressure.rawValue.capitalized,
                        series: model.statusHistory.memoryPercentSeries,
                        tint: Color.oceanAccent
                    )
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
                    MetricTile(title: "Disk", value: String(format: "%.0f%%", model.snapshot.disk.usedPercent), detail: "\(formatBytes(model.snapshot.disk.freeBytes)) free", tint: .teal)
                    MetricTile(title: "Network Down", value: "\(formatBytes(model.snapshot.network.receivedBytesPerSecond))/s", detail: "Up \(formatBytes(model.snapshot.network.sentBytesPerSecond))/s", tint: Color.leafAccent)
                    MetricTile(title: "Battery", value: "\(model.snapshot.battery.percent)%", detail: "\(model.snapshot.battery.healthPercent)% health · \(model.snapshot.battery.cycleCount) cycles", tint: .mint)
                    MetricTile(title: "Fan", value: model.snapshot.fanRPM > 0 ? "\(model.snapshot.fanRPM) RPM" : "Read-only", detail: "No fan control", tint: .gray)
                }

                MemoryDoctorPanel(
                    report: memoryReport,
                    state: model.memoryPurgeState,
                    runPurge: { isShowingMemoryPurgeConfirmation = true }
                )
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("Run advanced memory purge?", isPresented: $isShowingMemoryPurgeConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Run", role: .destructive) {
                model.runMemoryPurge()
            }
        } message: {
            Text(MemoryPurgePlan(report: memoryReport).confirmationMessage)
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
                exposureStat("Above 35°", minutes(summary.today.secondsAbove35))
                exposureStat("Above 40°", minutes(summary.today.secondsAbove40))
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
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text("\(value) min").font(.title3).monospacedDigit()
        }
    }
}

struct ThermalExposureWeekStrip: View {
    let days: [DailyThermalExposure]   // descending (today first); displayed chronologically

    private func minutes(_ s: TimeInterval) -> Int { Int((s / 60).rounded()) }

    var body: some View {
        let chronological = Array(days.reversed())
        let maxMinutes = max(1, chronological.map { minutes($0.secondsAbove35) }.max() ?? 1)
        let hasAnyExposure = chronological.contains { minutes($0.secondsAbove35) > 0 }
        VStack(alignment: .leading, spacing: 4) {
            Text("Last 7 days (min ≥35°)").font(.caption2).foregroundStyle(.secondary)
            if hasAnyExposure {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(chronological, id: \.day) { day in
                        let m = minutes(day.secondsAbove35)
                        let tint: Color = day.secondsAbove40 > 0 ? .red : (m > 0 ? .amberAccent : Color.secondary.opacity(0.3))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(tint)
                            .frame(width: 14, height: max(3, CGFloat(m) / CGFloat(maxMinutes) * 28))
                            .accessibilityLabel("\(day.day): \(m) minutes above 35 degrees")
                    }
                }
                .frame(height: 28, alignment: .bottom)
            } else {
                Text("No heat above 35° in the last 7 days")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(height: 28, alignment: .center)
                    .accessibilityLabel("No battery heat above 35 degrees in the last 7 days")
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
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text("\(value) min").font(.title3).monospacedDigit()
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
                            .accessibilityLabel("\(day.day): \(m) minutes at or above 80 percent on AC")
                    }
                }
                .frame(height: 28, alignment: .bottom)
            } else {
                Text("No high-charge dwell on AC in the last 7 days")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(height: 28, alignment: .center)
                    .accessibilityLabel("No high charge dwell on AC in the last 7 days")
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
        return .red
    }

    private var detailLine: String {
        guard let h = health else { return "Collecting daily readings…" }
        return "\(h.healthPercent)% health · \(h.cycleCount) cycles · \(h.maxCapacityMAh) mAh"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(tint.opacity(0.85)).frame(width: 7, height: 7)
                Text("Battery longevity").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let months = report?.projectedMonthsTo80 {
                    Text("~\(Int(months.rounded())) mo to 80%")
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
        .accessibilityValue(Text(report.map { "score \($0.score) of 100, \($0.healthPercent) percent health, \($0.cycleCount) cycles" } ?? "collecting"))
    }

    private func alertText(_ alert: BatteryLongevityAlert) -> String {
        switch alert {
        case .fastFade: "Fading fast"
        case .healthBelow80: "Below 80%"
        case .healthBelow60: "Below 60%"
        case .highCycleRate: "High cycle rate"
        }
    }
}

struct StatusBriefPanel: View {
    var brief: StatusBrief

    private var tint: Color {
        switch brief.mood {
        case .steady: Color.leafAccent
        case .watch: Color.amberAccent
        case .hot: .red
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
                    Text(brief.title)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                    Text(brief.detail)
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
        .accessibilityLabel(Text("Status summary \(brief.title)"))
        .accessibilityValue(Text(brief.detail))
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
                Text(signal.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(signal.value)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(signal.detail)
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
        .accessibilityLabel(Text(signal.title))
        .accessibilityValue(Text("\(signal.value), \(signal.detail)"))
    }
}

struct MemoryDoctorPanel: View {
    var report: MemoryDoctorReport
    var state: OperationState
    var runPurge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Memory Doctor")
                        .font(.headline)
                    Text(report.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(report.level.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(tint)
                    Text("\(report.memory.usedPercent)% used")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if report.allowsPurge {
                    Button {
                        runPurge()
                    } label: {
                        if state.isRunning {
                            Label("Running", systemImage: "hourglass")
                        } else {
                            Label("Advanced Purge", systemImage: "exclamationmark.triangle")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.isRunning)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                SensorValueRow(title: "Pressure", value: report.memory.pressure.rawValue.capitalized)
                SensorValueRow(title: "Compressed", value: formatBytes(report.memory.compressedBytes))
                SensorValueRow(title: "Free + Cache", value: formatBytes(report.memory.freeBytes))
                SensorValueRow(title: "Top Process", value: report.topMemoryProcess?.name ?? "None")
            }

            Label(report.allowsPurge ? "Advanced purge is available only after critical pressure confirmation." : "No RAM cleanup action is exposed while pressure is below critical.", systemImage: report.allowsPurge ? "exclamationmark.triangle" : "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            if state.phase != .idle {
                OperationStatePill(state: state)
            }
        }
        .padding(14)
        .softPanel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Memory Doctor"))
    }

    private var tint: Color {
        switch report.level {
        case .calm: Color.leafAccent
        case .watch: Color.amberAccent
        case .critical: .red
        }
    }

    private var symbol: String {
        switch report.level {
        case .calm: "memorychip"
        case .watch: "memorychip.fill"
        case .critical: "exclamationmark.triangle.fill"
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
                Text(title)
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
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .softPanel()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
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
                Text(title)
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
                Text(detail)
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
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(detail.isEmpty ? value : "\(value), \(detail)"))
    }
}

