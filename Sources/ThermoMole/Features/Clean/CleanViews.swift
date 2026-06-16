import SwiftUI
import ThermoMoleCore
import ThermoMoleAppCore

struct CleanTab: View {
    let clean: CleanModel
    @State private var isShowingCleanupConfirmation = false
    @State private var cleanupSearchQuery = ""
    @State private var selectedCleanupCategory: CleanupCategory?
    @State private var cleanupSort = CleanupReviewSort.largestFirst

    private var summary: CleanupReviewSummary {
        CleanupReviewSummary(clean.result)
    }

    private var filteredItems: [CleanupItem] {
        CleanupReviewFilter(
            query: cleanupSearchQuery,
            category: selectedCleanupCategory,
            sort: cleanupSort
        ).apply(to: clean.result.items)
    }

    private var filteredBytes: UInt64 {
        filteredItems.reduce(0) { $0 + $1.sizeBytes }
    }

    private var selectedVisibleCount: Int {
        filteredItems.filter { clean.selection.contains($0) }.count
    }

    private var confirmationSummary: CleanupConfirmationSummary {
        CleanupConfirmationSummary(result: clean.result, selection: clean.selection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TabHeader(subtitle: "Find safe cache clutter; nothing leaves without review.") {
                OperationStatePill(state: clean.state)
                Button {
                    Task { await clean.runScan() }
                } label: {
                    if clean.state.isRunning {
                        Label("Scanning", systemImage: "hourglass")
                    } else {
                        Label("Review Scan", systemImage: "magnifyingglass")
                    }
                }
                .disabled(clean.state.isRunning)
                Button {
                    Task { await clean.prepareSmartCleanup() }
                } label: {
                    if clean.state.isRunning {
                        Label("Scanning", systemImage: "hourglass")
                    } else {
                        Label("Smart Clean", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(clean.state.isRunning)
            }

            HStack(alignment: .top, spacing: 12) {
                MetricTile(title: "Review Items", value: "\(summary.itemCount)", tint: Color.oceanAccent)
                MetricTile(title: "Visible", value: "\(filteredItems.count)", detail: formatBytes(filteredBytes), tint: .teal)
                MetricTile(title: "Selected for Trash", value: formatBytes(clean.selectedBytes()), tint: Color.leafAccent)
                MetricTile(title: "Skipped", value: "\(summary.skippedCount)", tint: .yellow)
            }

            CleanSafetyNotice(skippedCount: summary.skippedCount)

            if clean.state.isRunning {
                ProgressPanel(title: "Scanning", message: clean.state.message)
            } else if clean.result.items.isEmpty {
                ContentUnavailableView(
                    "No Scan Results",
                    systemImage: "sparkles",
                    description: Text("Smart Clean finds safe cache clutter and asks once before moving it to Trash. Review Scan opens the full list.")
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredItems.isEmpty {
                CleanupReviewControls(
                    query: $cleanupSearchQuery,
                    category: $selectedCleanupCategory,
                    sort: $cleanupSort,
                    canSelectVisible: false,
                    selectVisible: {},
                    clearVisible: {}
                )
                ContentUnavailableView(
                    "No Matching Items",
                    systemImage: "magnifyingglass",
                    description: Text("Clear the search field or choose another category.")
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CleanupReviewControls(
                    query: $cleanupSearchQuery,
                    category: $selectedCleanupCategory,
                    sort: $cleanupSort,
                    canSelectVisible: !filteredItems.isEmpty,
                    selectVisible: { clean.setSelected(filteredItems, true) },
                    clearVisible: { clean.setSelected(filteredItems, false) }
                )
                HStack(alignment: .top, spacing: 12) {
                    CleanupCategorySummaryView(categories: summary.categories)
                        .frame(width: 260)
                    VStack(spacing: 10) {
                        List(filteredItems) { item in
                            HStack {
                                Toggle("", isOn: Binding {
                                    clean.selection.contains(item)
                                } set: { isSelected in
                                    clean.setSelected(item, isSelected)
                                })
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                                .accessibilityLabel(Text("Select \(item.url.lastPathComponent)"))
                                .accessibilityValue(Text(formatBytes(item.sizeBytes)))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.url.lastPathComponent)
                                        .lineLimit(1)
                                    Text(item.category.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(item.url.deletingLastPathComponent().path)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(formatBytes(item.sizeBytes))
                                    .monospacedDigit()
                                    .frame(maxHeight: .infinity, alignment: .top)
                                IconButton(systemName: "folder", help: "Reveal in Finder") {
                                    revealInFinder(item.url)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        HStack {
                            Text("\(selectedVisibleCount) of \(filteredItems.count) visible selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Review rows before moving anything to Trash.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                isShowingCleanupConfirmation = true
                            } label: {
                                Label("Clean Selected", systemImage: "trash")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!confirmationSummary.hasSelection || clean.state.isRunning)
                            .help("Moves selected items to Trash after confirmation.")
                        }
                    }
                }
            }

            if !clean.log.isEmpty {
                CleanupOperationLogView(entries: Array(clean.log.prefix(8)))
            }
        }
        .padding(22)
        .background(Color.appBackground)
        .alert("Move selected items to Trash?", isPresented: $isShowingCleanupConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                Task { await clean.executeSelected() }
            }
        } message: {
            Text(confirmationSummary.confirmationMessage)
        }
        .alert(
            "Move Smart Clean items to Trash?",
            isPresented: Binding(
                get: { clean.smartPlan != nil },
                set: { isPresented in if !isPresented { clean.dismissSmartPlan() } }
            )
        ) {
            Button("Review List", role: .cancel) {
                clean.dismissSmartPlan()
            }
            Button("Move to Trash", role: .destructive) {
                Task { await clean.executeSelected() }
            }
        } message: {
            if clean.smartPlan != nil {
                let summary = CleanupConfirmationSummary(result: clean.result, selection: clean.selection)
                Text(summary.confirmationMessage)
            }
        }
    }
}

struct CleanupReviewControls: View {
    @Binding var query: String
    @Binding var category: CleanupCategory?
    @Binding var sort: CleanupReviewSort
    var canSelectVisible: Bool
    var selectVisible: () -> Void
    var clearVisible: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            SearchField(text: $query, placeholder: "Search cleanup items or paths")
            HStack(spacing: 10) {
                Picker("Category", selection: $category) {
                    Text("All Categories").tag(nil as CleanupCategory?)
                    ForEach(CleanupCategory.allCases) { category in
                        Text(category.title).tag(Optional(category))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 170)
                Picker("Sort", selection: $sort) {
                    ForEach(CleanupReviewSort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 230)
                Spacer()
                Button {
                    selectVisible()
                } label: {
                    Label("Select Visible", systemImage: "checklist.checked")
                }
                .disabled(!canSelectVisible)
                Button {
                    clearVisible()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .disabled(!canSelectVisible)
                .help("Clear visible selection")
                .accessibilityLabel(Text("Clear visible selection"))
            }
        }
    }
}

struct CleanupOperationLogView: View {
    var entries: [CleanupOperationLogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Operation Log")
                    .font(.headline)
                Spacer()
                Text("\(entries.count) recent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                HStack(spacing: 10) {
                    Image(systemName: symbol(for: entry.status))
                        .foregroundStyle(color(for: entry.status))
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.item.url.lastPathComponent)
                            .lineLimit(1)
                        Text(entry.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(formatBytes(entry.item.sizeBytes))
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
        case .skipped: .yellow
        case .failed: .red
        }
    }
}

struct CleanSafetyNotice: View {
    var skippedCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.leafAccent)
                .frame(width: 30, height: 30)
                .background(Color.leafAccent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text("Calm cleanup policy")
                    .font(.callout.weight(.semibold))
                Text("Review first. Trash only. Protected media cache roots are skipped\(skippedCount > 0 ? " (\(skippedCount))" : "").")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(12)
        .softPanel()
    }
}

struct CleanupCategorySummaryView: View {
    var categories: [CleanupCategorySummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Categories")
                .font(.headline)
            ForEach(categories, id: \.category) { category in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(category.category.title)
                            .lineLimit(1)
                        Spacer()
                        Text(formatBytes(category.bytes))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    DiskUsageBar(value: category.bytes, maxValue: categories.first?.bytes ?? category.bytes)
                        .frame(height: 7)
                }
            }
        }
        .padding(14)
        .softPanel()
    }
}
