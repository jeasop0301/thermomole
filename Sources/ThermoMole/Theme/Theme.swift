import SwiftUI
import AppKit
import ThermoMoleCore

extension Color {
    // MARK: - Surfaces (native system semantics — adaptive light/dark for free)
    static let appBackground  = Color(nsColor: .windowBackgroundColor)
    static let appSidebar     = Color(nsColor: .windowBackgroundColor)
    static let cardFill       = Color(nsColor: .controlBackgroundColor)
    static let insetFill      = Color(nsColor: .controlBackgroundColor)
    static let selectionFill  = Color(nsColor: .selectedContentBackgroundColor)
    static let iconBadgeFill  = Color(nsColor: .quaternaryLabelColor)
    static let subtleStroke   = Color(nsColor: .separatorColor)
    /// Native materials carry their own depth — no manual shadow.
    static let panelShadow    = Color.clear

    // MARK: - Text (native label hierarchy)
    static let textPrimary    = Color(nsColor: .labelColor)
    static let textSecondary  = Color(nsColor: .secondaryLabelColor)
    static let textTertiary   = Color(nsColor: .tertiaryLabelColor)

    // MARK: - Semantic accents (severity only — system colors)
    /// "Elevated / caution" — warm system orange.
    static let amberAccent  = Color(nsColor: .systemOrange)
    /// "Hot / urgent" — system red.
    static let garnetAccent = Color(nsColor: .systemRed)
    // "Good / healthy / live" stays calm (no green) — primary label, the native equivalent of the
    // old cream; color is reserved for elevated states. Chrome accents follow the system accent.
    static let leafAccent   = Color(nsColor: .labelColor)
    static let oceanAccent  = Color(nsColor: .labelColor)
    static let thermoAccent = Color.accentColor
    static let plumAccent   = Color.accentColor

    // MARK: - Semantic helper
    /// Returns red / orange / calm-primary based on battery aging multiplier magnitude.
    /// "Good" is calm (no green) — color is reserved for elevated states.
    static func agingWarmth(_ multiplier: Double) -> Color {
        multiplier > 3 ? .garnetAccent : (multiplier >= 1.5 ? .amberAccent : .textPrimary)
    }
}

extension Font {
    // MARK: - Display / body (native SF — rounded numerals for the clean, AlDente-like look)
    static func patinaDisplay(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func patinaBody(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    // MARK: - Aggregate tokens
    static let thermoTitle    = patinaDisplay(20, .semibold)
    static let thermoHeadline = Font.system(size: 16, weight: .semibold)
    static let thermoMetric   = patinaDisplay(22, .medium)
    static let thermoBody     = Font.system(size: 13)
    static let thermoCaption  = Font.system(size: 11, weight: .medium)
}

// (Removed thermoAdaptive — all color tokens now resolve to system semantic colors that adapt
//  to light/dark automatically; no hand-rolled appearance matching needed.)

// MARK: - Panel Modifiers

struct SoftPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
    }
}

struct HeroPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
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
    case .hot: Color.garnetAccent
    }
}

func healthColor(_ band: HealthBand) -> Color {
    switch band {
    case .excellent: Color.leafAccent
    case .good: Color.oceanAccent
    case .fair: Color.amberAccent
    case .needsAttention: Color.garnetAccent
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
    case .hot: Color.garnetAccent
    }
}

func nsColor(for condition: SystemConditionLevel) -> NSColor {
    switch condition {
    case .normal: .labelColor
    case .caution: .systemOrange
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
    case .stale: Color.garnetAccent
    }
}

func freshnessSymbol(_ level: StatusFreshnessLevel) -> String {
    switch level {
    case .live: "circle.fill"
    case .updating: "clock.fill"
    case .stale: "exclamationmark.triangle.fill"
    }
}
