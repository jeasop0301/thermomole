import SwiftUI
import ThermoMoleCore

struct MenuBarPopoverView: View {
    @ObservedObject var model: AppModel
    var openMain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PopoverHeader(snapshot: model.snapshot)

            HStack {
                Spacer()
                BatteryTemperatureRing(temperatureC: model.snapshot.thermal.batteryDisplayC, diameter: 104)
                Spacer()
            }
            .padding(.vertical, 2)

            if StatusBrief(snapshot: model.snapshot).isChargingWhileHot {
                ChargeWhileHotBanner()
            }

            PopoverMetricStack(snapshot: model.snapshot)

            HStack(spacing: 6) {
                ThermalLevelGlyph(level: model.snapshot.thermal.batteryWarningLevel)
                Text("Today: \(Int((model.todayExposure.today.secondsAbove35 / 60).rounded())) min ≥35°")
                    .font(.thermoCaption).foregroundStyle(.secondary)
            }

            CompactProcessList(processes: Array(model.snapshot.topProcesses.prefix(5)))

            Divider()
            HStack {
                Button {
                    model.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Spacer()
                Button("Open ThermoMole", action: openMain)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 370)
        .background(.regularMaterial)
        .tint(Color.thermoAccent)
    }
}

struct PopoverHeader: View {
    var snapshot: SystemSnapshot

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(healthColor(snapshot.health.band).opacity(0.18))
                Text("\(snapshot.health.value)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(healthColor(snapshot.health.band))
            }
            .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text("ThermoMole")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                Text("Quietly watching \(snapshot.modelIdentifier)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                FreshnessChip(sampledAt: snapshot.sampledAt, isCompact: true)
                Label(conditionTitle(systemCondition(for: snapshot)), systemImage: conditionSymbol(systemCondition(for: snapshot)))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(conditionColor(systemCondition(for: snapshot)))
            }
            Spacer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("ThermoMole health score \(snapshot.health.value), \(conditionTitle(systemCondition(for: snapshot)))"))
        .accessibilityValue(Text(StatusFreshness(sampledAt: snapshot.sampledAt).accessibilityLabel))
    }
}

struct FreshnessChip: View {
    var sampledAt: Date
    var isCompact = false

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            let freshness = StatusFreshness(sampledAt: sampledAt, now: context.date)
            Label {
                Text("\(freshness.title) · \(freshness.detail)")
            } icon: {
                Image(systemName: freshnessSymbol(freshness.level))
            }
            .font((isCompact ? Font.caption2 : Font.caption).weight(.semibold))
            .foregroundStyle(freshnessColor(freshness.level))
            .padding(.horizontal, isCompact ? 7 : 9)
            .padding(.vertical, isCompact ? 3 : 5)
            .background(freshnessColor(freshness.level).opacity(0.12))
            .clipShape(Capsule())
            .accessibilityLabel(Text(freshness.accessibilityLabel))
        }
    }
}

struct PopoverMetricStack: View {
    var snapshot: SystemSnapshot

    var body: some View {
        VStack(spacing: 0) {
            PopoverMetricRow(
                title: "CPU",
                value: formatTemperature(snapshot.thermal.cpuDisplayC),
                detail: cpuSourceLabel(snapshot.thermal.cpuTemperatureSource),
                tint: .orange
            )
            Divider().padding(.leading, 40)
            PopoverMetricRow(
                title: "Battery",
                value: formatTemperature(snapshot.thermal.batteryDisplayC),
                detail: batterySourceLabel(snapshot.thermal.batteryTemperatureSource),
                tint: batteryColor(snapshot.thermal.batteryWarningLevel)
            )
            Divider().padding(.leading, 40)
            PopoverMetricRow(
                title: "Memory",
                value: "\(snapshot.memory.usedPercent)%",
                detail: snapshot.memory.pressure.rawValue.capitalized,
                tint: Color.oceanAccent
            )
            Divider().padding(.leading, 40)
            PopoverMetricRow(
                title: "Load",
                value: "\(Int(snapshot.cpu.usagePercent.rounded()))%",
                detail: formatLoad(snapshot.cpu.loadAverage),
                tint: Color.plumAccent
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .softPanel()
    }
}

struct PopoverMetricRow: View {
    var title: String
    var value: String
    var detail: String
    var tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(value)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(value), \(detail)"))
    }
}

struct CompactProcessList: View {
    var processes: [ProcessSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Processes")
                .font(.headline)
            ForEach(processes) { process in
                HStack {
                    Text(process.name)
                        .lineLimit(1)
                    Spacer()
                Text("\(process.cpuPercent, specifier: "%.1f")%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(process.name))
            .accessibilityValue(Text("CPU \(process.cpuPercent, specifier: "%.1f") percent"))
        }
    }
        .padding(12)
        .softPanel()
    }
}
