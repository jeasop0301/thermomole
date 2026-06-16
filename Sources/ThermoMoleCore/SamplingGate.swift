import Foundation

public struct SamplingGate: Equatable, Sendable {
    public var timeout: TimeInterval
    public private(set) var startedAt: Date?

    public init(timeout: TimeInterval) {
        self.timeout = timeout
    }

    public mutating func begin(now: Date = Date()) -> Bool {
        if let startedAt, now.timeIntervalSince(startedAt) < timeout {
            return false
        }
        startedAt = now
        return true
    }

    public mutating func finish() {
        startedAt = nil
    }

    public mutating func finish(startedAt expectedStartedAt: Date) {
        guard startedAt == expectedStartedAt else { return }
        startedAt = nil
    }
}
