import Foundation
import Observation
import ThermoMoleCore

@MainActor
@Observable
public final class SoftwareModel {
    public private(set) var installedApps = [InstalledApp]()
    public private(set) var startupItems = [StartupItem]()
    public private(set) var appUninstallLog = [AppUninstallResult]()
    public private(set) var softwareState = OperationState.idle

    public typealias LoadInventory = @Sendable () -> (apps: [InstalledApp], startup: [StartupItem])
    public typealias Uninstall = @Sendable (InstalledApp) -> AppUninstallResult

    private let loadInventory: LoadInventory
    private let uninstall: Uninstall
    private let logOperation: (OperationHistoryEntry) -> Void
    private let onChanged: () -> Void

    public init(
        loadInventory: @escaping LoadInventory,
        uninstall: @escaping Uninstall,
        logOperation: @escaping (OperationHistoryEntry) -> Void,
        onChanged: @escaping () -> Void
    ) {
        self.loadInventory = loadInventory
        self.uninstall = uninstall
        self.logOperation = logOperation
        self.onChanged = onChanged
    }

    public func loadSoftware() {
        guard !softwareState.isRunning else { return }
        softwareState = softwareState.started(message: "Loading applications")
        let loadInventory = self.loadInventory
        Task { [weak self] in
            let inventory = await Task.detached(priority: .utility) { loadInventory() }.value
            guard let self else { return }
            installedApps = inventory.apps
            startupItems = inventory.startup
            softwareState = softwareState.finished(
                message: "\(inventory.apps.count) apps · \(inventory.startup.count) startup items",
                at: Date()
            )
        }
    }

    public func uninstallApp(_ app: InstalledApp) {
        guard !softwareState.isRunning else { return }
        softwareState = softwareState.started(message: "Moving \(app.name) to Trash")
        let uninstall = self.uninstall
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) { uninstall(app) }.value
            guard let self else { return }
            appUninstallLog = [result] + appUninstallLog
            logOperation(OperationHistoryEntry.uninstall(result))
            onChanged()
            if result.status == .succeeded {
                installedApps.removeAll { $0.id == result.app.id }
                softwareState = softwareState.finished(message: "\(result.app.name) moved to Trash", at: Date())
            } else {
                softwareState = softwareState.failed(message: "\(result.app.name) uninstall failed", at: Date())
            }
        }
    }
}
