import SwiftUI
import AppKit
import ThermoMoleCore

extension Color {
    static let appBackground = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedRed: 0.965, green: 0.955, blue: 0.925, alpha: 1),
        dark: NSColor(calibratedRed: 0.085, green: 0.083, blue: 0.073, alpha: 1)
    ))
    static let appSidebar = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedRed: 0.895, green: 0.925, blue: 0.875, alpha: 1),
        dark: NSColor(calibratedRed: 0.115, green: 0.118, blue: 0.098, alpha: 1)
    ))
    static let cardFill = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedRed: 0.992, green: 0.982, blue: 0.948, alpha: 1),
        dark: NSColor(calibratedRed: 0.145, green: 0.137, blue: 0.118, alpha: 1)
    ))
    static let insetFill = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.895, alpha: 1),
        dark: NSColor(calibratedRed: 0.108, green: 0.108, blue: 0.096, alpha: 1)
    ))
    static let selectionFill = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedRed: 0.972, green: 0.855, blue: 0.70, alpha: 1),
        dark: NSColor(calibratedRed: 0.235, green: 0.152, blue: 0.105, alpha: 1)
    ))
    static let iconBadgeFill = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedRed: 0.985, green: 0.84, blue: 0.62, alpha: 1),
        dark: NSColor(calibratedRed: 0.265, green: 0.164, blue: 0.108, alpha: 1)
    ))
    static let subtleStroke = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedRed: 0.48, green: 0.39, blue: 0.28, alpha: 0.14),
        dark: NSColor(calibratedRed: 0.85, green: 0.78, blue: 0.66, alpha: 0.12)
    ))
    static let panelShadow = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedWhite: 0, alpha: 0.035),
        dark: NSColor(calibratedWhite: 0, alpha: 0.18)
    ))
    static let thermoAccent = Color(red: 0.68, green: 0.27, blue: 0.16)
    static let oceanAccent = Color(red: 0.22, green: 0.44, blue: 0.54)
    static let leafAccent = Color(red: 0.28, green: 0.52, blue: 0.36)
    static let amberAccent = Color(red: 0.76, green: 0.52, blue: 0.21)
    static let plumAccent = Color(red: 0.46, green: 0.37, blue: 0.50)
}

extension NSColor {
    static func thermoAdaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        }
    }
}

struct SoftPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.cardFill)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.subtleStroke))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: Color.panelShadow, radius: 2, x: 0, y: 1)
    }
}

extension View {
    func softPanel() -> some View {
        modifier(SoftPanelModifier())
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

func formatTemperature(_ value: Double?) -> String {
    guard let value else { return "--°" }
    return "\(Int(value.rounded()))°"
}

func formatTemperaturePrecise(_ value: Double?) -> String {
    guard let value else { return "--°" }
    return String(format: "%.1f°", value)
}

func batterySourceLabel(_ source: BatteryTemperatureSource) -> String {
    switch source {
    case .unavailable: "Unavailable"
    case .smcCellMax: "SMC TB Max"
    case .ioregTemperature: "AppleSmartBattery"
    }
}

func cpuSourceLabel(_ source: CPUTemperatureSource) -> String {
    switch source {
    case .unavailable: "Unavailable"
    case .cpuDieHotspot: "CPU Die Hotspot"
    case .cpuAverage: "CPU Average"
    }
}

func formatLoad(_ loadAverage: [Double]) -> String {
    guard let first = loadAverage.first else { return "--" }
    return String(format: "%.2f", first)
}

func revealInFinder(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
}

func formatUptime(_ seconds: UInt64) -> String {
    let days = seconds / 86_400
    let hours = (seconds % 86_400) / 3_600
    let minutes = (seconds % 3_600) / 60
    if days > 0 { return "\(days)d \(hours)h" }
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m"
}

func batteryColor(_ level: TemperatureWarningLevel) -> Color {
    switch level {
    case .normal: Color.leafAccent
    case .caution: Color.amberAccent
    case .hot: .red
    }
}

func healthColor(_ band: HealthBand) -> Color {
    switch band {
    case .excellent: Color.leafAccent
    case .good: Color.oceanAccent
    case .fair: Color.amberAccent
    case .needsAttention: .red
    }
}

func systemCondition(for snapshot: SystemSnapshot) -> SystemConditionLevel {
    SystemConditionPolicy.resolve(
        cpuTemperatureC: snapshot.thermal.cpuDisplayC,
        batteryWarningLevel: snapshot.thermal.batteryWarningLevel,
        memoryPressure: snapshot.memory.pressure,
        healthBand: snapshot.health.band
    )
}

func conditionColor(_ condition: SystemConditionLevel) -> Color {
    switch condition {
    case .normal: Color.leafAccent
    case .caution: Color.amberAccent
    case .hot: .red
    }
}

func nsColor(for condition: SystemConditionLevel) -> NSColor {
    switch condition {
    case .normal: NSColor(calibratedRed: 0.22, green: 0.56, blue: 0.36, alpha: 1)
    case .caution: NSColor(calibratedRed: 0.84, green: 0.58, blue: 0.20, alpha: 1)
    case .hot: .systemRed
    }
}

func conditionTitle(_ condition: SystemConditionLevel) -> String {
    switch condition {
    case .normal: "All clear"
    case .caution: "Watch"
    case .hot: "Needs attention"
    }
}

func conditionSymbol(_ condition: SystemConditionLevel) -> String {
    switch condition {
    case .normal: "checkmark.circle.fill"
    case .caution: "exclamationmark.triangle.fill"
    case .hot: "flame.fill"
    }
}

func freshnessColor(_ level: StatusFreshnessLevel) -> Color {
    switch level {
    case .live: Color.leafAccent
    case .updating: Color.amberAccent
    case .stale: .red
    }
}

func freshnessSymbol(_ level: StatusFreshnessLevel) -> String {
    switch level {
    case .live: "circle.fill"
    case .updating: "clock.fill"
    case .stale: "exclamationmark.triangle.fill"
    }
}

func doctorActionLabel(_ action: DoctorAction) -> String {
    switch action {
    case .none: ""
    case .openFullDiskAccess: "Open Settings"
    case .reduceMemoryLoad: "Review processes"
    case .reviewStorage: "Use Clean or Analyze"
    case .reviewBatteryHealth: "Check service"
    case .repairOperationLog: "Check Logs folder"
    case .reviewRecentFailures: "Review logs"
    case .refreshStatusSnapshot: "Refresh status"
    }
}
