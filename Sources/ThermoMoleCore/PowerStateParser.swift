import Foundation

public struct PowerState: Equatable, Sendable {
    public var percent: Int
    public var isCharging: Bool
    public var isCharged: Bool
    public var isOnACPower: Bool
    public var timeRemaining: String

    public init(
        percent: Int,
        isCharging: Bool,
        isCharged: Bool,
        isOnACPower: Bool,
        timeRemaining: String
    ) {
        self.percent = percent
        self.isCharging = isCharging
        self.isCharged = isCharged
        self.isOnACPower = isOnACPower
        self.timeRemaining = timeRemaining
    }
}

/// Parses the output of `pmset -g batt`.
///
/// Guards against the "not charging" hold state (optimized battery charging),
/// where the substring "charging" would otherwise be misread as actively charging.
public enum PowerStateParser {
    public static func parse(pmsetOutput raw: String, fallbackPercent: Int = 0) -> PowerState {
        let lower = raw.lowercased()

        let onAC = lower.contains("ac power")
        let isCharged = lower.contains("charged") || lower.contains("finishing charge")
        let mentionsCharging = lower.contains("charging")
        let isDischarging = lower.contains("discharging")
        let isNotCharging = lower.contains("not charging")
        let isCharging = mentionsCharging && !isDischarging && !isNotCharging

        let percent = firstInt(#"(\d+)%"#, in: raw) ?? fallbackPercent
        let time = firstMatch(#"\d+:\d+"#, in: raw) ?? "--:--"

        return PowerState(
            percent: percent,
            isCharging: isCharging,
            isCharged: isCharged,
            isOnACPower: onAC,
            timeRemaining: time
        )
    }

    private static func firstMatch(_ pattern: String, in raw: String) -> String? {
        raw.range(of: pattern, options: .regularExpression).map { String(raw[$0]) }
    }

    private static func firstInt(_ pattern: String, in raw: String) -> Int? {
        firstMatch(pattern, in: raw).flatMap { token in
            Int(token.trimmingCharacters(in: CharacterSet(charactersIn: "%; ")))
        }
    }
}
