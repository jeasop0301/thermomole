import Foundation

public enum AppUninstallStatus: String, Codable, Sendable {
    case succeeded
    case failed
}

public enum AppUninstallPlanStatus: String, Codable, Equatable, Sendable {
    case ready
    case ambiguous
    case notFound
    case missingQuery
}

public struct AppUninstallPlan: Equatable, Sendable {
    public var query: String
    public var status: AppUninstallPlanStatus
    public var matches: [InstalledApp]
    public var selectedApp: InstalledApp?
    public var message: String

    public init(query: String, apps: [InstalledApp]) {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.query = normalizedQuery

        guard !normalizedQuery.isEmpty else {
            status = .missingQuery
            matches = []
            selectedApp = nil
            message = "Provide an app name."
            return
        }

        let filtered = SoftwareInventoryFilter(query: normalizedQuery).filter(apps)
        guard !filtered.isEmpty else {
            status = .notFound
            matches = []
            selectedApp = nil
            message = "No app found for \"\(normalizedQuery)\"."
            return
        }

        let exactMatches = Self.exactMatches(query: normalizedQuery, apps: filtered)
        if exactMatches.count == 1, let app = exactMatches.first {
            status = .ready
            matches = [app]
            selectedApp = app
            message = "Ready to move \(app.name) to Trash."
            return
        }

        if filtered.count == 1, let app = filtered.first {
            status = .ready
            matches = [app]
            selectedApp = app
            message = "Ready to move \(app.name) to Trash."
            return
        }

        status = .ambiguous
        matches = Array(filtered.prefix(10))
        selectedApp = nil
        message = "Multiple apps match \"\(normalizedQuery)\"."
    }

    public var canExecute: Bool {
        status == .ready && selectedApp != nil
    }

    private static func exactMatches(query: String, apps: [InstalledApp]) -> [InstalledApp] {
        let needle = normalize(query)
        return apps.filter { app in
            let pathName = URL(fileURLWithPath: app.bundlePath)
                .deletingPathExtension()
                .lastPathComponent
            return [
                app.name,
                app.bundleIdentifier,
                app.bundlePath,
                pathName
            ].contains { normalize($0) == needle }
        }
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct AppUninstallResult: Identifiable, Equatable, Sendable {
    public var id: String
    public var app: InstalledApp
    public var status: AppUninstallStatus
    public var destinationURL: URL?
    public var message: String
    public var executedAt: Date

    public init(
        app: InstalledApp,
        status: AppUninstallStatus,
        destinationURL: URL? = nil,
        message: String,
        executedAt: Date = Date()
    ) {
        id = "\(executedAt.timeIntervalSince1970)-\(app.id)-\(status.rawValue)"
        self.app = app
        self.status = status
        self.destinationURL = destinationURL
        self.message = message
        self.executedAt = executedAt
    }
}

public struct AppUninstallConfirmationSummary: Equatable, Sendable {
    public var title: String
    public var appName: String
    public var bundleIdentifier: String
    public var path: String
    public var versionLine: String
    public var requiresAdministratorApproval: Bool

    public init(app: InstalledApp) {
        appName = app.name
        bundleIdentifier = app.bundleIdentifier
        path = app.bundlePath
        versionLine = Self.versionLine(version: app.version, build: app.build)
        requiresAdministratorApproval = Self.requiresAdministratorApproval(path: app.bundlePath)
        title = "Move \(app.name) to Trash?"
    }

    public var confirmationMessage: String {
        var lines = [
            "Bundle ID: \(bundleIdentifier)",
            versionLine,
            "Path: \(path)",
            "Mode: Move to Trash"
        ]
        if requiresAdministratorApproval {
            lines.append("Administrator approval may be required.")
        }
        return lines.joined(separator: "\n")
    }

    private static func versionLine(version: String, build: String) -> String {
        guard !build.isEmpty, build != "unknown", build != version else {
            return "Version: \(version)"
        }
        return "Version: \(version) (\(build))"
    }

    private static func requiresAdministratorApproval(path: String) -> Bool {
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return standardizedPath.hasPrefix("/Applications/")
            || standardizedPath.hasPrefix("/Library/")
            || standardizedPath.hasPrefix("/System/")
    }
}

public struct AppUninstallExecutor {
    public typealias TrashItem = @Sendable (URL) throws -> URL

    public var validator: ProtectedPathValidator
    private var trashItem: TrashItem

    public init(
        validator: ProtectedPathValidator = ProtectedPathValidator(),
        trashItem: @escaping TrashItem = AppUninstallExecutor.defaultTrashItem
    ) {
        self.validator = validator
        self.trashItem = trashItem
    }

    public func moveToTrash(_ app: InstalledApp) -> AppUninstallResult {
        let url = URL(fileURLWithPath: app.bundlePath, isDirectory: true)
        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
        guard validator.canTrashAppBundle(url, resolvedURL: resolvedURL) else {
            return AppUninstallResult(
                app: app,
                status: .failed,
                message: "Protected path blocked"
            )
        }
        do {
            let destination = try trashItem(url)
            return AppUninstallResult(
                app: app,
                status: .succeeded,
                destinationURL: destination,
                message: "Moved to Trash"
            )
        } catch {
            return AppUninstallResult(
                app: app,
                status: .failed,
                message: error.localizedDescription
            )
        }
    }

    public static func defaultTrashItem(_ url: URL) throws -> URL {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        return (resultingURL as URL?) ?? url
    }
}
