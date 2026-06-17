import Foundation

public enum BatterySensorKind: String, Equatable, Sendable {
    case bms        // IOReg Temperature — 주 표시·추세 기준
    case cellMax    // SMC 셀 thermistor 최대 — 가장 더운 셀 상한
    case virtual    // VirtualTemperature — BMS 추정
}

public struct BatterySensorRow: Equatable, Sendable {
    public let kind: BatterySensorKind
    public let temperatureC: Double

    public init(kind: BatterySensorKind, temperatureC: Double) {
        self.kind = kind
        self.temperatureC = temperatureC
    }
}

/// View-model that lists the battery temperature sources actually available in a
/// snapshot (nil sources omitted), so the UI can show why apps disagree by ~1°C.
/// Pure value type — display labels live in the view, this only decides which rows exist.
public struct BatterySensorSummary: Equatable, Sendable {
    public let rows: [BatterySensorRow]
    public let hasMismatch: Bool

    public init(thermal: ThermalSnapshot) {
        var rows = [BatterySensorRow]()
        if let value = thermal.batteryIORegC {
            rows.append(BatterySensorRow(kind: .bms, temperatureC: value))
        }
        if let value = thermal.batteryCellMaxC {
            rows.append(BatterySensorRow(kind: .cellMax, temperatureC: value))
        }
        if let value = thermal.batteryVirtualC {
            rows.append(BatterySensorRow(kind: .virtual, temperatureC: value))
        }
        self.rows = rows
        self.hasMismatch = thermal.hasBatterySensorMismatch
    }
}
