import Foundation

public struct AppleSmartBatteryInfo: Equatable, Sendable {
    public var temperatureC: Double?
    public var virtualTemperatureC: Double?
    public var cycleCount: Int
    public var currentCapacityPercent: Int
    public var rawCurrentCapacityMAh: Int
    public var rawMaxCapacityMAh: Int
    public var designCapacityMAh: Int
    public var voltageMV: Int
    public var amperageMA: Int

    public init(
        temperatureC: Double? = nil,
        virtualTemperatureC: Double? = nil,
        cycleCount: Int = 0,
        currentCapacityPercent: Int = 0,
        rawCurrentCapacityMAh: Int = 0,
        rawMaxCapacityMAh: Int = 0,
        designCapacityMAh: Int = 0,
        voltageMV: Int = 0,
        amperageMA: Int = 0
    ) {
        self.temperatureC = temperatureC
        self.virtualTemperatureC = virtualTemperatureC
        self.cycleCount = cycleCount
        self.currentCapacityPercent = currentCapacityPercent
        self.rawCurrentCapacityMAh = rawCurrentCapacityMAh
        self.rawMaxCapacityMAh = rawMaxCapacityMAh
        self.designCapacityMAh = designCapacityMAh
        self.voltageMV = voltageMV
        self.amperageMA = amperageMA
    }

    public var healthPercent: Int {
        guard designCapacityMAh > 0, rawMaxCapacityMAh > 0 else { return 100 }
        return min(100, Int((Double(rawMaxCapacityMAh) / Double(designCapacityMAh) * 100).rounded()))
    }

    /// Instantaneous battery power in watts (V × A). Positive while charging into the pack,
    /// negative while discharging. The magnitude is the direct heat source and the largest
    /// driver of pack temperature.
    public var instantPowerW: Double {
        Double(voltageMV) * Double(amperageMA) / 1_000_000.0
    }
}

public enum AppleSmartBatteryParser {
    public static func parse(_ raw: String) -> AppleSmartBatteryInfo {
        AppleSmartBatteryInfo(
            temperatureC: centiCelsiusValue(for: "Temperature", in: raw),
            virtualTemperatureC: centiCelsiusValue(for: "VirtualTemperature", in: raw),
            cycleCount: intValue(for: "CycleCount", in: raw),
            currentCapacityPercent: intValue(for: "CurrentCapacity", in: raw),
            rawCurrentCapacityMAh: intValue(for: "AppleRawCurrentCapacity", in: raw),
            rawMaxCapacityMAh: intValue(for: "AppleRawMaxCapacity", in: raw),
            designCapacityMAh: intValue(for: "DesignCapacity", in: raw),
            voltageMV: intValue(for: "Voltage", in: raw),
            amperageMA: signedIntValue(for: "Amperage", in: raw)
        )
    }

    private static func centiCelsiusValue(for key: String, in raw: String) -> Double? {
        let value = intValue(for: key, in: raw)
        return value > 0 ? Double(value) / 100.0 : nil
    }

    private static func intValue(for key: String, in raw: String) -> Int {
        guard let range = raw.range(
            of: #""\#(key)"\s*=\s*(\d+)"#,
            options: .regularExpression
        ) else {
            return 0
        }
        let token = raw[range].split(separator: "=").last?.trimmingCharacters(in: .whitespaces) ?? ""
        return Int(token) ?? 0
    }

    private static func signedIntValue(for key: String, in raw: String) -> Int {
        // ioreg prints signed fields (e.g. Amperage) as a 64-bit two's-complement unsigned;
        // reinterpret the raw bit pattern as signed. (The old `unsigned - Int(UInt64.max) - 1`
        // trapped on 32-bit-range values and overflowed 64-bit discharge values to 0.)
        guard let range = raw.range(
            of: #""\#(key)"\s*=\s*(\d+)"#,
            options: .regularExpression
        ) else {
            return 0
        }
        let token = raw[range].split(separator: "=").last?.trimmingCharacters(in: .whitespaces) ?? ""
        guard let unsigned = UInt64(token) else { return 0 }
        return Int(Int64(bitPattern: unsigned))
    }
}
