import Foundation

public struct DiskBreadcrumb: Identifiable, Equatable, Sendable {
    public var id: String { url.path }
    public var title: String
    public var url: URL

    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }
}

public struct DiskAnalysisPath: Equatable, Sendable {
    public private(set) var urls: [URL]

    public init(rootURL: URL) {
        urls = [rootURL.standardizedFileURL]
    }

    public var rootURL: URL {
        urls[0]
    }

    public var currentURL: URL {
        urls[urls.count - 1]
    }

    public var canGoUp: Bool {
        urls.count > 1
    }

    public var breadcrumbs: [DiskBreadcrumb] {
        urls.map { url in
            DiskBreadcrumb(
                title: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
                url: url
            )
        }
    }

    public mutating func push(_ url: URL) {
        let standardized = url.standardizedFileURL
        if let existingIndex = urls.firstIndex(of: standardized) {
            urls = Array(urls.prefix(existingIndex + 1))
        } else {
            urls.append(standardized)
        }
    }

    public mutating func popTo(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard let existingIndex = urls.firstIndex(of: standardized) else { return }
        urls = Array(urls.prefix(existingIndex + 1))
    }

    public mutating func popUp() {
        guard canGoUp else { return }
        urls.removeLast()
    }

    public mutating func reset(to url: URL) {
        urls = [url.standardizedFileURL]
    }
}

public struct DiskTreemapItem: Identifiable, Equatable, Sendable {
    public var id: String { entry.id }
    public var entry: DiskEntry
    public var ratio: Double
    public var isLargest: Bool

    public init(entry: DiskEntry, ratio: Double, isLargest: Bool) {
        self.entry = entry
        self.ratio = ratio
        self.isLargest = isLargest
    }

    public static func items(from entries: [DiskEntry], limit: Int = 16) -> [DiskTreemapItem] {
        let total = entries.reduce(UInt64(0)) { $0 + $1.sizeBytes }
        guard total > 0 else { return [] }

        return entries
            .prefix(max(1, limit))
            .enumerated()
            .map { index, entry in
                DiskTreemapItem(
                    entry: entry,
                    ratio: Double(entry.sizeBytes) / Double(total),
                    isLargest: index == 0
                )
            }
    }
}

public struct DiskTrashConfirmationSummary: Equatable, Sendable {
    public var title: String
    public var itemName: String
    public var path: String
    public var kind: String
    public var sizeBytes: UInt64

    public init(entry: DiskEntry) {
        itemName = entry.url.lastPathComponent.isEmpty ? entry.url.path : entry.url.lastPathComponent
        path = entry.url.path
        kind = entry.isDirectory ? "Folder" : "File"
        sizeBytes = entry.sizeBytes
        title = "Move \(itemName) to Trash?"
    }

    public var confirmationMessage: String {
        [
            "\(kind) · \(Self.formatBytes(sizeBytes))",
            "Path: \(path)",
            "Mode: Move to Trash"
        ].joined(separator: "\n")
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        guard bytes >= 1_024 else { return "\(bytes) B" }
        let units = ["KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = -1
        repeat {
            value /= 1_024
            unitIndex += 1
        } while value >= 1_024 && unitIndex < units.count - 1
        return String(format: "%.1f %@", value, units[unitIndex])
    }
}
