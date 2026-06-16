import Foundation

public enum OperationPhase: String, Codable, Sendable {
    case idle
    case running
    case finished
    case failed
}

public struct OperationState: Equatable, Sendable {
    public var phase: OperationPhase
    public var message: String
    public var lastUpdatedAt: Date?

    public init(phase: OperationPhase, message: String, lastUpdatedAt: Date? = nil) {
        self.phase = phase
        self.message = message
        self.lastUpdatedAt = lastUpdatedAt
    }

    public static let idle = OperationState(phase: .idle, message: "Ready")

    public var isRunning: Bool {
        phase == .running
    }

    public func started(message: String, at date: Date = Date()) -> OperationState {
        OperationState(phase: .running, message: message, lastUpdatedAt: date)
    }

    public func finished(message: String, at date: Date = Date()) -> OperationState {
        OperationState(phase: .finished, message: message, lastUpdatedAt: date)
    }

    public func failed(message: String, at date: Date = Date()) -> OperationState {
        OperationState(phase: .failed, message: message, lastUpdatedAt: date)
    }
}
