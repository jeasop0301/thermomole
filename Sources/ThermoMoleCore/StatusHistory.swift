import Foundation

public struct StatusHistorySample: Equatable, Sendable {
    public var sampledAt: Date
    public var cpuTemperatureC: Double?
    public var batteryTemperatureC: Double?
    public var memoryPercent: Int
    public var cpuUsagePercent: Double
    public var batteryPowerW: Double

    public init(
        sampledAt: Date,
        cpuTemperatureC: Double?,
        batteryTemperatureC: Double?,
        memoryPercent: Int,
        cpuUsagePercent: Double,
        batteryPowerW: Double = 0
    ) {
        self.sampledAt = sampledAt
        self.cpuTemperatureC = cpuTemperatureC
        self.batteryTemperatureC = batteryTemperatureC
        self.memoryPercent = memoryPercent
        self.cpuUsagePercent = cpuUsagePercent
        self.batteryPowerW = batteryPowerW
    }

    public init(snapshot: SystemSnapshot) {
        self.init(
            sampledAt: snapshot.sampledAt,
            cpuTemperatureC: snapshot.thermal.cpuDisplayC,
            batteryTemperatureC: snapshot.thermal.batteryDisplayC,
            memoryPercent: snapshot.memory.usedPercent,
            cpuUsagePercent: snapshot.cpu.usagePercent,
            batteryPowerW: snapshot.battery.instantPowerW
        )
    }
}

public struct BoundedStatusHistory: Equatable, Sendable {
    public private(set) var samples: [StatusHistorySample]
    public var limit: Int

    public init(limit: Int = 30, samples: [StatusHistorySample] = []) {
        self.limit = max(1, limit)
        self.samples = Array(samples.suffix(max(1, limit)))
    }

    public mutating func append(_ sample: StatusHistorySample) {
        samples.append(sample)
        if samples.count > limit {
            samples.removeFirst(samples.count - limit)
        }
    }

    public mutating func append(_ snapshot: SystemSnapshot) {
        append(StatusHistorySample(snapshot: snapshot))
    }

    public var cpuTemperatureSeries: [Double] {
        samples.compactMap(\.cpuTemperatureC)
    }

    public var batteryTemperatureSeries: [Double] {
        samples.compactMap(\.batteryTemperatureC)
    }

    public var memoryPercentSeries: [Double] {
        samples.map { Double($0.memoryPercent) }
    }

    public var cpuUsageSeries: [Double] {
        samples.map(\.cpuUsagePercent)
    }

    /// Magnitude of battery power flow (charge or discharge) over time — the direct
    /// heat driver. Sign is dropped here; the instantaneous label shows direction.
    public var batteryPowerSeries: [Double] {
        samples.map { abs($0.batteryPowerW) }
    }
}
