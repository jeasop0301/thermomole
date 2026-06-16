import SwiftUI
import ThermoMoleCore

struct BatteryTemperatureRing: View {
    let temperatureC: Double?
    var diameter: CGFloat = 96

    private var scale: BatteryRingScale { BatteryRingScale(temperatureC: temperatureC) }
    private var ringColor: Color { batteryColor(scale.level) }
    private var lineWidth: CGFloat { diameter * 0.09 }

    var body: some View {
        ZStack {
            Circle().stroke(Color.insetFill, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: scale.fraction)
                .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: scale.level == .hot ? ringColor.opacity(0.55) : .clear,
                        radius: scale.level == .hot ? 8 : 0)
            VStack(spacing: 2) {
                Text(temperatureC.map { String(format: "%.1f°", $0) } ?? "--°")
                    .font(.system(size: diameter * 0.27, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary)
                Text("Battery")
                    .font(.thermoCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery temperature \(temperatureC.map { String(format: "%.1f degrees", $0) } ?? "unavailable")")
    }
}
