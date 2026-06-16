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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    PageHeader(title: "Status", subtitle: "Battery heat, CPU warmth, and memory pressure without the noise.", symbol: "gauge.with.dots.needle.67percent")
                    Spacer()
                    FreshnessChip(sampledAt: model.snapshot.sampledAt)
                    Button {
                        model.refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if statusBrief.isChargingWhileHot {
                    ChargeWhileHotBanner()
                }

                StatusBriefPanel(brief: statusBrief)

                ThermalExposureCard(
                    summary: model.todayExposure,
                    warningLevel: model.snapshot.thermal.batteryWarningLevel
                )

                ThermalOverviewPanel(snapshot: model.snapshot)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                    TrendCard(title: "CPU Temp", value: formatTemperaturePrecise(model.snapshot.thermal.cpuDisplayC), series: model.statusHistory.cpuTemperatureSeries, tint: .orange)
                    TrendCard(title: "Battery Temp", value: formatTemperaturePrecise(model.snapshot.thermal.batteryDisplayC), series: model.statusHistory.batteryTemperatureSeries, tint: batteryColor(model.snapshot.thermal.batteryWarningLevel))
                    TrendCard(title: "Memory", value: "\(model.snapshot.memory.usedPercent)%", series: model.statusHistory.memoryPercentSeries, tint: Color.oceanAccent)
                    TrendCard(title: "CPU Load", value: "\(Int(model.snapshot.cpu.usagePercent.rounded()))%", series: model.statusHistory.cpuUsageSeries, tint: Color.plumAccent)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    MetricTile(title: "CPU Temperature", value: formatTemperature(model.snapshot.thermal.cpuDisplayC), detail: cpuSourceLabel(model.snapshot.thermal.cpuTemperatureSource), tint: .orange)
                    MetricTile(title: "Memory", value: "\(model.snapshot.memory.usedPercent)%", detail: model.snapshot.memory.pressure.rawValue.capitalized, tint: Color.oceanAccent)
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

                ProcessTable(processes: model.snapshot.topProcesses)
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Last 7 days (min ≥35°)").font(.caption2).foregroundStyle(.secondary)
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


struct ThermalOverviewPanel: View {
    var snapshot: SystemSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Real battery pack", systemImage: "battery.100percent")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(formatTemperaturePrecise(snapshot.thermal.batteryDisplayC))
                        .font(.system(size: 46, weight: .semibold, design: .rounded))
                        .foregroundStyle(batteryColor(snapshot.thermal.batteryWarningLevel))
                        .monospacedDigit()
                    Text("AppleSmartBattery Temperature is shown here. VirtualTemperature stays out of the reading.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        SourceChip(title: "Battery", value: batterySourceLabel(snapshot.thermal.batteryTemperatureSource))
                        SourceChip(title: "CPU", value: cpuSourceLabel(snapshot.thermal.cpuTemperatureSource))
                    }
                }

                Spacer(minLength: 12)

                VStack(alignment: .leading, spacing: 8) {
                    Label("CPU warmth", systemImage: "cpu")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(formatTemperaturePrecise(snapshot.thermal.cpuDisplayC))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange)
                        .monospacedDigit()
                    Text(cpuSourceLabel(snapshot.thermal.cpuTemperatureSource))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("\(snapshot.chipName) · \(snapshot.modelIdentifier)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .frame(width: 190, alignment: .leading)

                VStack(spacing: 4) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(healthColor(snapshot.health.band).opacity(0.14))
                        Text("\(snapshot.health.value)")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(healthColor(snapshot.health.band))
                            .monospacedDigit()
                    }
                    .frame(width: 74, height: 74)
                    Label(conditionTitle(systemCondition(for: snapshot)), systemImage: conditionSymbol(systemCondition(for: snapshot)))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(conditionColor(systemCondition(for: snapshot)))
                        .lineLimit(1)
                }
            }

            Divider()

            HStack(spacing: 12) {
                OverviewReading(title: "CPU", value: formatTemperaturePrecise(snapshot.thermal.cpuDisplayC), tint: .orange)
                OverviewReading(title: "Battery", value: formatTemperaturePrecise(snapshot.thermal.batteryIORegC), tint: batteryColor(snapshot.thermal.batteryWarningLevel))
                OverviewReading(title: "SMC TB Max", value: formatTemperaturePrecise(snapshot.thermal.batteryCellMaxC), tint: Color.plumAccent)
                OverviewReading(title: "Memory", value: "\(snapshot.memory.usedPercent)%", tint: Color.oceanAccent)
            }

            if snapshot.thermal.hasBatterySensorMismatch {
                Label("SMC TB differs from AppleSmartBattery. ThermoMole displays the physical AppleSmartBattery reading.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .softPanel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Thermal overview"))
    }
}

