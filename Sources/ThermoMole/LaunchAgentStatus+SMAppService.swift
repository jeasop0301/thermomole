import ServiceManagement
import ThermoMoleCore

extension LaunchAgentStatus {
    init(_ status: SMAppService.Status) {
        switch status {
        case .enabled: self = .enabled
        case .notRegistered: self = .notRegistered
        case .notFound: self = .notFound
        case .requiresApproval: self = .requiresApproval
        @unknown default: self = .unknown
        }
    }
}
