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
}

struct MainWindowView: View {
    @ObservedObject var model: AppModel
    @State private var selection: AppSection = .status

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(Color.subtleStroke)
                .frame(width: 1)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
        }
        .frame(minWidth: 1040, minHeight: 680)
        .background(Color.appBackground)
        .tint(Color.thermoAccent)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.thermoAccent)
                    .frame(width: 34, height: 34)
                    .background(Color.iconBadgeFill)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("ThermoMole")
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                    Text("Local Mac monitor")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)

            VStack(spacing: 4) {
                ForEach(AppSection.allCases) { section in
                    Button {
                        selection = section
                    } label: {
                        SidebarRow(section: section, isSelected: selection == section)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                Text("Real Battery Pack")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(batterySourceLabel(model.snapshot.thermal.batteryTemperatureSource))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(formatTemperaturePrecise(model.snapshot.thermal.batteryDisplayC))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(batteryColor(model.snapshot.thermal.batteryWarningLevel))
                    .monospacedDigit()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .softPanel()
        }
        .padding(14)
        .frame(width: 244)
        .background(Color.appSidebar)
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

struct SidebarRow: View {
    var section: AppSection
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: section.symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 22)
                .foregroundStyle(isSelected ? Color.thermoAccent : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(section.title)
                    .font(.callout.weight(.semibold))
                Text(section.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(isSelected ? Color.selectionFill : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.thermoAccent.opacity(0.22) : Color.clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(section.title), \(section.subtitle)"))
        .accessibilityHint(Text(isSelected ? "Current section" : "Open section"))
    }
}

struct PageHeader: View {
    var title: String
    var subtitle: String
    var symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("ThermoMole")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.thermoAccent)
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.thermoAccent)
                    .frame(width: 32, height: 32)
                    .background(Color.iconBadgeFill.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
            }
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
