import Foundation

public enum MemoryPressure: String, Codable, Sendable {
    case normal
    case warning
    case critical

    public static func from(usedPercent: Int) -> MemoryPressure {
        if usedPercent >= 88 { return .critical }
        if usedPercent >= 71 { return .warning }
        return .normal
    }
}

public struct MemorySnapshot: Codable, Equatable, Sendable {
    public var usedBytes: UInt64
    public var totalBytes: UInt64
    public var usedPercent: Int
    public var pressure: MemoryPressure
    public var activeBytes: UInt64
    public var wiredBytes: UInt64
    public var compressedBytes: UInt64
    public var freeBytes: UInt64

    public init(
        usedBytes: UInt64,
        totalBytes: UInt64,
        usedPercent: Int,
        pressure: MemoryPressure,
        activeBytes: UInt64,
        wiredBytes: UInt64,
        compressedBytes: UInt64,
        freeBytes: UInt64
    ) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
        self.usedPercent = usedPercent
        self.pressure = pressure
        self.activeBytes = activeBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.freeBytes = freeBytes
    }
}

public enum MemoryCalculator {
    public static func snapshot(
        pageSize: UInt64,
        activePages: UInt64,
        wiredPages: UInt64,
        compressedPages: UInt64,
        speculativePages: UInt64,
        inactivePages: UInt64,
        freePages: UInt64,
        totalBytes: UInt64
    ) -> MemorySnapshot {
        let active = activePages * pageSize
        let wired = wiredPages * pageSize
        let compressed = compressedPages * pageSize
        let free = freePages * pageSize
        let used = active + wired + compressed
        let percent = totalBytes > 0 ? Int((Double(used) / Double(totalBytes) * 100).rounded()) : 0

        return MemorySnapshot(
            usedBytes: used,
            totalBytes: totalBytes,
            usedPercent: percent,
            pressure: MemoryPressure.from(usedPercent: percent),
            activeBytes: active,
            wiredBytes: wired,
            compressedBytes: compressed,
            freeBytes: free + (speculativePages * pageSize) + (inactivePages * pageSize)
        )
    }
}
