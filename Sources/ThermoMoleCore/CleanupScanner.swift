import Foundation

public enum CleanupCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case appCaches
    case logs
    case developerArtifacts
    case aiToolCaches
    case browserCaches
    case communicationCaches
    case designToolCaches
    case cloudStorageCaches
    case temporaryFiles
    case installers

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .appCaches: "App Caches"
        case .logs: "Logs"
        case .developerArtifacts: "Developer Artifacts"
        case .aiToolCaches: "AI Tool Caches"
        case .browserCaches: "Browser Caches"
        case .communicationCaches: "Communication Caches"
        case .designToolCaches: "Design Tool Caches"
        case .cloudStorageCaches: "Cloud Caches"
        case .temporaryFiles: "Temporary Files"
        case .installers: "Installers"
        }
    }
}

public struct CleanupItem: Identifiable, Equatable, Sendable {
    public var id: String { url.path }
    public var category: CleanupCategory
    public var url: URL
    public var sizeBytes: UInt64
    public var isPreselected: Bool

    public init(category: CleanupCategory, url: URL, sizeBytes: UInt64, isPreselected: Bool) {
        self.category = category
        self.url = url
        self.sizeBytes = sizeBytes
        self.isPreselected = isPreselected
    }
}

public struct CleanupScanResult: Equatable, Sendable {
    public var items: [CleanupItem]
    public var skipped: [String]

    public init(items: [CleanupItem], skipped: [String]) {
        self.items = items
        self.skipped = skipped
    }

    public var totalBytes: UInt64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }
}

public enum CleanupPreselectionMode: String, Codable, Sendable {
    case none
    case recommended
}

public struct CleanupCategorySummary: Equatable, Sendable {
    public var category: CleanupCategory
    public var bytes: UInt64
    public var preselectedBytes: UInt64
    public var itemCount: Int

    public init(category: CleanupCategory, bytes: UInt64, preselectedBytes: UInt64, itemCount: Int) {
        self.category = category
        self.bytes = bytes
        self.preselectedBytes = preselectedBytes
        self.itemCount = itemCount
    }
}

public struct CleanupReviewSummary: Equatable, Sendable {
    public var totalBytes: UInt64
    public var preselectedBytes: UInt64
    public var itemCount: Int
    public var skippedCount: Int
    public var categories: [CleanupCategorySummary]

    public init(_ result: CleanupScanResult) {
        totalBytes = result.totalBytes
        preselectedBytes = result.items
            .filter(\.isPreselected)
            .reduce(0) { $0 + $1.sizeBytes }
        itemCount = result.items.count
        skippedCount = result.skipped.count

        categories = CleanupCategory.allCases.compactMap { category in
            let items = result.items.filter { $0.category == category }
            guard !items.isEmpty else { return nil }
            return CleanupCategorySummary(
                category: category,
                bytes: items.reduce(0) { $0 + $1.sizeBytes },
                preselectedBytes: items.filter(\.isPreselected).reduce(0) { $0 + $1.sizeBytes },
                itemCount: items.count
            )
        }
        .sorted {
            if $0.bytes == $1.bytes {
                return $0.category.title < $1.category.title
            }
            return $0.bytes > $1.bytes
        }
    }
}

public struct SmartCleanupReviewPlan: Identifiable, Equatable, Sendable {
    public var id: String {
        "\(selectedItemCount)-\(selectedBytes)-\(skippedCount)"
    }

    public var selectedItemCount: Int
    public var selectedBytes: UInt64
    public var skippedCount: Int
    public var selection: CleanupReviewSelection

    public init(_ result: CleanupScanResult) {
        let selectedItems = result.items.filter(\.isPreselected)
        selectedItemCount = selectedItems.count
        selectedBytes = selectedItems.reduce(0) { $0 + $1.sizeBytes }
        skippedCount = result.skipped.count
        selection = CleanupReviewSelection(items: result.items)
    }

    public var hasSelection: Bool {
        selectedItemCount > 0
    }
}

public struct CleanupConfirmationSummary: Equatable, Sendable {
    public var itemCount: Int
    public var selectedBytes: UInt64
    public var skippedCount: Int
    public var categoryLines: [String]
    public var examplePaths: [String]

    public var hasSelection: Bool {
        itemCount > 0
    }

