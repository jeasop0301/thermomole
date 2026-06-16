import SwiftUI
import ThermoMoleCore

enum AppSection: String, CaseIterable, Identifiable {
    case status
    case clean
    case software
    case optimize
    case analyze
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: "Status"
        case .clean: "Clean"
        case .software: "Software"
        case .optimize: "Optimize"
        case .analyze: "Analyze"
        case .settings: "Settings"
        }
    }

    var subtitle: String {
        switch self {
        case .status: "Battery heat, CPU warmth"
        case .clean: "Safe clutter review"
        case .software: "Apps and quiet starters"
        case .optimize: "Small repairs, staged"
        case .analyze: "Follow storage inward"
        case .settings: "Local choices"
        }
    }

    var symbol: String {
        switch self {
        case .status: "gauge.with.dots.needle.67percent"
        case .clean: "sparkles"
        case .software: "shippingbox"
        case .optimize: "wand.and.stars"
        case .analyze: "chart.pie"
        case .settings: "gearshape"
        }
    }

    /// Initial tab; `THERMOMOLE_TAB=<rawValue>` overrides for dev/screenshot runs.
    static var initial: AppSection {
        if let raw = ProcessInfo.processInfo.environment["THERMOMOLE_TAB"],
           let section = AppSection(rawValue: raw) {
            return section
        }
        return .status
    }
}

struct MainWindowView: View {
    @ObservedObject var model: AppModel
    @State private var selection: AppSection = AppSection.initial

    var body: some View {
        VStack(spacing: 0) {
            AppToolbar(model: model)
            TabPillBar(selection: $selection)
            Rectangle()
                .fill(Color.subtleStroke)
                .frame(height: 1)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
        }
        .frame(minWidth: 1040, minHeight: 680)
        .background(Color.appBackground)
        .tint(Color.thermoAccent)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .status:
            StatusTab(model: model)
        case .clean:
            CleanTab(clean: model.clean)
        case .software:
            SoftwareTab(model: model)
        case .optimize:
            OptimizeTab(model: model)
        case .analyze:
            AnalyzeTab(model: model)
        case .settings:
            SettingsTab(model: model)
        }
    }
}

struct AppToolbar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "thermometer.medium")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Color.thermoAccent)
                .frame(width: 30, height: 30)
                .background(Color.iconBadgeFill)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            Text("ThermoMole")
                .font(.system(.headline, design: .rounded).weight(.semibold))

            BatteryPackChip(
                temperatureC: model.snapshot.thermal.batteryDisplayC,
                level: model.snapshot.thermal.batteryWarningLevel
            )

            Spacer()

            FreshnessChip(sampledAt: model.snapshot.sampledAt)
            Button {
                model.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(Color.appSidebar)
    }
}

struct BatteryPackChip: View {
    var temperatureC: Double?
    var level: TemperatureWarningLevel

    var body: some View {
        Label(formatTemperaturePrecise(temperatureC), systemImage: "battery.100percent")
            .font(.callout.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(batteryColor(level))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(batteryColor(level).opacity(0.12))
            .clipShape(Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Battery pack temperature"))
            .accessibilityValue(Text(formatTemperaturePrecise(temperatureC)))
    }
}

struct TabPillBar: View {
    @Binding var selection: AppSection

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(AppSection.allCases) { section in
                    TabPill(section: section, isSelected: selection == section) {
                        selection = section
                    }
                }
            }
            .padding(4)
            .background(Color.insetFill)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.subtleStroke))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
    }
}

struct TabPill: View {
    var section: AppSection
    var isSelected: Bool
    var select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 6) {
                Image(systemName: section.symbol)
                    .font(.system(size: 13, weight: .semibold))
                Text(section.title)
                    .font(.callout.weight(.medium))
            }
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .background(isSelected ? Color.thermoAccent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(section.title))
        .accessibilityHint(Text(isSelected ? "Current section" : "Open section"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct TabHeader<Actions: View>: View {
    var subtitle: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .center) {
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            actions()
        }
    }
}
