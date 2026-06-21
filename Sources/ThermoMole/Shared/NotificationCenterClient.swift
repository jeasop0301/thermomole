import Foundation
import UserNotifications
import ThermoMoleCore

/// Thin wrapper over UNUserNotificationCenter for the longevity alerts. No-ops when the
/// process isn't a proper app bundle (e.g. a raw-binary dev launch) so it can never crash.
@MainActor
final class NotificationCenterClient {
    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorization() {
        guard isBundled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ notification: LongevityNotification, nativeChargeLimitAvailable: Bool) {
        guard isBundled else { return }
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body(nativeChargeLimitAvailable: nativeChargeLimitAvailable)
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "thermomole.\(notification.rawValue)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
