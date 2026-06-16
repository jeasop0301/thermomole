import SwiftUI
import ThermoMoleCore

struct SoftwareTab: View {
    @ObservedObject var model: AppModel
    @State private var selectedView = SoftwareViewMode.apps
    @State private var pendingUninstallApp: InstalledApp?
    @State private var searchQuery = ""

    private var filteredApps: [InstalledApp] {
        SoftwareInventoryFilter(query: searchQuery).filter(model.installedApps)
    }

    private var filteredStartupItems: [StartupItem] {
        SoftwareInventoryFilter(query: searchQuery).filter(model.startupItems)
    }

    private var summary: SoftwareSummary {
        SoftwareSummary(apps: model.installedApps, startupItems: model.startupItems)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TabHeader(subtitle: "Apps, versions, and launch items gathered in one quiet list.") {
                OperationStatePill(state: model.softwareState)
                Button {
                    model.loadSoftware()
                } label: {
                    if model.softwareState.isRunning {
                        Label("Loading", systemImage: "hourglass")
                    } else if model.installedApps.isEmpty && model.startupItems.isEmpty {
                        Label("Gather Apps", systemImage: "arrow.down.circle")
                    } else {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.softwareState.isRunning)
            }

            HStack(spacing: 12) {
                MetricTile(title: "Installed Apps", value: "\(summary.appCount)", tint: Color.oceanAccent)
                MetricTile(title: "Startup Items", value: "\(summary.startupItemCount)", detail: "\(summary.enabledStartupItemCount) enabled", tint: Color.plumAccent)
                MetricTile(title: "Uninstall Candidates", value: "\(summary.uninstallCandidateCount)", detail: "Trash with confirmation", tint: .yellow)
            }

            Picker("Software View", selection: $selectedView) {
                ForEach(SoftwareViewMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            SearchField(
                text: $searchQuery,
                placeholder: "Search apps, bundle IDs, versions, startup labels, or paths"
            )

            if model.softwareState.isRunning {
                ProgressPanel(title: "Loading Apps", message: model.softwareState.message)
            } else if selectedView == .apps && model.installedApps.isEmpty {
                ContentUnavailableView("No App Inventory", systemImage: "shippingbox", description: Text("Load Apps to scan application bundles."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedView == .startup && model.startupItems.isEmpty {
                ContentUnavailableView("No Startup Items", systemImage: "powerplug", description: Text("Load Apps to scan LaunchAgent and LaunchDaemon plists."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedView == .apps && filteredApps.isEmpty {
                ContentUnavailableView("No Matching Apps", systemImage: "magnifyingglass", description: Text("Clear the search field or try a bundle identifier, version, or path."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedView == .startup && filteredStartupItems.isEmpty {
                ContentUnavailableView("No Matching Startup Items", systemImage: "magnifyingglass", description: Text("Clear the search field or try a label, program, domain, or path."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedView == .startup {
                StartupItemList(items: filteredStartupItems)
            } else {
                InstalledAppList(
                    apps: filteredApps,
                    uninstall: { pendingUninstallApp = $0 }
                )
            }

            if !model.appUninstallLog.isEmpty {
                AppUninstallLogView(results: Array(model.appUninstallLog.prefix(6)))
            }
        }
        .padding(22)
        .background(Color.appBackground)
        .task {
            if model.installedApps.isEmpty && model.startupItems.isEmpty && !model.softwareState.isRunning {
                model.loadSoftware()
            }
        }
        .alert(item: $pendingUninstallApp) { app in
            let summary = AppUninstallConfirmationSummary(app: app)
            return Alert(
                title: Text(summary.title),
                message: Text(summary.confirmationMessage),
                primaryButton: .destructive(Text("Move to Trash")) {
                    model.uninstallApp(app)
                },
                secondaryButton: .cancel()
            )
        }
    }
}

enum SoftwareViewMode: String, CaseIterable, Identifiable {
    case apps
    case startup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apps: "Apps"
        case .startup: "Startup"
        }
    }
}

struct InstalledAppList: View {
    var apps: [InstalledApp]
    var uninstall: (InstalledApp) -> Void

    var body: some View {
        List(apps) { app in
            HStack(spacing: 10) {
                Image(systemName: "app.dashed")
                    .foregroundStyle(Color.oceanAccent)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(app.name)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 8)
                        Text(app.version)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    Text(app.bundleIdentifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(app.bundlePath)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                IconButton(systemName: "folder", help: "Reveal in Finder") {
                    revealInFinder(URL(fileURLWithPath: app.bundlePath))
                }
                IconButton(systemName: "arrow.up.right.square", help: "Open app") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: app.bundlePath))
                }
                IconButton(systemName: "trash", help: "Move app to Trash") {
                    uninstall(app)
                }
            }
            .padding(.vertical, 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct StartupItemList: View {
    var items: [StartupItem]

    var body: some View {
        List(items) { item in
            HStack(spacing: 10) {
                Image(systemName: item.isEnabled ? "powerplug.fill" : "powerplug")
                    .foregroundStyle(item.isEnabled ? Color.leafAccent : .secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.label)
                        .font(.callout.weight(.semibold))
                    Text(item.program)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("\(item.domain.title) · \(item.plistPath)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                Text(item.isEnabled ? "Enabled" : "Disabled")
                    .font(.caption)
                    .foregroundStyle(item.isEnabled ? Color.leafAccent : .secondary)
                IconButton(systemName: "folder", help: "Reveal plist") {
                    revealInFinder(URL(fileURLWithPath: item.plistPath))
                }
            }
            .padding(.vertical, 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct AppUninstallLogView: View {
    var results: [AppUninstallResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Uninstall Log")
                    .font(.headline)
                Spacer()
                Text("\(results.count) recent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(results) { result in
                HStack(spacing: 10) {
                    Image(systemName: result.status == .succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.status == .succeeded ? Color.leafAccent : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.app.name)
                            .lineLimit(1)
                        Text(result.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(result.status.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
        .padding(14)
        .softPanel()
    }
}
