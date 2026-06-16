import XCTest
@testable import ThermoMoleCore

final class DiskAnalysisTests: XCTestCase {
    func testDiskAnalysisPathNavigatesIntoDirectoriesAndBack() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let documents = home.appendingPathComponent("Documents", isDirectory: true)
        let project = documents.appendingPathComponent("Project", isDirectory: true)

        var path = DiskAnalysisPath(rootURL: home)
        XCTAssertEqual(path.currentURL, home)
        XCTAssertEqual(path.breadcrumbs.map(\.title), ["test"])

        path.push(documents)
        path.push(project)
        XCTAssertEqual(path.currentURL, project)
        XCTAssertEqual(path.breadcrumbs.map(\.title), ["test", "Documents", "Project"])

        path.popTo(home)
        XCTAssertEqual(path.currentURL, home)
        XCTAssertEqual(path.breadcrumbs.map(\.title), ["test"])
    }

    func testTreemapItemsUseStableRatiosAndLimit() {
        let root = URL(fileURLWithPath: "/tmp/thermomole", isDirectory: true)
        let entries = [
            DiskEntry(url: root.appendingPathComponent("A"), sizeBytes: 70, isDirectory: true),
            DiskEntry(url: root.appendingPathComponent("B"), sizeBytes: 20, isDirectory: false),
            DiskEntry(url: root.appendingPathComponent("C"), sizeBytes: 10, isDirectory: false)
        ]

        let items = DiskTreemapItem.items(from: entries, limit: 2)

        XCTAssertEqual(items.map(\.entry.url.lastPathComponent), ["A", "B"])
        XCTAssertEqual(items.map(\.ratio), [0.7, 0.2])
        XCTAssertTrue(items.first?.isLargest ?? false)
        XCTAssertFalse(items.last?.isLargest ?? true)
    }

    func testDiskAnalyzerReturnsNoEntriesWhenCanceledBeforeSizing() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("large.log")
        try Data(repeating: 1, count: 1024).write(to: file)

        let entries = DiskAnalyzer().analyze(root, shouldCancel: { true })

        XCTAssertTrue(entries.isEmpty)
    }

    func testDiskAnalyzerSkipsHomeMediaRootsBeforeSizing() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let music = home.appendingPathComponent("Music", isDirectory: true)
        let projects = home.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 128).write(to: music.appendingPathComponent("library-track.bin"))
        try Data(repeating: 2, count: 64).write(to: projects.appendingPathComponent("archive.bin"))

        let entries = DiskAnalyzer(homeDirectory: home).analyze(home)

        XCTAssertFalse(entries.contains { $0.url.lastPathComponent == "Music" })
        XCTAssertTrue(entries.contains { $0.url.lastPathComponent == "Projects" })
    }

    func testDiskAnalyzerSkipsHomeLibraryBeforeSizing() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let projects = home.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 128).write(to: library.appendingPathComponent("state.bin"))
        try Data(repeating: 2, count: 64).write(to: projects.appendingPathComponent("archive.bin"))

        let entries = DiskAnalyzer(homeDirectory: home).analyze(home)

        XCTAssertFalse(entries.contains { $0.url.lastPathComponent == "Library" })
        XCTAssertTrue(entries.contains { $0.url.lastPathComponent == "Projects" })
    }

    func testDiskAnalyzerSkipsHomeFileAccessPrivacyRootsBeforeSizing() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        let documents = home.appendingPathComponent("Documents", isDirectory: true)
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        let projects = home.appendingPathComponent("Projects", isDirectory: true)
        for url in [desktop, documents, downloads, projects] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 64).write(to: url.appendingPathComponent("file.bin"))
        }

        let entries = DiskAnalyzer(homeDirectory: home).analyze(home)

        XCTAssertFalse(entries.contains { $0.url.lastPathComponent == "Desktop" })
        XCTAssertFalse(entries.contains { $0.url.lastPathComponent == "Documents" })
        XCTAssertFalse(entries.contains { $0.url.lastPathComponent == "Downloads" })
        XCTAssertTrue(entries.contains { $0.url.lastPathComponent == "Projects" })
    }

    func testDiskAnalyzerSkipsSensitiveMediaCacheRootsBeforeSizing() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let caches = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let musicCache = caches.appendingPathComponent("com.apple.Music", isDirectory: true)
        let appCache = caches.appendingPathComponent("ExampleApp", isDirectory: true)
        try FileManager.default.createDirectory(at: musicCache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appCache, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 128).write(to: musicCache.appendingPathComponent("media-cache.bin"))
        try Data(repeating: 2, count: 64).write(to: appCache.appendingPathComponent("safe-cache.bin"))

        let entries = DiskAnalyzer(homeDirectory: home).analyze(caches)

        XCTAssertFalse(entries.contains { $0.url.lastPathComponent == "com.apple.Music" })
        XCTAssertTrue(entries.contains { $0.url.lastPathComponent == "ExampleApp" })
    }

    func testDiskAnalysisPathCanResetToChosenFolder() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let project = URL(fileURLWithPath: "/Users/test/Projects/ThermoMole", isDirectory: true)
        var path = DiskAnalysisPath(rootURL: home)
        path.push(home.appendingPathComponent("Documents", isDirectory: true))

        path.reset(to: project)

        XCTAssertEqual(path.currentURL, project.standardizedFileURL)
        XCTAssertEqual(path.rootURL, project.standardizedFileURL)
        XCTAssertEqual(path.breadcrumbs.map(\.title), ["ThermoMole"])
    }

    func testDiskTrashConfirmationSummaryDescribesFolderSelection() {
        let entry = DiskEntry(
            url: URL(fileURLWithPath: "/Users/test/Library/Caches/BigCache", isDirectory: true),
            sizeBytes: 1_572_864,
            isDirectory: true
        )

        let summary = DiskTrashConfirmationSummary(entry: entry)

        XCTAssertEqual(summary.title, "Move BigCache to Trash?")
        XCTAssertEqual(summary.itemName, "BigCache")
        XCTAssertEqual(summary.kind, "Folder")
        XCTAssertEqual(summary.sizeBytes, 1_572_864)
        XCTAssertTrue(summary.confirmationMessage.contains("Folder · 1.5 MB"))
        XCTAssertTrue(summary.confirmationMessage.contains("Path: /Users/test/Library/Caches/BigCache"))
        XCTAssertTrue(summary.confirmationMessage.contains("Mode: Move to Trash"))
    }

    func testDiskTrashConfirmationSummaryDescribesFileSelection() {
        let entry = DiskEntry(
            url: URL(fileURLWithPath: "/Users/test/Library/Logs/app.log"),
            sizeBytes: 900,
            isDirectory: false
        )

        let summary = DiskTrashConfirmationSummary(entry: entry)

        XCTAssertEqual(summary.title, "Move app.log to Trash?")
        XCTAssertEqual(summary.itemName, "app.log")
        XCTAssertEqual(summary.kind, "File")
        XCTAssertTrue(summary.confirmationMessage.contains("File · 900 B"))
    }

    func testDiskEntryTrashExecutorMovesAllowedEntryToTrashAndLogs() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home
            .appendingPathComponent("Library/Caches", isDirectory: true)
            .appendingPathComponent("old-cache.bin")
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([1, 2, 3, 4]).write(to: file)
        let trashRoot = home.appendingPathComponent(".Trash", isDirectory: true)
        let entry = DiskEntry(url: file, sizeBytes: 4, isDirectory: false)
        let executor = DiskEntryTrashExecutor(
            validator: ProtectedPathValidator(homeDirectory: home),
            trashItem: { url in
                try FileManager.default.createDirectory(at: trashRoot, withIntermediateDirectories: true)
                let destination = trashRoot.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: destination)
                return destination
            }
        )

        let result = executor.moveToTrash(entry, at: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(result.entry, entry)
        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.destinationURL, trashRoot.appendingPathComponent("old-cache.bin"))
        XCTAssertEqual(result.message, "Moved to Trash")
        XCTAssertEqual(result.executedAt, Date(timeIntervalSince1970: 100))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashRoot.appendingPathComponent("old-cache.bin").path))
    }

    func testDiskEntryTrashExecutorSkipsProtectedEntry() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("keep.txt")
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([1, 2, 3, 4]).write(to: file)
        let entry = DiskEntry(url: file, sizeBytes: 4, isDirectory: false)
        let executor = DiskEntryTrashExecutor(
            validator: ProtectedPathValidator(homeDirectory: home),
            trashItem: { url in
                XCTFail("Protected Analyze entries must not be trashed: \(url.path)")
                return url
            }
        )

        let result = executor.moveToTrash(entry)

        XCTAssertEqual(result.status, .skipped)
        XCTAssertEqual(result.destinationURL, nil)
        XCTAssertEqual(result.message, "Protected path skipped")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    private func makeTemporaryHome() throws -> URL {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }
}
