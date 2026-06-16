import Foundation

public struct StatusHistorySample: Equatable, Sendable {
    public var sampledAt: Date
    public var cpuTemperatureC: Double?
    public var batteryTemperatureC: Double?
    public var memoryPercent: Int
    public var cpuUsagePercent: Double

    public init(
        sampledAt: Date,
        cpuTemperatureC: Double?,
        batteryTemperatureC: Double?,
        memoryPercent: Int,
        cpuUsagePercent: Double
    ) {
        self.sampledAt = sampledAt
        self.cpuTemperatureC = cpuTemperatureC
        self.batteryTemperatureC = batteryTemperatureC
        self.memoryPercent = memoryPercent
        self.cpuUsagePercent = cpuUsagePercent
    }

    public init(snapshot: SystemSnapshot) {
        self.init(
            sampledAt: snapshot.sampledAt,
            cpuTemperatureC: snapshot.thermal.cpuDisplayC,
            batteryTemperatureC: snapshot.thermal.batteryDisplayC,
            memoryPercent: snapshot.memory.usedPercent,
            cpuUsagePercent: snapshot.cpu.usagePercent
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
}
