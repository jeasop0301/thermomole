import Foundation

public struct ProtectedPathCatalog: Equatable, Sendable {
    public var summary: String
    public var protectedRoots: [String]
    public var allowedDeletePrefixes: [String]
    public var allowedAppRoots: [String]
    public var defaultScanSkips: [String]

    public init(
        summary: String,
        protectedRoots: [String],
        allowedDeletePrefixes: [String],
        allowedAppRoots: [String] = [],
        defaultScanSkips: [String]
    ) {
        self.summary = summary
        self.protectedRoots = protectedRoots
        self.allowedDeletePrefixes = allowedDeletePrefixes
        self.allowedAppRoots = allowedAppRoots
        self.defaultScanSkips = defaultScanSkips
    }

    public static func `default`(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> ProtectedPathCatalog {
        let home = homeDirectory.standardizedFileURL.path
        return ProtectedPathCatalog(
            summary: "Trash actions are limited to known disposable locations.",
            protectedRoots: [
                "/",
                "/System",
                "/System/",
                "/Library",
                "/Library/",
                "/Applications",
                "/Applications/",
                "/private",
                "/private/",
                home,
                "\(home)/",
                "\(home)/Documents",
                "\(home)/Desktop",
                "\(home)/Pictures",
                "\(home)/Movies",
                "\(home)/Music"
            ],
            allowedDeletePrefixes: [
                "\(home)/Library/Caches/",
                "\(home)/Library/Logs/",
                "\(home)/Library/Application Support/",
                "\(home)/Downloads/",
                "\(home)/.cache/",
                "\(home)/.npm/",
                "\(home)/.gradle/",
                "\(home)/Library/Developer/Xcode/DerivedData/"
            ],
            allowedAppRoots: [
                "/Applications/",
                "\(home)/Applications/"
            ],
            defaultScanSkips: [
                "~/Music",
                "~/Pictures",
                "~/Desktop",
                "~/Documents",
                "~/Downloads"
            ]
        )
    }
}

public struct ProtectedPathValidator: Sendable {
    public var homeDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    public func canDelete(_ url: URL, resolvedURL: URL? = nil) -> Bool {
        let standardized = url.standardizedFileURL.path
        let resolved = (resolvedURL ?? url).standardizedFileURL.path

        guard isAllowedBase(standardized), isAllowedBase(resolved) else { return false }
        guard !isProtectedRoot(standardized), !isProtectedRoot(resolved) else { return false }
        return true
    }

    /// App uninstall has different semantics than cache cleanup: `.app` bundles live under
    /// `/Applications` (a protected root) and must be trashable, while everything else there
    /// must stay protected. Requires an `.app` extension and both the logical and symlink-resolved
    /// paths to sit under an allowed application root.
    public func canTrashAppBundle(_ url: URL, resolvedURL: URL? = nil) -> Bool {
        let standardized = url.standardizedFileURL
        let resolved = (resolvedURL ?? url).standardizedFileURL

        guard standardized.pathExtension == "app" else { return false }
        guard isAllowedAppRoot(standardized.path), isAllowedAppRoot(resolved.path) else { return false }
        guard !isProtectedRoot(standardized.path), !isProtectedRoot(resolved.path) else { return false }
        return true
    }

    private func isAllowedBase(_ path: String) -> Bool {
        ProtectedPathCatalog.default(homeDirectory: homeDirectory)
            .allowedDeletePrefixes
            .contains { path.hasPrefix($0) }
    }

    private func isAllowedAppRoot(_ path: String) -> Bool {
        ProtectedPathCatalog.default(homeDirectory: homeDirectory)
            .allowedAppRoots
            .contains { path.hasPrefix($0) }
    }

    private func isProtectedRoot(_ path: String) -> Bool {
        ProtectedPathCatalog.default(homeDirectory: homeDirectory)
            .protectedRoots
            .contains(path)
    }
}
