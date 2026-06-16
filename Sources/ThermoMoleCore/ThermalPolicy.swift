import Foundation

public enum TemperatureWarningLevel: String, Codable, Sendable {
    case normal
    case caution
    case hot

    public static func batteryLevel(for temperatureC: Double?) -> TemperatureWarningLevel {
        guard let temperatureC else { return .normal }
        if temperatureC >= ThermalThresholds.batteryHotC { return .hot }
        if temperatureC >= ThermalThresholds.batteryCautionC { return .caution }
        return .normal
    }
}

public enum BatteryTemperatureSource: String, Codable, Sendable {
    case unavailable
    case smcCellMax
    case ioregTemperature
}

public enum CPUTemperatureSource: String, Codable, Sendable {
    case unavailable
    case cpuDieHotspot
    case cpuAverage
}

public struct CPUTemperatureReading: Codable, Equatable, Sendable {
    public var valueC: Double?
    public var source: CPUTemperatureSource
}

public struct ThermalSnapshot: Codable, Equatable, Sendable {
    public var cpuDisplayC: Double?
    public var cpuTemperatureSource: CPUTemperatureSource
    public var cpuDieHotspotC: Double?
    public var cpuAverageC: Double?
    public var batteryDisplayC: Double?
    public var batteryTemperatureSource: BatteryTemperatureSource
    public var batteryCellMaxC: Double?
    public var batteryIORegC: Double?
    public var batteryWarningLevel: TemperatureWarningLevel
    public var hasBatterySensorMismatch: Bool

    public init(
        cpuDisplayC: Double? = nil,
        cpuTemperatureSource: CPUTemperatureSource = .unavailable,
        cpuDieHotspotC: Double? = nil,
        cpuAverageC: Double? = nil,
        batteryDisplayC: Double? = nil,
        batteryTemperatureSource: BatteryTemperatureSource = .unavailable,
        batteryCellMaxC: Double? = nil,
        batteryIORegC: Double? = nil,
        batteryWarningLevel: TemperatureWarningLevel = .normal,
        hasBatterySensorMismatch: Bool = false
    ) {
        self.cpuDisplayC = cpuDisplayC
        self.cpuTemperatureSource = cpuTemperatureSource
        self.cpuDieHotspotC = cpuDieHotspotC
        self.cpuAverageC = cpuAverageC
        self.batteryDisplayC = batteryDisplayC
        self.batteryTemperatureSource = batteryTemperatureSource
        self.batteryCellMaxC = batteryCellMaxC
        self.batteryIORegC = batteryIORegC
        self.batteryWarningLevel = batteryWarningLevel
        self.hasBatterySensorMismatch = hasBatterySensorMismatch
    }
}

public enum ThermalPolicy {
    public static func resolveCPUTemperature(
        cpuDieHotspotC: Double?,
        cpuAverageC: Double?
    ) -> CPUTemperatureReading {
        if let cpuDieHotspotC, isValidTemperature(cpuDieHotspotC) {
            return CPUTemperatureReading(valueC: cpuDieHotspotC, source: .cpuDieHotspot)
        }
        if let cpuAverageC, isValidTemperature(cpuAverageC) {
            return CPUTemperatureReading(valueC: cpuAverageC, source: .cpuAverage)
        }
        return CPUTemperatureReading(valueC: nil, source: .unavailable)
    }

    public static func isValidTemperature(_ value: Double) -> Bool {
        value > 0 && value < 150
    }

    /// Tighter bound for battery-pack readings. A battery realistically operates well under
    /// 80°C, so a higher value indicates a sensor glitch or wrong-units decode and is rejected
    /// (rather than displayed as an alarming wrong number). 80°C stays conservative so a
    /// genuinely hot pack still reads through.
    public static func isValidBatteryTemperature(_ value: Double) -> Bool {
        value > 0 && value < 80
    }
}

public enum BatteryTemperaturePolicy {
    public static func resolve(
        smcCellTemperaturesC: [Double],
        ioregTemperatureC: Double?
    ) -> ThermalSnapshot {
        let validCells = smcCellTemperaturesC.filter(ThermalPolicy.isValidBatteryTemperature)
        let cellMax = validCells.max()
        let validIOReg = ioregTemperatureC.flatMap { ThermalPolicy.isValidBatteryTemperature($0) ? $0 : nil }

        let display: Double?
        let source: BatteryTemperatureSource
        if let validIOReg {
            display = validIOReg
            source = .ioregTemperature
        } else if let cellMax {
            display = cellMax
            source = .smcCellMax
        } else {
            display = nil
            source = .unavailable
        }

        let mismatch: Bool
        if let cellMax, let validIOReg {
            mismatch = abs(cellMax - validIOReg) >= 2.0
        } else {
            mismatch = false
        }

        return ThermalSnapshot(
            batteryDisplayC: display,
            batteryTemperatureSource: source,
            batteryCellMaxC: cellMax,
            batteryIORegC: validIOReg,
            batteryWarningLevel: TemperatureWarningLevel.batteryLevel(for: display),
            hasBatterySensorMismatch: mismatch
        )
    }
}
