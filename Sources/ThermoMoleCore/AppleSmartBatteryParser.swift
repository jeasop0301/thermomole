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
    /// Highest state-of-charge the BMS recorded over the recent rolling window (BatteryData block).
    /// nil when the firmware doesn't report it. High values flag high-SoC dwell aging.
    public var dailyMaxSoc: Int?
    /// Lowest state-of-charge over the same window. nil when unreported.
    public var dailyMinSoc: Int?

    public init(
        temperatureC: Double? = nil,
        virtualTemperatureC: Double? = nil,
        cycleCount: Int = 0,
        currentCapacityPercent: Int = 0,
        rawCurrentCapacityMAh: Int = 0,
        rawMaxCapacityMAh: Int = 0,
        designCapacityMAh: Int = 0,
        voltageMV: Int = 0,
        amperageMA: Int = 0,
        dailyMaxSoc: Int? = nil,
        dailyMinSoc: Int? = nil
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
        self.dailyMaxSoc = dailyMaxSoc
        self.dailyMinSoc = dailyMinSoc
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
        // The nested `"BatteryData" = {…}` dict appears BEFORE the top-level keys and carries its
        // own DesignCapacity / CycleCount / Voltage. A first-match regex would read those nested
        // values (equal today, but they diverge after a battery service / firmware re-estimation,
        // which would corrupt cycle-wear + calibration). Strip that block so only top-level wins.
        let top = strippingNestedBlock(named: "BatteryData", from: raw)
        return AppleSmartBatteryInfo(
            temperatureC: centiCelsiusValue(for: "Temperature", in: top),
            virtualTemperatureC: centiCelsiusValue(for: "VirtualTemperature", in: top),
            cycleCount: intValue(for: "CycleCount", in: top),
            currentCapacityPercent: intValue(for: "CurrentCapacity", in: top),
            rawCurrentCapacityMAh: intValue(for: "AppleRawCurrentCapacity", in: top),
            rawMaxCapacityMAh: intValue(for: "AppleRawMaxCapacity", in: top),
            designCapacityMAh: intValue(for: "DesignCapacity", in: top),
            voltageMV: intValue(for: "Voltage", in: top),
            amperageMA: signedIntValue(for: "Amperage", in: top),
            // DailyMaxSoc / DailyMinSoc live INSIDE the nested BatteryData block, so they are NOT
            // in `top` (which had that block stripped) — read them from the full `raw`. intValue
            // returns 0 for a missing key; map 0 → nil to mean "unknown".
            dailyMaxSoc: optionalIntValue(for: "DailyMaxSoc", in: raw),
            dailyMinSoc: optionalIntValue(for: "DailyMinSoc", in: raw)
        )
    }

    /// Like `intValue` but treats a missing/zero key as `nil` (unknown) rather than 0.
    private static func optionalIntValue(for key: String, in raw: String) -> Int? {
        let value = intValue(for: key, in: raw)
        return value > 0 ? value : nil
    }

    /// Removes a `"<name>" = {…}` block (balanced braces) so its nested keys don't shadow the
    /// top-level ones. Returns the input unchanged if the block isn't found.
    static func strippingNestedBlock(named name: String, from raw: String) -> String {
        guard let open = raw.range(of: #""\#(name)"\s*=\s*\{"#, options: .regularExpression) else {
            return raw
        }
        var depth = 1
        var i = open.upperBound // first char after the opening '{'
        while i < raw.endIndex {
            switch raw[i] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    var s = raw
                    s.removeSubrange(open.lowerBound...i)
                    return s
                }
            default: break
            }
            i = raw.index(after: i)
        }
        return raw // unbalanced — leave as-is
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
