import SwiftUI
import ThermoMoleCore

enum AppSection: String, CaseIterable, Identifiable {
    case status
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: NSLocalizedString("Status", comment: "")
        case .settings: NSLocalizedString("Settings", comment: "")
        }
    }

    var subtitle: String {
        switch self {
        case .status: NSLocalizedString("Battery heat, CPU warmth", comment: "")
        case .settings: NSLocalizedString("Local choices", comment: "")
        }
    }

    var symbol: String {
        switch self {
        case .status: "gauge.with.dots.needle.67percent"
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
    @State private var selection: AppSection? = AppSection.initial

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar { toolbarContent }
        }
        .frame(minWidth: 1180, minHeight: 720)
        .tint(Color.thermoAccent)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .status {
        case .status:
            StatusTab(model: model)
        case .settings:
            SettingsTab(model: model, settings: model.settings)
        }
    }

    // Native window toolbar: live status chips + Refresh on the trailing side. The window title
    // ("Patina") is set on the NSWindow; the sidebar carries section navigation.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            BatteryPackChip(
                temperatureC: model.snapshot.thermal.batteryDisplayC,
                level: model.snapshot.thermal.batteryWarningLevel
            )
            FreshnessChip(sampledAt: model.snapshot.sampledAt)
            Button {
                model.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
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
