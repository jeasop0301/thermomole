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
            title = NSLocalizedString("Live", comment: "freshness")
        } else if age <= 20 {
            level = .updating
            title = NSLocalizedString("Updating", comment: "freshness")
        } else {
            level = .stale
            title = NSLocalizedString("Stale", comment: "freshness")
        }

        detail = Self.detail(seconds: seconds)
        accessibilityLabel = Self.accessibilityLabel(title: title, seconds: seconds)
    }

    private static func detail(seconds: Int) -> String {
        seconds == 0
            ? NSLocalizedString("now", comment: "freshness")
            : String(format: NSLocalizedString("%ds ago", comment: "freshness"), seconds)
    }

    private static func accessibilityLabel(title: String, seconds: Int) -> String {
        if seconds == 0 {
            return String(format: NSLocalizedString("%@, last updated now", comment: ""), title)
        }
        let unit = seconds == 1
            ? NSLocalizedString("second", comment: "")
            : NSLocalizedString("seconds", comment: "")
        return String(format: NSLocalizedString("%@, last updated %d %@ ago", comment: ""), title, seconds, unit)
    }
}
