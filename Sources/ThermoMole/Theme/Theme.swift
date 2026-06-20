import SwiftUI
import AppKit
import ThermoMoleCore

extension Color {
    // MARK: - Surfaces
    static let appBackground = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedRed: 0.957, green: 0.957, blue: 0.965, alpha: 1),
        dark: NSColor(calibratedRed: 0.086, green: 0.090, blue: 0.098, alpha: 1)  // #161719
    ))
    static let appSidebar = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedRed: 0.925, green: 0.925, blue: 0.937, alpha: 1),
        dark: NSColor(calibratedRed: 0.102, green: 0.110, blue: 0.122, alpha: 1)  // #1A1C1F
    ))
    static let cardFill = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 1),
        dark: NSColor(calibratedRed: 0.118, green: 0.125, blue: 0.137, alpha: 1)  // #1E2023
    ))
    static let insetFill = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedRed: 0.937, green: 0.937, blue: 0.949, alpha: 1),
        dark: NSColor(calibratedRed: 0.137, green: 0.149, blue: 0.169, alpha: 1)  // #23262B
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
        dark: NSColor(calibratedWhite: 1, alpha: 0.10)   // α0.10 (flat design)
    ))
    /// Flat design: no shadow in dark mode
    static let panelShadow = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedWhite: 0, alpha: 0.06),
        dark: NSColor(calibratedWhite: 0, alpha: 0.0)    // clear
    ))

    // MARK: - Text (adaptive)
    static let textPrimary = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedRed: 0.098, green: 0.098, blue: 0.106, alpha: 1),
        dark: NSColor(calibratedRed: 0.945, green: 0.937, blue: 0.918, alpha: 1)  // #F1EFEA
    ))
    static let textSecondary = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedRed: 0.380, green: 0.380, blue: 0.400, alpha: 1),
        dark: NSColor(calibratedRed: 0.612, green: 0.596, blue: 0.561, alpha: 1)  // #9C988F
    ))
    static let textTertiary = Color(nsColor: .thermoAdaptive(
        light: NSColor(calibratedRed: 0.500, green: 0.500, blue: 0.518, alpha: 1),
        dark: NSColor(calibratedRed: 0.545, green: 0.529, blue: 0.494, alpha: 1)  // #8B877E
    ))

    // MARK: - Jewel Accents
    /// Emerald — primary brand accent
    static let leafAccent   = Color(red: 0.137, green: 0.788, blue: 0.627)  // #23C9A0
    static let amberAccent  = Color(red: 0.878, green: 0.647, blue: 0.227)  // #E0A53A
    /// NEW: garnet accent for high-severity states
    static let garnetAccent = Color(red: 0.886, green: 0.376, blue: 0.290)  // #E2604A
    static let plumAccent   = Color(red: 0.369, green: 0.361, blue: 0.902)
    /// Unified to emerald (same as leafAccent)
    static let oceanAccent  = Color(red: 0.137, green: 0.788, blue: 0.627)  // #23C9A0
    /// Unified to emerald (same as leafAccent)
    static let thermoAccent = Color(red: 0.137, green: 0.788, blue: 0.627)  // #23C9A0

    // MARK: - Semantic helper
    /// Returns garnet / amber / calm-cream based on battery aging multiplier magnitude.
    /// "Good" is a calm warm-neutral (no green/teal) — color is reserved for elevated states.
    static func agingWarmth(_ multiplier: Double) -> Color {
        multiplier > 3 ? .garnetAccent : (multiplier >= 1.5 ? .amberAccent : .textPrimary)
    }
}

extension Font {
    // MARK: - Patina custom fonts (graceful fallback)
    static func patinaDisplay(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        NSFont(name: "Fraunces", size: size) != nil
            ? Font.custom("Fraunces", size: size).weight(weight)
            : .system(size: size, weight: weight, design: .serif)
    }
    static func patinaBody(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        NSFont(name: "Figtree", size: size) != nil
            ? Font.custom("Figtree", size: size).weight(weight)
            : .system(size: size, weight: weight)
    }

    // MARK: - Existing tokens (values updated to use Patina fonts)
    static let thermoTitle    = patinaDisplay(20, .semibold)
    static let thermoHeadline = Font.system(size: 16, weight: .semibold)
    static let thermoMetric   = patinaDisplay(22, .medium)
    static let thermoBody     = Font.system(size: 13)
    static let thermoCaption  = Font.system(size: 11, weight: .medium)
}

extension NSColor {
    static func thermoAdaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        }
    }
}

// MARK: - Panel Modifiers

struct SoftPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.subtleStroke, lineWidth: 1))
            // flat: no shadow
    }
}

struct HeroPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.insetFill)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            // flat: no shadow
    }
}

extension View {
    func softPanel() -> some View {
        modifier(SoftPanelModifier())
    }
    func heroPanel() -> some View {
        modifier(HeroPanelModifier())
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

/// Power-flow direction from the boolean flags (amperage sign is unreliable across Macs).
/// "from pack" only when genuinely off AC — AC-connected-but-not-charging is "holding"/"full".
func batteryPowerDirection(_ b: BatteryStatus) -> String {
    if b.isCharging { return NSLocalizedString("into pack", comment: "") }
    if !b.isOnACPower { return NSLocalizedString("from pack", comment: "") }
    return b.isCharged
        ? NSLocalizedString("full", comment: "")
        : NSLocalizedString("holding", comment: "")
}

func batterySourceLabel(_ source: BatteryTemperatureSource) -> String {
    switch source {
    case .unavailable: NSLocalizedString("Unavailable", comment: "")
    case .smcCellMax: NSLocalizedString("SMC TB Max", comment: "")
    case .ioregTemperature: NSLocalizedString("AppleSmartBattery", comment: "")
    }
}

func cpuSourceLabel(_ source: CPUTemperatureSource) -> String {
    switch source {
    case .unavailable: NSLocalizedString("Unavailable", comment: "")
    case .cpuDieHotspot: NSLocalizedString("CPU Die Hotspot", comment: "")
    case .cpuAverage: NSLocalizedString("CPU Average", comment: "")
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
