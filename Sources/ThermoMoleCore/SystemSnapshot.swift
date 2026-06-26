import Foundation

public struct CPUStatus: Codable, Equatable, Sendable {
    public var usagePercent: Double
    public var perCorePercent: [Double]
    public var logicalCoreCount: Int
    public var performanceCoreCount: Int
    public var efficiencyCoreCount: Int
    public var loadAverage: [Double]

    public init(
        usagePercent: Double,
        perCorePercent: [Double],
        logicalCoreCount: Int,
        performanceCoreCount: Int,
        efficiencyCoreCount: Int,
        loadAverage: [Double]
    ) {
        self.usagePercent = usagePercent
        self.perCorePercent = perCorePercent
        self.logicalCoreCount = logicalCoreCount
        self.performanceCoreCount = performanceCoreCount
        self.efficiencyCoreCount = efficiencyCoreCount
        self.loadAverage = loadAverage
    }
}

public struct DiskStatus: Codable, Equatable, Sendable {
    public var totalBytes: UInt64
    public var usedBytes: UInt64
    public var freeBytes: UInt64
    public var usedPercent: Double
    public var readBytesPerSecond: UInt64
    public var writeBytesPerSecond: UInt64

    public init(
        totalBytes: UInt64,
        usedBytes: UInt64,
        freeBytes: UInt64,
        usedPercent: Double,
        readBytesPerSecond: UInt64,
        writeBytesPerSecond: UInt64
    ) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.freeBytes = freeBytes
        self.usedPercent = usedPercent
        self.readBytesPerSecond = readBytesPerSecond
        self.writeBytesPerSecond = writeBytesPerSecond
    }
}

public struct NetworkStatus: Codable, Equatable, Sendable {
    public var receivedBytesPerSecond: UInt64
    public var sentBytesPerSecond: UInt64

    public init(receivedBytesPerSecond: UInt64, sentBytesPerSecond: UInt64) {
        self.receivedBytesPerSecond = receivedBytesPerSecond
        self.sentBytesPerSecond = sentBytesPerSecond
    }
}

public struct BatteryStatus: Codable, Equatable, Sendable {
    public var percent: Int
    public var isCharging: Bool
    public var isCharged: Bool
    public var isOnACPower: Bool
    public var timeRemaining: String
    public var cycleCount: Int
    public var healthPercent: Int
    public var currentCapacityMAh: Int
    public var maxCapacityMAh: Int
    public var designCapacityMAh: Int
    public var instantPowerW: Double
    /// Recent highest/lowest state-of-charge from the BMS (ioreg BatteryData). nil = unreported.
    /// Feeds the native charge-limit insight; optional/decodeIfPresent for old persisted snapshots.
    public var dailyMaxSoc: Int?
    public var dailyMinSoc: Int?
    /// Apple's rated cycle count (BMS DesignCycleCount9C, ~1000 to 80% health). nil = unreported.
    /// Context only — Apple's spec, NOT a hard limit. decodeIfPresent for old persisted snapshots.
    public var ratedCycleCount: Int?
    /// BMS `ChargerData.NotChargingReason`; non-zero while the OS is holding charging. nil =
    /// unreported. decodeIfPresent for old persisted snapshots.
    public var notChargingReason: Int?

    /// True when the OS is holding the pack below full on AC (native Charge Limit / Optimized
    /// Charging), read authoritatively from `ChargerData` rather than inferred from SoC.
    public var nativeLimitHolding: Bool {
        ChargeLimitInsight.nativeLimitHolding(
            isOnACPower: isOnACPower,
            isCharging: isCharging,
            currentCapacityPercent: percent,
            notChargingReason: notChargingReason
        )
    }

    public init(
        percent: Int,
        isCharging: Bool,
        isCharged: Bool,
        isOnACPower: Bool,
        timeRemaining: String,
        cycleCount: Int,
        healthPercent: Int,
        currentCapacityMAh: Int,
        maxCapacityMAh: Int,
        designCapacityMAh: Int,
        instantPowerW: Double = 0,
        dailyMaxSoc: Int? = nil,
        dailyMinSoc: Int? = nil,
        ratedCycleCount: Int? = nil,
        notChargingReason: Int? = nil
    ) {
        self.percent = percent
        self.isCharging = isCharging
        self.isCharged = isCharged
        self.isOnACPower = isOnACPower
        self.timeRemaining = timeRemaining
        self.cycleCount = cycleCount
        self.healthPercent = healthPercent
        self.currentCapacityMAh = currentCapacityMAh
        self.maxCapacityMAh = maxCapacityMAh
        self.designCapacityMAh = designCapacityMAh
        self.instantPowerW = instantPowerW
        self.dailyMaxSoc = dailyMaxSoc
        self.dailyMinSoc = dailyMinSoc
        self.ratedCycleCount = ratedCycleCount
        self.notChargingReason = notChargingReason
    }

