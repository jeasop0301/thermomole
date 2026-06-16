import SwiftUI
import ThermoMoleCore
import UniformTypeIdentifiers

struct AnalyzeTab: View {
    @ObservedObject var model: AppModel
    @State private var pendingTrashEntry: DiskEntry?

    private var summary: DiskAnalysisSummary {
        DiskAnalysisSummary(scopeURL: model.diskAnalysisPath.currentURL, entries: model.diskEntries)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                PageHeader(title: "Analyze", subtitle: "Follow storage from a wide branch into the heavy leaves.", symbol: "chart.pie")
                Spacer()
                OperationStatePill(state: model.analyzeState)
                if model.analyzeState.isRunning {
                    Button {
                        model.cancelAnalyze()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                }
                Button {
                    chooseFolder()
                } label: {
                    Label("Choose Folder", systemImage: "folder.badge.gearshape")
                }
                .disabled(model.analyzeState.isRunning)
                Button {
                    model.analyzeHome()
                } label: {
                    if model.analyzeState.isRunning {
                        Label("Analyzing", systemImage: "hourglass")
                    } else {
                        Label("Map Home", systemImage: "chart.pie")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.analyzeState.isRunning)
            }

            HStack(alignment: .top, spacing: 12) {
                MetricTile(title: "Entries", value: "\(summary.entryCount)", tint: Color.oceanAccent)
                MetricTile(title: "Mapped Size", value: formatBytes(summary.totalBytes), detail: "visible safe roots", tint: Color.leafAccent)
                MetricTile(title: "Largest", value: summary.largestEntry?.url.lastPathComponent ?? "--", detail: summary.largestEntry.map { formatBytes($0.sizeBytes) } ?? "", tint: .gray, valueIsName: true)
            }

            DiskBreadcrumbBar(
                path: model.diskAnalysisPath,
                isBusy: model.analyzeState.isRunning,
                goUp: { model.analyzeParentDiskURL() },
                select: { model.analyzeDiskBreadcrumb($0) }
            )

            if model.analyzeState.isRunning {
                ProgressPanel(title: "Analyzing Disk", message: model.analyzeState.message)
            } else if model.diskEntries.isEmpty {
                ContentUnavailableView("No Disk Map", systemImage: "chart.pie", description: Text("Map Home or choose a folder to rank large files and folders."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    DiskTreemapView(items: DiskTreemapItem.items(from: model.diskEntries, limit: 18)) { item in
                        if item.entry.isDirectory {
                            model.analyzeDiskEntry(item.entry)
                        }
                    }
                    .frame(minWidth: 300)

                    List(model.diskEntries) { entry in
                        HStack {
                            Image(systemName: entry.isDirectory ? "folder" : "doc")
                                .foregroundStyle(entry.isDirectory ? Color.oceanAccent : .secondary)
                            Text(entry.url.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .layoutPriority(1)
                            DiskUsageBar(value: entry.sizeBytes, maxValue: model.diskEntries.first?.sizeBytes ?? entry.sizeBytes)
                                .frame(minWidth: 60, idealWidth: 120, maxWidth: 150)
                            Spacer()
                            Text(formatBytes(entry.sizeBytes))
                                .monospacedDigit()
                            if entry.isDirectory {
                                IconButton(systemName: "arrow.down.right.circle", help: "Analyze folder") {
                                    model.analyzeDiskEntry(entry)
                                }
                            }
                            IconButton(systemName: "folder", help: "Reveal in Finder") {
                                revealInFinder(entry.url)
                            }
                            if model.canTrashDiskEntry(entry) {
                                IconButton(systemName: "trash", help: "Move to Trash") {
                                    pendingTrashEntry = entry
                                }
                                .disabled(model.analyzeState.isRunning)
                            } else {
                                Image(systemName: "lock")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 26, height: 26)
                                    .help("Protected path")
                                    .accessibilityLabel(Text("Protected path"))
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(minWidth: 420)
                }
            }

            if !model.diskTrashLog.isEmpty {
                DiskEntryTrashLogView(results: Array(model.diskTrashLog.prefix(6)))
            }
        }
        .padding(22)
        .background(Color.appBackground)
        .alert(item: $pendingTrashEntry) { entry in
            let summary = DiskTrashConfirmationSummary(entry: entry)
            return Alert(
                title: Text(summary.title),
                message: Text(summary.confirmationMessage),
                primaryButton: .destructive(Text("Move to Trash")) {
                    model.trashDiskEntry(entry)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Analyze"
        panel.message = "Choose a folder to analyze."
        if panel.runModal() == .OK, let url = panel.url {
            model.analyzeFolder(url)
        }
    }
}

struct DiskEntryTrashLogView: View {
    var results: [DiskEntryTrashResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Analyze Trash Log")
                    .font(.headline)
                Spacer()
                Text("\(results.count) recent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(results) { result in
                HStack(spacing: 10) {
                    Image(systemName: symbol(for: result.status))
                        .foregroundStyle(color(for: result.status))
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.entry.url.lastPathComponent)
                            .lineLimit(1)
                        Text(result.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(formatBytes(result.entry.sizeBytes))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
        .padding(14)
        .softPanel()
    }

    private func symbol(for status: CleanupOperationStatus) -> String {
        switch status {
        case .succeeded: "checkmark.circle.fill"
        case .skipped: "exclamationmark.triangle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    private func color(for status: CleanupOperationStatus) -> Color {
        switch status {
        case .succeeded: Color.leafAccent
        case .skipped: Color.amberAccent
        case .failed: .red
        }
    }
}


struct DiskBreadcrumbBar: View {
    var path: DiskAnalysisPath
    var isBusy: Bool
    var goUp: () -> Void
    var select: (DiskBreadcrumb) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: goUp) {
                Image(systemName: "chevron.up")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .disabled(!path.canGoUp || isBusy)
            .help("Analyze parent folder")
            .accessibilityLabel(Text("Analyze parent folder"))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(path.breadcrumbs) { breadcrumb in
                        Button {
                            select(breadcrumb)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: breadcrumb.url == path.rootURL ? "house" : "folder")
                                    .font(.caption)
                                Text(breadcrumb.title)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isBusy || breadcrumb.url == path.currentURL)
                        .accessibilityLabel(Text("Open \(breadcrumb.title)"))
                        .accessibilityHint(Text(breadcrumb.url == path.currentURL ? "Current folder" : "Analyze this folder"))
                    }
                }
            }
        }
        .padding(10)
        .softPanel()
    }
}

struct DiskTreemapView: View {
    var items: [DiskTreemapItem]
    var select: (DiskTreemapItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Treemap")
                .font(.headline)
            GeometryReader { proxy in
                if items.isEmpty {
                    Text("No sized items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let columns = treemapColumns(for: proxy.size.width)
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(items) { item in
                            Button {
                                select(item)
                            } label: {
                                DiskTreemapCell(item: item)
                                    .frame(height: treemapCellHeight(item, in: proxy.size))
                            }
                            .buttonStyle(.plain)
                            .disabled(!item.entry.isDirectory)
                            .help(item.entry.isDirectory ? "Analyze folder" : "File")
                            .accessibilityLabel(Text(item.entry.isDirectory ? "Analyze folder \(item.entry.url.lastPathComponent)" : "File \(item.entry.url.lastPathComponent)"))
                            .accessibilityValue(Text(formatBytes(item.entry.sizeBytes)))
                        }
                    }
                }
            }
        }
        .padding(14)
        .softPanel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Disk treemap"))
        .accessibilityValue(Text("\(items.count) entries"))
    }

    private func treemapColumns(for width: CGFloat) -> [GridItem] {
        let count = max(2, min(4, Int(width / 150)))
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    private func treemapCellHeight(_ item: DiskTreemapItem, in size: CGSize) -> CGFloat {
        let base = max(86, min(120, size.height / 4))
        if item.isLargest { return base + 34 }
        return base + CGFloat(item.ratio) * 64
    }
}

struct DiskTreemapCell: View {
    var item: DiskTreemapItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: item.entry.isDirectory ? "folder.fill" : "doc.fill")
                    .foregroundStyle(item.entry.isDirectory ? Color.oceanAccent : .secondary)
                Spacer()
                Text("\(Int((item.ratio * 100).rounded()))%")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.entry.url.lastPathComponent)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .truncationMode(.middle)
                .multilineTextAlignment(.leading)
            Text(formatBytes(item.entry.sizeBytes))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(item.entry.isDirectory ? Color.oceanAccent.opacity(0.11) : Color.insetFill)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(item.isLargest ? Color.thermoAccent.opacity(0.55) : Color.subtleStroke))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(item.entry.url.lastPathComponent))
        .accessibilityValue(Text("\(formatBytes(item.entry.sizeBytes)), \(Int((item.ratio * 100).rounded())) percent of shown items"))
    }
}



struct DiskUsageBar: View {
    var value: UInt64
    var maxValue: UInt64

    var body: some View {
        GeometryReader { proxy in
            let width = value > 0 ? max(3, proxy.size.width * ratio) : 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.16))
                Capsule()
                    .fill(Color.thermoAccent)
                    .frame(width: width)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    private var ratio: CGFloat {
        guard maxValue > 0 else { return 0 }
        return min(max(CGFloat(Double(value) / Double(maxValue)), 0), 1)
    }
}