struct SourceChip: View {
    var title: String
    var value: String

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.caption)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.insetFill)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value))
    }
}

struct OverviewReading: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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

struct BatteryProtectionPanel: View {
    var snapshot: SystemSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Battery Pack", systemImage: "battery.100percent.bolt")
                    .font(.headline)
                Spacer()
                Text(formatTemperaturePrecise(snapshot.thermal.batteryDisplayC))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(batteryColor(snapshot.thermal.batteryWarningLevel))
                    .monospacedDigit()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                SensorValueRow(title: "Displayed", value: batterySourceLabel(snapshot.thermal.batteryTemperatureSource))
                SensorValueRow(title: "AppleSmartBattery", value: formatTemperaturePrecise(snapshot.thermal.batteryIORegC))
                SensorValueRow(title: "SMC TB Max", value: formatTemperaturePrecise(snapshot.thermal.batteryCellMaxC))
                SensorValueRow(title: "Warning Lines", value: "\(Int(ThermalThresholds.batteryCautionC))° / \(Int(ThermalThresholds.batteryHotC))°")
            }

            if snapshot.thermal.hasBatterySensorMismatch {
                Label("Diagnostic: SMC TB differs; displaying AppleSmartBattery Temperature.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .softPanel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Battery pack"))
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

struct TrendCard: View {
    var title: String
    var value: String
    var series: [Double]
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            SparklineView(values: series, tint: tint)
                .frame(height: 42)
        }
        .padding(14)
        .softPanel()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(value), \(series.count) samples"))
    }
}

struct SparklineView: View {
    var values: [Double]
    var tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(tint.opacity(0.08))
                sparklinePath(in: proxy.size)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }

    private func sparklinePath(in size: CGSize) -> Path {
        var path = Path()
        guard values.count > 1, size.width > 0, size.height > 0 else { return path }

        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let spread = max(maxValue - minValue, 1)

        for index in values.indices {
            let x = CGFloat(index) / CGFloat(values.count - 1) * size.width
            let normalized = (values[index] - minValue) / spread
            let y = size.height - CGFloat(normalized) * size.height
            let point = CGPoint(x: x, y: y)
            if index == values.startIndex {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

struct HealthHeader: View {
    var snapshot: SystemSnapshot

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(healthColor(snapshot.health.band).opacity(0.14))
                Text("\(snapshot.health.value)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(healthColor(snapshot.health.band))
            }
            .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text("ThermoMole")
                    .font(.title2.bold())
                Text("\(snapshot.chipName) · \(snapshot.modelIdentifier)")
                    .foregroundStyle(.secondary)
                Text("Uptime \(formatUptime(snapshot.uptimeSeconds)) · \(snapshot.macOSVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .softPanel()
    }
}

struct MetricTile: View {
    var title: String
    var value: String
    var detail: String = ""
    var tint: Color

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
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
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

struct ProcessTable: View {
    var processes: [ProcessSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Processes")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Name").foregroundStyle(.secondary)
                    Text("PID").foregroundStyle(.secondary)
                    Text("CPU").foregroundStyle(.secondary)
                    Text("Memory").foregroundStyle(.secondary)
                }
                ForEach(processes) { process in
                    GridRow {
                        Text(process.name).lineLimit(1)
                        Text("\(process.pid)").monospacedDigit()
                        Text("\(process.cpuPercent, specifier: "%.1f")%").monospacedDigit()
                        Text(formatBytes(process.memoryBytes)).monospacedDigit()
                    }
                }
            }
            .font(.caption)
        }
        .padding(14)
        .softPanel()
    }
}
