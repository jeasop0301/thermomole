import Foundation

public enum StatusFreshnessLevel: String, Codable, Equatable, Sendable {
    case live
    case updating
    case stale
}

public struct StatusFreshness: Equatable, Sendable {
    public var level: StatusFreshnessLevel
    public var title: String
    public var detail: String
    public var accessibilityLabel: String

    public init(sampledAt: Date, now: Date = Date()) {
        let age = max(0, now.timeIntervalSince(sampledAt))
        let seconds = Int(age.rounded(.down))

        if age <= 6 {
            level = .live
            title = "Live"
        } else if age <= 20 {
            level = .updating
            title = "Updating"
        } else {
            level = .stale
            title = "Stale"
        }

        detail = Self.detail(seconds: seconds)
        accessibilityLabel = Self.accessibilityLabel(title: title, seconds: seconds)
    }

    private static func detail(seconds: Int) -> String {
        seconds == 0 ? "now" : "\(seconds)s ago"
    }

    private static func accessibilityLabel(title: String, seconds: Int) -> String {
        if seconds == 0 {
            return "\(title), last updated now"
        }
        let unit = seconds == 1 ? "second" : "seconds"
        return "\(title), last updated \(seconds) \(unit) ago"
    }
}