    public init(result: CleanupScanResult, selection: CleanupReviewSelection) {
        let selectedItems = result.items
            .filter { selection.contains($0) }
            .sorted {
                if $0.sizeBytes == $1.sizeBytes {
                    return $0.url.path.localizedCaseInsensitiveCompare($1.url.path) == .orderedAscending
                }
                return $0.sizeBytes > $1.sizeBytes
            }

        itemCount = selectedItems.count
        selectedBytes = selectedItems.reduce(0) { $0 + $1.sizeBytes }
        skippedCount = result.skipped.count
        examplePaths = selectedItems.prefix(3).map(\.url.path)

        let categoryRows: [(category: CleanupCategory, bytes: UInt64, line: String)] = CleanupCategory.allCases.compactMap { category in
            let items = selectedItems.filter { $0.category == category }
            guard !items.isEmpty else { return nil }
            let suffix = items.count == 1 ? "item" : "items"
            return (
                category: category,
                bytes: items.reduce(0) { $0 + $1.sizeBytes },
                line: "\(category.title): \(items.count) \(suffix)"
            )
        }

        categoryLines = categoryRows
        .sorted {
            if $0.bytes == $1.bytes {
                return $0.category.title < $1.category.title
            }
            return $0.bytes > $1.bytes
        }
        .map(\.line)
    }

    public var confirmationMessage: String {
        var lines = [
            "\(itemCount) \(itemCount == 1 ? "item" : "items") · \(formatBytes(selectedBytes))",
            "Mode: Move to Trash"
        ]
        if !categoryLines.isEmpty {
            lines.append("Categories: \(categoryLines.joined(separator: ", "))")
        }
        if !examplePaths.isEmpty {
            lines.append("Examples: \(examplePaths.joined(separator: "\n"))")
        }
        if skippedCount > 0 {
            lines.append("\(skippedCount) protected or privacy-sensitive paths skipped.")
        }
        return lines.joined(separator: "\n")
    }
}

public struct CleanupReviewSelection: Equatable, Sendable {
    public private(set) var selectedIDs: Set<String>

    public init(items: [CleanupItem]) {
        selectedIDs = Set(items.filter(\.isPreselected).map(\.id))
    }

    public init(selectedIDs: Set<String>) {
        self.selectedIDs = selectedIDs
    }

    public func contains(_ item: CleanupItem) -> Bool {
        selectedIDs.contains(item.id)
    }

    public mutating func setSelected(_ item: CleanupItem, isSelected: Bool) {
        if isSelected {
            selectedIDs.insert(item.id)
        } else {
            selectedIDs.remove(item.id)
        }
    }

    public mutating func setSelected(_ items: [CleanupItem], isSelected: Bool) {
        for item in items {
            setSelected(item, isSelected: isSelected)
        }
    }

    public func selectedBytes(in items: [CleanupItem]) -> UInt64 {
        items
            .filter { contains($0) }
            .reduce(0) { $0 + $1.sizeBytes }
    }
}

public enum CleanupReviewSort: String, CaseIterable, Identifiable, Codable, Sendable {
    case largestFirst
    case smallestFirst
    case nameAscending

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .largestFirst: "Largest"
        case .smallestFirst: "Smallest"
        case .nameAscending: "Name"
        }
    }
}

public struct CleanupReviewFilter: Equatable, Sendable {
    public var query: String
    public var category: CleanupCategory?
    public var sort: CleanupReviewSort

    public init(query: String, category: CleanupCategory? = nil, sort: CleanupReviewSort = .largestFirst) {
        self.query = query
        self.category = category
        self.sort = sort
    }

    public func apply(to items: [CleanupItem]) -> [CleanupItem] {
        let filtered = items.filter { item in
            matchesCategory(item) && matchesQuery(item)
        }

        return filtered.sorted { first, second in
            switch sort {
            case .largestFirst:
                if first.sizeBytes == second.sizeBytes {
                    return first.url.lastPathComponent.localizedCaseInsensitiveCompare(second.url.lastPathComponent) == .orderedAscending
                }
                return first.sizeBytes > second.sizeBytes
            case .smallestFirst:
                if first.sizeBytes == second.sizeBytes {
                    return first.url.lastPathComponent.localizedCaseInsensitiveCompare(second.url.lastPathComponent) == .orderedAscending
                }
                return first.sizeBytes < second.sizeBytes
            case .nameAscending:
                return first.url.lastPathComponent.localizedCaseInsensitiveCompare(second.url.lastPathComponent) == .orderedAscending
            }
        }
    }

    private var tokens: [String] {
        query
            .lowercased()
            .split { $0.isWhitespace }
            .map(String.init)
    }

    private func matchesCategory(_ item: CleanupItem) -> Bool {
        guard let category else { return true }
        return item.category == category
    }

    private func matchesQuery(_ item: CleanupItem) -> Bool {
        guard !tokens.isEmpty else { return true }
        let haystack = [
            item.url.lastPathComponent,
            item.url.path,
            item.category.title
        ]
        .joined(separator: " ")
        .lowercased()
        return tokens.allSatisfy { haystack.contains($0) }
    }
}

