import SwiftUI
import ThermoMoleCore
import ThermoMoleAppCore

struct OptimizeTab: View {
    let optimize: OptimizeModel
    @State private var pendingTask: OptimizeTask?
    @State private var isShowingDefaultOptimizeConfirmation = false

    private var safetyPolicy: OptimizeSafetyPolicy {
        OptimizeSafetyPolicy(context: optimize.optimizeSafetyContext)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TabHeader(subtitle: "Small maintenance tasks, shown before they run.") {
                OperationStatePill(state: optimize.optimizeState)
                Button {
                    optimize.refreshOptimizeSafetyContext()
                    isShowingDefaultOptimizeConfirmation = true
                } label: {
                    if optimize.optimizeState.isRunning {
                        Label("Running", systemImage: "hourglass")
                    } else {
                        Label("Run Default", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(optimize.optimizeState.isRunning)
            }

            OptimizeSafetySummaryPanel(summary: OptimizeSafetySummary(context: optimize.optimizeSafetyContext))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                ForEach(OptimizeTask.allCases) { task in
                    let skipReason = safetyPolicy.decision(for: task).skipReason
                    OptimizeTaskCard(
                        task: task,
                        plan: OptimizePlan(task: task),
                        skipReason: skipReason,
                        isRunning: optimize.optimizeState.isRunning,
                        run: { pendingTask = task }
                    )
                }
            }

            if !optimize.optimizeLog.isEmpty {
                OptimizeOperationLogView(results: Array(optimize.optimizeLog.prefix(6)))
            }
        }
        .padding(22)
        .background(Color.appBackground)
        .onAppear {
            optimize.refreshOptimizeSafetyContext()
        }
        .alert("Run default maintenance?", isPresented: $isShowingDefaultOptimizeConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Run", role: .destructive) {
                optimize.runDefaultOptimize()
            }
        } message: {
            let batch = OptimizeBatchPlan.defaultMaintenance(safetyContext: optimize.optimizeSafetyContext)
            let summary = OptimizeBatchConfirmationSummary(batch: batch)
            Text(summary.confirmationMessage)
        }
        .alert(item: $pendingTask) { task in
            let plan = OptimizePlan(task: task)
            let summary = OptimizeTaskConfirmationSummary(plan: plan)
            return Alert(
                title: Text(summary.title),
                message: Text(summary.confirmationMessage),
                primaryButton: .destructive(Text("Run")) {
                    optimize.runOptimizeTask(task)
                },
                secondaryButton: .cancel()
            )
        }
    }
}

struct OptimizeSafetySummaryPanel: View {
    var summary: OptimizeSafetySummary

    private var tint: Color {
        summary.activeSignals.isEmpty ? Color.leafAccent : Color.amberAccent
    }

    private var symbol: String {
        summary.activeSignals.isEmpty ? "checkmark.seal.fill" : "shield.lefthalf.filled"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.title)
                        .font(.headline)
                    Text(summary.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                Spacer()
            }

            if summary.activeSignals.isEmpty {
                Label("Normal context", systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.leafAccent)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(summary.activeSignals) { signal in
                        OptimizeSafetySignalChip(signal: signal)
                    }
                }
            }
        }
        .padding(14)
        .softPanel()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Optimize safety \(summary.title)"))
        .accessibilityValue(Text(summary.detail))
    }
}

struct OptimizeSafetySignalChip: View {
    var signal: OptimizeSafetySignal

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.amberAccent)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(signal.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(signal.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.insetFill)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.subtleStroke))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch signal.id {
        case "batteryPower": "battery.50percent"
        case "activeVPN": "lock.shield"
        case "externalDisplay": "display"
        case "externalAudio": "speaker.wave.2"
        case "bluetoothInput": "keyboard"
        case "bluetoothAudio": "headphones"
        default: "shield"
        }
    }
}

struct OptimizeTaskCard: View {
    var task: OptimizeTask
    var plan: OptimizePlan
    var skipReason: String?
    var isRunning: Bool
    var run: () -> Void

    private var isStaged: Bool {
        plan.commands.isEmpty || skipReason != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(plan.riskLevel.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(tint)
                }
                Spacer()
            }

            Text(plan.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            if let skipReason {
                Label(skipReason, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color.amberAccent)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(plan.effects.prefix(3), id: \.self) { effect in
                    Label(effect, systemImage: "checkmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Text("\(plan.commands.count) command\(plan.commands.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    run()
                } label: {
                    Label(isStaged ? "Staged" : "Run", systemImage: isStaged ? "lock" : "play.fill")
                }
                .disabled(isRunning || isStaged)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(14)
        .softPanel()
    }

    private var tint: Color {
        switch plan.riskLevel {
        case .low: Color.leafAccent
        case .medium: Color.amberAccent
        }
    }

    private var symbol: String {
        switch task {
        case .quickLook: "eye"
        case .launchServices: "app.badge"
        case .periodicMaintenance: "calendar.badge.clock"
        case .savedApplicationState: "clock.arrow.circlepath"
        case .dockRefresh: "rectangle.bottomthird.inset.filled"
        }
    }
}

struct OptimizeOperationLogView: View {
    var results: [OptimizeExecutionResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Maintenance Log")
                    .font(.headline)
                Spacer()
                Text("\(results.count) recent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(results, id: \.executedAt) { result in
                HStack(spacing: 10) {
                    Image(systemName: result.status == .succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.status == .succeeded ? Color.leafAccent : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.task.title)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(result.entries.first?.output.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? result.status.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("\(result.entries.count) command\(result.entries.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                .font(.caption)
            }
        }
        .padding(14)
        .softPanel()
    }
}