    private enum CodingKeys: String, CodingKey {
        case percent, isCharging, isCharged, isOnACPower, timeRemaining, cycleCount
        case healthPercent, currentCapacityMAh, maxCapacityMAh, designCapacityMAh, instantPowerW
        case dailyMaxSoc, dailyMinSoc, ratedCycleCount, notChargingReason
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        percent = try c.decode(Int.self, forKey: .percent)
        isCharging = try c.decode(Bool.self, forKey: .isCharging)
        isCharged = try c.decode(Bool.self, forKey: .isCharged)
        isOnACPower = try c.decode(Bool.self, forKey: .isOnACPower)
        timeRemaining = try c.decode(String.self, forKey: .timeRemaining)
        cycleCount = try c.decode(Int.self, forKey: .cycleCount)
        healthPercent = try c.decode(Int.self, forKey: .healthPercent)
        currentCapacityMAh = try c.decode(Int.self, forKey: .currentCapacityMAh)
        maxCapacityMAh = try c.decode(Int.self, forKey: .maxCapacityMAh)
        designCapacityMAh = try c.decode(Int.self, forKey: .designCapacityMAh)
        instantPowerW = try c.decodeIfPresent(Double.self, forKey: .instantPowerW) ?? 0
        dailyMaxSoc = try c.decodeIfPresent(Int.self, forKey: .dailyMaxSoc)
        dailyMinSoc = try c.decodeIfPresent(Int.self, forKey: .dailyMinSoc)
        ratedCycleCount = try c.decodeIfPresent(Int.self, forKey: .ratedCycleCount)
        notChargingReason = try c.decodeIfPresent(Int.self, forKey: .notChargingReason)
    }
}

public struct ProcessSnapshot: Codable, Identifiable, Equatable, Sendable {
    public var id: Int { pid }
    public var pid: Int
    public var name: String
    public var cpuPercent: Double
    public var memoryBytes: UInt64

    public init(pid: Int, name: String, cpuPercent: Double, memoryBytes: UInt64) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}

public struct SystemSnapshot: Codable, Equatable, Sendable {
    public var sampledAt: Date
    public var chipName: String
    public var modelIdentifier: String
    public var macOSVersion: String
    public var uptimeSeconds: UInt64
    public var cpu: CPUStatus
    public var memory: MemorySnapshot
    public var disk: DiskStatus
    public var network: NetworkStatus
    public var battery: BatteryStatus
    public var thermal: ThermalSnapshot
    public var fanRPM: Int
    public var topProcesses: [ProcessSnapshot]
    public var health: HealthScore

    public init(
        sampledAt: Date,
        chipName: String,
        modelIdentifier: String,
        macOSVersion: String,
        uptimeSeconds: UInt64,
        cpu: CPUStatus,
        memory: MemorySnapshot,
        disk: DiskStatus,
        network: NetworkStatus,
        battery: BatteryStatus,
        thermal: ThermalSnapshot,
        fanRPM: Int,
        topProcesses: [ProcessSnapshot],
        health: HealthScore
    ) {
        self.sampledAt = sampledAt
        self.chipName = chipName
        self.modelIdentifier = modelIdentifier
        self.macOSVersion = macOSVersion
        self.uptimeSeconds = uptimeSeconds
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
        self.network = network
        self.battery = battery
        self.thermal = thermal
        self.fanRPM = fanRPM
        self.topProcesses = topProcesses
        self.health = health
    }

    public static let placeholder = SystemSnapshot(
        sampledAt: Date(timeIntervalSince1970: 0),
        chipName: "Apple Silicon",
        modelIdentifier: "Unknown",
        macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        uptimeSeconds: 0,
        cpu: CPUStatus(
            usagePercent: 0,
            perCorePercent: [],
            logicalCoreCount: ProcessInfo.processInfo.processorCount,
            performanceCoreCount: 0,
            efficiencyCoreCount: 0,
            loadAverage: [0, 0, 0]
        ),
        memory: MemorySnapshot(
            usedBytes: 0,
            totalBytes: 0,
            usedPercent: 0,
            pressure: .normal,
            activeBytes: 0,
            wiredBytes: 0,
            compressedBytes: 0,
            freeBytes: 0
        ),
        disk: DiskStatus(
            totalBytes: 0,
            usedBytes: 0,
            freeBytes: 0,
            usedPercent: 0,
            readBytesPerSecond: 0,
            writeBytesPerSecond: 0
        ),
        network: NetworkStatus(receivedBytesPerSecond: 0, sentBytesPerSecond: 0),
        battery: BatteryStatus(
            percent: 0,
            isCharging: false,
            isCharged: false,
            isOnACPower: false,
            timeRemaining: "--:--",
            cycleCount: 0,
            healthPercent: 100,
            currentCapacityMAh: 0,
            maxCapacityMAh: 0,
            designCapacityMAh: 0
        ),
        thermal: ThermalSnapshot(),
        fanRPM: 0,
        topProcesses: [],
        health: HealthScore(value: 100, band: .excellent, issues: [])
    )
}