public struct CleanupScanner {
    public var homeDirectory: URL
    public var validator: ProtectedPathValidator
    public var fileManager: FileManager

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        validator: ProtectedPathValidator = ProtectedPathValidator(),
        fileManager: FileManager = .default
    ) {
        self.homeDirectory = homeDirectory
        self.validator = validator
        self.fileManager = fileManager
    }

    public func scan(
        categories: [CleanupCategory] = CleanupCategory.allCases,
        preselection: CleanupPreselectionMode = .none
    ) -> CleanupScanResult {
        var items = [CleanupItem]()
        var skipped = [String]()

        for category in categories {
            for url in roots(for: category) {
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
                if isTCCSensitiveMediaRoot(url) {
                    skipped.append(url.path)
                } else if validator.canDelete(url, resolvedURL: resolved(url)) {
                    items.append(CleanupItem(
                        category: category,
                        url: url,
                        sizeBytes: directorySize(url),
                        isPreselected: preselection == .recommended
                    ))
                } else {
                    skipped.append(url.path)
                }
            }
        }

        return CleanupScanResult(items: items.filter { $0.sizeBytes > 0 }, skipped: skipped)
    }

    private func roots(for category: CleanupCategory) -> [URL] {
        switch category {
        case .appCaches:
            return children(of: homeDirectory.appendingPathComponent("Library/Caches", isDirectory: true))
        case .logs:
            return children(of: homeDirectory.appendingPathComponent("Library/Logs", isDirectory: true))
        case .developerArtifacts:
            return [
                homeDirectory.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true),
                homeDirectory.appendingPathComponent(".npm", isDirectory: true),
                homeDirectory.appendingPathComponent(".gradle", isDirectory: true)
            ]
        case .aiToolCaches:
            return existingRoots([
                "Library/Caches/com.openai.chat",
                "Library/Caches/com.anthropic.claudefordesktop",
                "Library/Caches/com.github.Copilot",
                "Library/Caches/com.todesktop.230313mzl4w4u92",
                "Library/Application Support/Cursor/Cache",
                "Library/Application Support/Cursor/CachedData",
                "Library/Application Support/Code/Cache",
                "Library/Application Support/Code/CachedData"
            ])
        case .browserCaches:
            return [
                homeDirectory.appendingPathComponent("Library/Caches/com.apple.Safari", isDirectory: true),
                homeDirectory.appendingPathComponent("Library/Caches/Google/Chrome", isDirectory: true),
                homeDirectory.appendingPathComponent("Library/Caches/Arc", isDirectory: true),
                homeDirectory.appendingPathComponent("Library/Caches/Firefox", isDirectory: true)
            ]
        case .communicationCaches:
            return existingRoots([
                "Library/Application Support/Slack/Cache",
                "Library/Application Support/Slack/Code Cache",
                "Library/Application Support/Slack/Service Worker/CacheStorage",
                "Library/Application Support/Discord/Cache",
                "Library/Application Support/Discord/Code Cache",
                "Library/Application Support/zoom.us/data/Cache",
                "Library/Caches/us.zoom.xos",
                "Library/Caches/com.tinyspeck.slackmacgap"
            ])
        case .designToolCaches:
            return existingRoots([
                "Library/Application Support/Figma/Cache",
                "Library/Application Support/Figma/Code Cache",
                "Library/Caches/com.figma.Desktop",
                "Library/Caches/com.bohemiancoding.sketch3",
                "Library/Caches/com.adobe.CreativeCloud",
                "Library/Caches/com.adobe.accmac"
            ])
        case .cloudStorageCaches:
            return existingRoots([
                "Library/Application Support/Dropbox/Cache",
                "Library/Caches/com.getdropbox.dropbox",
                "Library/Application Support/Google/DriveFS",
                "Library/Caches/com.google.drivefs",
                "Library/Caches/com.microsoft.OneDrive"
            ])
        case .temporaryFiles:
            return existingRoots([
                "Library/Caches/TemporaryItems",
                "Library/Caches/com.apple.nsurlsessiond",
                ".cache"
            ])
        case .installers:
            return installerFiles(in: [
                homeDirectory.appendingPathComponent("Downloads", isDirectory: true),
                homeDirectory.appendingPathComponent("Library/Caches/Homebrew/downloads", isDirectory: true)
            ])
        }
    }

    private func installerFiles(in directories: [URL]) -> [URL] {
        let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "xip"]
        return directories.flatMap { directory in
            children(of: directory).filter { url in
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                    return false
                }
                return installerExtensions.contains(url.pathExtension.lowercased())
            }
        }
        .sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    private func existingRoots(_ relativePaths: [String]) -> [URL] {
        relativePaths
            .map { homeDirectory.appendingPathComponent($0, isDirectory: true) }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    private func children(of directory: URL) -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
            .sorted {
                $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
            }
    }

    private func directorySize(_ url: URL) -> UInt64 {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            return fileSize(url)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return 0
        }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            total += fileSize(fileURL)
        }
        return total
    }

    private func fileSize(_ url: URL) -> UInt64 {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
        return UInt64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
    }

    private func resolved(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
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
