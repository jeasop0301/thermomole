import SwiftUI
import ThermoMoleCore

/// Menu-bar popover: the Patina aging card, plus a slim action footer.
/// Right-click on the status item still exposes Open / Refresh / Quit.
struct MenuBarPopoverView: View {
    @ObservedObject var model: AppModel
    var openMain: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            PatinaAgingCard(model: model)

            HStack(spacing: 10) {
                Button {
                    model.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Open Patina", action: openMain)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 4)
        }
        .padding(16)
        .frame(width: 424)
        .background(Color.appBackground)
        .tint(Color.amberAccent)
        // The card is designed Dark Jewel only; pin dark so a Light-mode Mac doesn't
        // flip the adaptive surfaces to white and wash out the amber/garnet accents.
        .preferredColorScheme(.dark)
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

struct CompactProcessList: View {
    var processes: [ProcessSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Processes")
                .font(.headline)
            if processes.isEmpty {
                Text("No process data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
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
        }
        .padding(12)
        .softPanel()
    }
}
