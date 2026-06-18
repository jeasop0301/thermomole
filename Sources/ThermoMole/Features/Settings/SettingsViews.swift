import SwiftUI
import ThermoMoleCore
import ThermoMoleAppCore

struct SettingsTab: View {
    @ObservedObject var model: AppModel
    let settings: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TabHeader(subtitle: "Menu bar readings, local permissions, and reversible defaults.") {}

                SettingsPanel(title: "Menu Bar Metrics", symbol: "menubar.rectangle") {
                    ForEach(metricRows) { metric in
                        SettingsRow(accent: model.menuBarMetrics.contains(metric)) {
                            Toggle(metric.label, isOn: binding(for: metric))
                                .toggleStyle(.checkbox)
                            Spacer()
                            if model.menuBarMetrics.contains(metric) {
                                Text("\((model.menuBarMetrics.firstIndex(of: metric) ?? 0) + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                IconButton(systemName: "chevron.up", help: "Move up") {
                                    model.moveMenuBarMetric(metric, direction: .up)
                                }
                                IconButton(systemName: "chevron.down", help: "Move down") {
                                    model.moveMenuBarMetric(metric, direction: .down)
                                }
                            }
                        }
                    }
                }

                SettingsPanel(title: "App Presence", symbol: "macwindow") {
                    SettingsRow {
                        Toggle("Show Dock Icon", isOn: Binding {
                            settings.showsDockIcon
                        } set: { isOn in
                            settings.setDockIconVisible(isOn)
                        })
                        .toggleStyle(.switch)
                        Spacer()
                    }
                    SettingsRow {
                        Toggle("Launch at Login", isOn: Binding {
                            settings.launchAtLoginEnabled
                        } set: { isOn in
                            settings.setLaunchAtLogin(isOn)
                        })
                        .toggleStyle(.switch)
                        Spacer()
                    }
                    SettingsInfoRow(title: "Launch Status", value: settings.launchAtLoginStatusText)
                }

                SettingsPanel(title: "Longevity Alerts", symbol: "bell.badge") {
                    SettingsRow {
                        Toggle("System notifications", isOn: Binding {
                            model.notificationsEnabled
                        } set: { isOn in
                            model.setNotificationsEnabled(isOn)
                        })
                        .toggleStyle(.switch)
                        Spacer()
                    }
                    Label("Quietly alerts you when charging-while-hot, sustained heat, long high-charge dwell, or low storage put the Mac's lifespan at risk. Throttled, and silent 22:00–07:00.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                SettingsPanel(title: "Temperature Policy", symbol: "thermometer.medium") {
                    SettingsInfoRow(title: "Battery source", value: "AppleSmartBattery (BMS) — shown")
                    SettingsInfoRow(title: "Hottest cell", value: "SMC TB max — upper bound")
                    SettingsInfoRow(title: "VirtualTemperature", value: "Shown as reference")
                    SettingsInfoRow(title: "Warnings", value: "\(Int(ThermalThresholds.batteryCautionC))°C caution · \(Int(ThermalThresholds.batteryHotC))°C hot")
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.appBackground)
    }

    private var metricRows: [MenuBarMetric] {
        model.menuBarMetrics + MenuBarMetric.allCases.filter { !model.menuBarMetrics.contains($0) }
    }

    private func binding(for metric: MenuBarMetric) -> Binding<Bool> {
        Binding {
            model.menuBarMetrics.contains(metric)
        } set: { isOn in
            model.setMenuBarMetric(metric, enabled: isOn)
        }
    }
}

struct SettingsPanel<Content: View>: View {
    var title: String
    var symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)
            VStack(spacing: 8) {
                content
            }
        }
        .padding(14)
        .softPanel()
    }
}

struct SettingsRow<Content: View>: View {
    var accent: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(accent ? Color.thermoAccent.opacity(0.10) : Color.insetFill)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent ? Color.thermoAccent.opacity(0.25) : Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SettingsInfoRow: View {
    var title: String
    var value: String

    var body: some View {
        SettingsRow {
            Text(title)
                .font(.callout.weight(.medium))
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
