import Foundation

public struct DiskEntry: Identifiable, Equatable, Sendable {
    public var id: String { url.path }
    public var url: URL
    public var sizeBytes: UInt64
    public var isDirectory: Bool

    public init(url: URL, sizeBytes: UInt64, isDirectory: Bool) {
        self.url = url
        self.sizeBytes = sizeBytes
        self.isDirectory = isDirectory
    }
}

public struct DiskAnalyzer {
    public var fileManager: FileManager = .default
    public var homeDirectory: URL

    public init(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    public func analyze(_ url: URL, limit: Int = 80, shouldCancel: @Sendable () -> Bool = { false }) -> [DiskEntry] {
        let children = (try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var entries = [DiskEntry]()
        for child in children {
            if shouldCancel() { break }
            if shouldSkip(child) { continue }
            let isDirectory = ((try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
            entries.append(DiskEntry(url: child, sizeBytes: size(child, shouldCancel: shouldCancel), isDirectory: isDirectory))
        }

        return entries
            .sorted { $0.sizeBytes > $1.sizeBytes }
            .prefix(limit)
            .map { $0 }
    }

    private func size(_ url: URL, shouldCancel: @Sendable () -> Bool) -> UInt64 {
        if shouldCancel() { return 0 }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
            return UInt64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            if shouldCancel() { break }
            if shouldSkip(fileURL) {
                enumerator.skipDescendants()
                continue
            }
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
            total += UInt64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }

    private func shouldSkip(_ url: URL) -> Bool {
        isHomePrivacyRoot(url) || isTCCSensitiveMediaRoot(url)
    }

    private func isHomePrivacyRoot(_ url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        let privacyRoots = [
            homeDirectory.appendingPathComponent("Desktop", isDirectory: true),
            homeDirectory.appendingPathComponent("Documents", isDirectory: true),
            homeDirectory.appendingPathComponent("Downloads", isDirectory: true),
            homeDirectory.appendingPathComponent("Library", isDirectory: true),
            homeDirectory.appendingPathComponent("Music", isDirectory: true),
            homeDirectory.appendingPathComponent("Pictures", isDirectory: true),
            homeDirectory.appendingPathComponent("Movies", isDirectory: true)
        ].map { $0.standardizedFileURL.path }
        return privacyRoots.contains(standardized.path)
    }

    private func isTCCSensitiveMediaRoot(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        let path = url.standardizedFileURL.path.lowercased()
        let sensitiveNames = [
            "com.apple.music",
            "com.apple.itunes",
            "com.apple.amp",
            "com.apple.medialibrary",
            "com.apple.photos",
            "com.apple.tv",
            "com.apple.ilifemediabrowser"
        ]
        if sensitiveNames.contains(where: { name.hasPrefix($0) }) {
            return true
        }
        return path.contains("/library/caches/com.apple.music")
            || path.contains("/library/caches/com.apple.amp")
            || path.contains("/library/caches/com.apple.medialibrary")
            || path.contains("/library/caches/com.apple.photos")
            || path.contains("/library/caches/com.apple.tv")
    }
}

public struct InstalledApp: Identifiable, Equatable, Sendable {
    public var id: String { bundlePath }
    public var name: String
    public var bundleIdentifier: String
    public var bundlePath: String
    public var version: String
    public var build: String

    public init(
        name: String,
        bundleIdentifier: String,
        bundlePath: String,
        version: String = "unknown",
        build: String = "unknown"
    ) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
        self.version = version
        self.build = build
    }
}

public enum StartupItemDomain: String, Codable, Sendable {
    case userLaunchAgent
    case localLaunchAgent
    case localLaunchDaemon

    public var title: String {
        switch self {
        case .userLaunchAgent: "User LaunchAgent"
        case .localLaunchAgent: "Local LaunchAgent"
        case .localLaunchDaemon: "LaunchDaemon"
        }
    }
}

public struct StartupItem: Identifiable, Equatable, Sendable {
    public var id: String { plistPath }
    public var label: String
    public var program: String
    public var domain: StartupItemDomain
    public var isEnabled: Bool
    public var plistPath: String

    public init(label: String, program: String, domain: StartupItemDomain, isEnabled: Bool, plistPath: String) {
        self.label = label
        self.program = program
        self.domain = domain
        self.isEnabled = isEnabled
        self.plistPath = plistPath
    }
}

public struct SoftwareInventoryFilter: Equatable, Sendable {
    public var query: String

    public init(query: String) {
        self.query = query
    }

    public func filter(_ apps: [InstalledApp]) -> [InstalledApp] {
        guard !tokens.isEmpty else { return apps }
        return apps.filter { app in
            matches([
                app.name,
                app.bundleIdentifier,
                app.bundlePath,
                app.version,
                app.build
            ])
        }
    }

    public func filter(_ startupItems: [StartupItem]) -> [StartupItem] {
        guard !tokens.isEmpty else { return startupItems }
        return startupItems.filter { item in
            matches([
                item.label,
                item.program,
                item.domain.title,
                item.domain.rawValue,
                item.isEnabled ? "enabled" : "disabled",
                item.plistPath
            ])
        }
    }

    private var tokens: [String] {
        query
            .lowercased()
            .split { $0.isWhitespace }
            .map(String.init)
    }

    private func matches(_ fields: [String]) -> Bool {
        let haystack = fields.joined(separator: " ").lowercased()
        return tokens.allSatisfy { haystack.contains($0) }
    }
}

public struct SoftwareInventory {
    public var fileManager: FileManager = .default
    public var homeDirectory: URL
    public var appRoots: [URL]
    public var startupRoots: [(URL, StartupItemDomain)]

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        appRoots: [URL]? = nil,
        startupRoots: [URL]? = nil
    ) {
        self.homeDirectory = homeDirectory
        self.appRoots = appRoots ?? [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ]
        if let startupRoots {
            self.startupRoots = startupRoots.map { ($0, .userLaunchAgent) }
        } else {
            self.startupRoots = [
                (homeDirectory.appendingPathComponent("Library/LaunchAgents", isDirectory: true), .userLaunchAgent),
                (URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true), .localLaunchAgent),
                (URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true), .localLaunchDaemon)
            ]
        }
    }

