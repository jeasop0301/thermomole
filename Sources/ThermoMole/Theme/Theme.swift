import SwiftUI
import AppKit
import ThermoMoleCore

extension Color {
    static let appBackground = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedRed: 0.957, green: 0.957, blue: 0.965, alpha: 1),
        dark: NSColor(calibratedRed: 0.102, green: 0.102, blue: 0.110, alpha: 1)
    ))
    static let appSidebar = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedRed: 0.925, green: 0.925, blue: 0.937, alpha: 1),
        dark: NSColor(calibratedRed: 0.125, green: 0.125, blue: 0.133, alpha: 1)
    ))
    static let cardFill = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 1),
        dark: NSColor(calibratedRed: 0.165, green: 0.165, blue: 0.180, alpha: 1)
    ))
    static let insetFill = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedRed: 0.937, green: 0.937, blue: 0.949, alpha: 1),
        dark: NSColor(calibratedRed: 0.139, green: 0.139, blue: 0.153, alpha: 1)
    ))
    static let selectionFill = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedRed: 0.894, green: 0.941, blue: 1.0, alpha: 1),
        dark: NSColor(calibratedRed: 0.071, green: 0.227, blue: 0.388, alpha: 1)
    ))
    static let iconBadgeFill = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedRed: 0.933, green: 0.945, blue: 0.961, alpha: 1),
        dark: NSColor(calibratedRed: 0.173, green: 0.184, blue: 0.208, alpha: 1)
    ))
    static let subtleStroke = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedWhite: 0, alpha: 0.10),
        dark: NSColor(calibratedWhite: 1, alpha: 0.12)
    ))
    static let panelShadow = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedWhite: 0, alpha: 0.06),
        dark: NSColor(calibratedWhite: 0, alpha: 0.30)
    ))
    static let thermoAccent = Color(red: 0.039, green: 0.518, blue: 1.0)
    static let oceanAccent = Color(red: 0.353, green: 0.784, blue: 0.980)
    static let leafAccent = Color(red: 0.204, green: 0.780, blue: 0.349)
    static let amberAccent = Color(red: 1.0, green: 0.624, blue: 0.039)
    static let plumAccent = Color(red: 0.369, green: 0.361, blue: 0.902)
}

extension Font {
    static let thermoTitle = Font.system(size: 20, weight: .semibold)
    static let thermoHeadline = Font.system(size: 16, weight: .semibold)
    static let thermoMetric = Font.system(size: 22, weight: .medium, design: .rounded)
    static let thermoBody = Font.system(size: 13)
    static let thermoCaption = Font.system(size: 11, weight: .medium)
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
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.subtleStroke, lineWidth: 1))
            .shadow(color: Color.panelShadow, radius: 3, x: 0, y: 1)
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

/// Instantaneous battery power as a signed wattage ("+23 W" charging, "−18 W" discharging),
/// or nil when effectively idle (< 0.5 W) so the UI can omit it.
func formatBatteryPower(_ watts: Double) -> String? {
    guard abs(watts) >= 0.5 else { return nil }
    let sign = watts > 0 ? "+" : "−"
    return String(format: "%@%.0f W", sign, abs(watts))
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

