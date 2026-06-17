import Foundation

/// Module-pure mirror of ServiceManagement's SMAppService.Status. The main target
/// maps SMAppService.Status into this so SettingsModel can live in ThermoMoleAppCore
/// (which has no ServiceManagement dependency) and be unit-tested with a stub.
public enum LaunchAgentStatus: Equatable, Sendable {
    case enabled
    case notRegistered
    case notFound
    case requiresApproval
    case unknown
}