    public func installedApps() -> [InstalledApp] {
        appRoots.flatMap(apps(in:)).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func startupItems() -> [StartupItem] {
        startupRoots.flatMap { root, domain in
            startupItems(in: root, domain: domain)
        }
        .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    private func apps(in directory: URL) -> [InstalledApp] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.pathExtension == "app" }
            .map { url in
                let bundle = Bundle(url: url)
                return InstalledApp(
                    name: bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                        ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                        ?? url.deletingPathExtension().lastPathComponent,
                    bundleIdentifier: bundle?.bundleIdentifier ?? "unknown",
                    bundlePath: url.path,
                    version: bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                    build: bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
                )
            }
    }

    private func startupItems(in directory: URL, domain: StartupItemDomain) -> [StartupItem] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.pathExtension == "plist" }
            .compactMap { startupItem(from: $0, domain: domain) }
    }

    private func startupItem(from url: URL, domain: StartupItemDomain) -> StartupItem? {
        guard let dictionary = NSDictionary(contentsOf: url) as? [String: Any] else { return nil }
        let label = dictionary["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
        let program = dictionary["Program"] as? String
            ?? (dictionary["ProgramArguments"] as? [String])?.first
            ?? "unknown"
        let disabled = dictionary["Disabled"] as? Bool ?? false
        let runAtLoad = dictionary["RunAtLoad"] as? Bool ?? false
        let keepAlive = dictionary["KeepAlive"] as? Bool ?? false
        return StartupItem(
            label: label,
            program: program,
            domain: domain,
            isEnabled: !disabled && (runAtLoad || keepAlive || program != "unknown"),
            plistPath: url.path
        )
    }
}

public enum OptimizeTask: String, CaseIterable, Identifiable, Codable, Sendable {
    case quickLook
    case launchServices
    case periodicMaintenance
    case savedApplicationState
    case dockRefresh

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .quickLook: "Rebuild Quick Look"
        case .launchServices: "Refresh Launch Services"
        case .periodicMaintenance: "Run periodic maintenance"
        case .savedApplicationState: "Clean saved application state"
        case .dockRefresh: "Refresh Dock"
        }
    }
}
