import SwiftUI
import ThermoMoleCore
import ThermoMoleAppCore

struct SettingsTab: View {
    @ObservedObject var model: AppModel
    let settings: SettingsModel

    var body: some View {
        Form {
            Section("Menu Bar Metrics") {
                ForEach(metricRows) { metric in
                    HStack(spacing: 10) {
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

            Section("App Presence") {
                Toggle("Show Dock Icon", isOn: Binding {
                    settings.showsDockIcon
                } set: { settings.setDockIconVisible($0) })
                Toggle("Launch at Login", isOn: Binding {
                    settings.launchAtLoginEnabled
                } set: { settings.setLaunchAtLogin($0) })
                LabeledContent("Launch Status", value: settings.launchAtLoginStatusText)
            }

            Section("Longevity Alerts") {
                Toggle("System notifications", isOn: Binding {
                    model.notificationsEnabled
                } set: { model.setNotificationsEnabled($0) })
                Label("Quietly alerts you when charging-while-hot, sustained heat, long high-charge dwell, or low storage put the Mac's lifespan at risk. Throttled, and silent 22:00–07:00.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Temperature Policy") {
                infoRow("Battery source", "AppleSmartBattery (BMS) — shown")
                infoRow("Hottest cell", "SMC TB max — upper bound")
                infoRow("VirtualTemperature", "Shown as reference")
                infoRow("Warnings", String(format: NSLocalizedString("%d°C caution · %d°C hot", comment: "Battery temperature warning thresholds"), Int(ThermalThresholds.batteryCautionC), Int(ThermalThresholds.batteryHotC)))
            }
        }
        .formStyle(.grouped)
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

    /// Read-only reference row. Both title and value go through LocalizedStringKey to preserve the
    /// previous SettingsInfoRow localization behavior (ko.lproj reference strings).
    private func infoRow(_ title: String, _ value: String) -> some View {
        LabeledContent {
            Text(LocalizedStringKey(value))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        } label: {
            Text(LocalizedStringKey(title))
        }
    }
}
