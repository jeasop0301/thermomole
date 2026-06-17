import SwiftUI
import ThermoMoleCore
import ThermoMoleAppCore

struct SettingsTab: View {
    @ObservedObject var model: AppModel
    let settings: SettingsModel

    private var doctorGuidance: DoctorGuidanceSummary {
        DoctorGuidanceSummary(report: model.doctorReport)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TabHeader(subtitle: "Menu bar readings, local permissions, and reversible defaults.") {}

                DoctorSettingsPanel(
                    report: model.doctorReport,
                    refresh: { model.refreshDoctorReport() },
                    refreshStatus: model.refresh,
                    openFullDiskAccess: model.openFullDiskAccessSettings
                )

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

                SettingsPanel(title: "Local App", symbol: "lock.laptopcomputer") {
                    SettingsInfoRow(title: "Dock", value: settings.showsDockIcon ? "Visible" : "Hidden by default")
                    SettingsInfoRow(title: "Full Disk Access", value: doctorGuidance.fullDiskAccessStatus)
                    SettingsInfoRow(title: "Scan mode", value: "Local only")
                    Text(doctorGuidance.fullDiskAccessDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    SettingsRow {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Diagnostic report")
                                .font(.callout.weight(.semibold))
                            Text("\(doctorGuidance.diagnosticScopeTitle): \(doctorGuidance.diagnosticIncludedLines.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Excludes: \(doctorGuidance.diagnosticExcludedLines.joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(doctorGuidance.sharingNote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if settings.diagnosticExportState.phase != .idle {
                            OperationStatePill(state: settings.diagnosticExportState)
                        }
                        if settings.diagnosticImportState.phase != .idle {
                            OperationStatePill(state: settings.diagnosticImportState)
                        }
                        Button {
                            chooseDiagnosticReportURL()
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            chooseDiagnosticImportURL()
                        } label: {
                            Label("Import", systemImage: "square.and.arrow.down")
                        }
                    }
                    if let summary = settings.importedDiagnosticSummary {
                        ImportedDiagnosticSummaryView(summary: summary)
                    }
                    if let lastError = model.lastError {
                        Text(lastError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                }

                ProtectedPathPolicyPanel(catalog: .default())

                OperationHistoryPanel(
                    entries: model.operationHistoryEntries,
                    error: model.operationHistoryError,
                    refresh: model.loadOperationHistory,
                    revealLog: model.revealOperationHistoryLog
                )
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

    private func chooseDiagnosticReportURL() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ThermoMole-Diagnostic.json"
        panel.prompt = "Export"
        panel.message = "Save a local ThermoMole diagnostic report."
        if panel.runModal() == .OK, let url = panel.url {
            settings.exportDiagnosticReport(to: url)
        }
    }

    private func chooseDiagnosticImportURL() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Import"
        panel.message = "Open a ThermoMole diagnostic report."
        if panel.runModal() == .OK, let url = panel.url {
            settings.importDiagnosticReport(from: url)
        }
    }
}

struct ProtectedPathPolicyPanel: View {
    var catalog: ProtectedPathCatalog

    var body: some View {
        SettingsPanel(title: "Protected Items", symbol: "shield.lefthalf.filled") {
            Text(catalog.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ProtectedPathList(
                title: "Never Trash",
                value: "\(catalog.protectedRoots.count) roots",
                paths: catalog.protectedRoots
            )
            ProtectedPathList(
                title: "Trash Allowed Under",
                value: "\(catalog.allowedDeletePrefixes.count) prefixes",
                paths: catalog.allowedDeletePrefixes
            )
            ProtectedPathList(
                title: "Default Scan Skips",
                value: "\(catalog.defaultScanSkips.count) roots",
                paths: catalog.defaultScanSkips
            )
        }
    }
}

struct ProtectedPathList: View {
    var title: String
    var value: String
    var paths: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(paths, id: \.self) { path in
                    Text(displayPath(path))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.cardFill)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }
        }
        .padding(10)
        .background(Color.insetFill)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if path == home { return "~" }
        if path.hasPrefix("\(home)/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

struct ImportedDiagnosticSummaryView: View {
    var summary: DiagnosticReportSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("Imported Report", systemImage: "doc.text.magnifyingglass")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(summary.generatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                SensorValueRow(title: "Version", value: summary.appVersion)
                SensorValueRow(title: "Schema", value: "\(summary.schemaVersion)")
                SensorValueRow(title: "Health", value: "\(summary.healthScore)")
                SensorValueRow(title: "Operations", value: "\(summary.recentOperationCount)")
            }
            Text(summary.machine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(summary.doctorSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .background(Color.insetFill)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Imported diagnostic report"))
    }
}

struct OperationHistoryPanel: View {
    var entries: [OperationHistoryEntry]
    var error: String?
    var refresh: () -> Void
    var revealLog: () -> Void

    var body: some View {
        SettingsPanel(title: "Operation History", symbol: "clock.arrow.circlepath") {
            HStack {
                Text("\(entries.count) recent operations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Button {
                    revealLog()
                } label: {
                    Label("Reveal Log", systemImage: "folder")
                }
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.insetFill)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if entries.isEmpty {
                Text("No operations logged yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.insetFill)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 8) {
                    ForEach(entries.prefix(8)) { entry in
                        OperationHistoryRow(entry: entry)
                    }
                }
            }
        }
    }
}

struct OperationHistoryRow: View {
    var entry: OperationHistoryEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(entry.kind.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.insetFill)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Text(entry.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.status.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Text("\(entry.itemCount) · \(formatBytes(entry.bytes))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(entry.executedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(10)
        .background(Color.insetFill)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var symbol: String {
        switch entry.status {
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .skipped: "minus.circle.fill"
        case .mixed: "exclamationmark.circle.fill"
        }
    }

    private var color: Color {
        switch entry.status {
        case .succeeded: Color.leafAccent
        case .failed: .red
        case .skipped: .secondary
        case .mixed: Color.amberAccent
        }
    }
}

struct DoctorSettingsPanel: View {
    var report: DoctorReport
    var refresh: () -> Void
    var refreshStatus: () -> Void
    var openFullDiskAccess: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: report.isAllClear ? "checkmark.seal.fill" : "stethoscope")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(report.isAllClear ? Color.leafAccent : Color.amberAccent)
                    .frame(width: 34, height: 34)
                    .background((report.isAllClear ? Color.leafAccent : Color.amberAccent).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Doctor")
                        .font(.headline)
                    Text(report.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

            VStack(spacing: 8) {
                ForEach(report.checks) { check in
                    DoctorCheckRow(
                        check: check,
                        refreshStatus: refreshStatus,
                        openFullDiskAccess: openFullDiskAccess
                    )
                }
            }
        }
        .padding(14)
        .softPanel()
    }
}

struct DoctorCheckRow: View {
    var check: DoctorCheck
    var refreshStatus: () -> Void
    var openFullDiskAccess: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.title)
                    .font(.callout.weight(.semibold))
                Text(check.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if check.action == .openFullDiskAccess {
                Button {
                    openFullDiskAccess()
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                }
            } else if check.action == .refreshStatusSnapshot {
                Button {
                    refreshStatus()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            } else if check.action != .none {
                Text(doctorActionLabel(check.action))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.insetFill)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var color: Color {
        switch check.severity {
        case .ok: Color.leafAccent
        case .warning: Color.amberAccent
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








