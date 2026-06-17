import Foundation
import XCTest
@testable import ThermoMoleCore

final class MaintenanceScannerTests: XCTestCase {
    func testCleanScannerProducesReviewItemsWithoutDeletingFiles() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("Library/Caches/com.example", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let file = cache.appendingPathComponent("cache.bin")
        try Data(repeating: 7, count: 128).write(to: file)

        let scanner = CleanupScanner(
            homeDirectory: root,
            validator: ProtectedPathValidator(homeDirectory: root)
        )
        let result = scanner.scan(categories: [.appCaches])

        XCTAssertEqual(result.items.count, 1)
        XCTAssertGreaterThanOrEqual(result.items.first?.sizeBytes ?? 0, 128)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testCleanScannerDoesNotPreselectReviewItemsByDefault() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("Library/Caches/com.example", isDirectory: true)
        let log = root.appendingPathComponent("Library/Logs/com.example", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: log, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 64).write(to: cache.appendingPathComponent("cache.bin"))
        try Data(repeating: 2, count: 64).write(to: log.appendingPathComponent("log.txt"))

        let scanner = CleanupScanner(
            homeDirectory: root,
            validator: ProtectedPathValidator(homeDirectory: root)
        )
        let result = scanner.scan(categories: [.appCaches, .logs])

        XCTAssertEqual(result.items.count, 2)
        XCTAssertTrue(result.items.allSatisfy { !$0.isPreselected })
        XCTAssertTrue(CleanupReviewSelection(items: result.items).selectedIDs.isEmpty)
    }

    func testCleanScannerCanPreselectRecommendedItemsForOneClickClean() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("Library/Caches/com.example", isDirectory: true)
        let log = root.appendingPathComponent("Library/Logs/com.example", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: log, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 64).write(to: cache.appendingPathComponent("cache.bin"))
        try Data(repeating: 2, count: 64).write(to: log.appendingPathComponent("log.txt"))

        let scanner = CleanupScanner(
            homeDirectory: root,
            validator: ProtectedPathValidator(homeDirectory: root)
        )
        let result = scanner.scan(categories: [.appCaches, .logs], preselection: .recommended)
        let selection = CleanupReviewSelection(items: result.items)

        XCTAssertEqual(result.items.count, 2)
        XCTAssertTrue(result.items.allSatisfy(\.isPreselected))
        XCTAssertEqual(selection.selectedIDs, Set(result.items.map(\.id)))
    }

    func testCleanScannerSkipsTCCSensitiveMediaCacheRootsBeforeSizing() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let safe = root.appendingPathComponent("Library/Caches/com.example", isDirectory: true)
        let media = root.appendingPathComponent("Library/Caches/com.apple.Music", isDirectory: true)
        try FileManager.default.createDirectory(at: safe, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 64).write(to: safe.appendingPathComponent("cache.bin"))
        try Data(repeating: 2, count: 64).write(to: media.appendingPathComponent("media-cache.bin"))

        let scanner = CleanupScanner(
            homeDirectory: root,
            validator: ProtectedPathValidator(homeDirectory: root)
        )
        let result = scanner.scan(categories: [.appCaches])

        XCTAssertEqual(result.items.map { $0.url.lastPathComponent }, ["com.example"])
        XCTAssertEqual(result.skipped.count, 1)
        XCTAssertTrue(result.skipped[0].hasSuffix("/Library/Caches/com.apple.Music"))
    }

    func testCleanScannerFindsExpandedCacheCategories() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let targets: [(CleanupCategory, String)] = [
            (.aiToolCaches, "Library/Caches/com.openai.chat"),
            (.communicationCaches, "Library/Application Support/Slack/Cache"),
            (.designToolCaches, "Library/Application Support/Figma/Cache"),
            (.cloudStorageCaches, "Library/Application Support/Dropbox/Cache"),
            (.temporaryFiles, "Library/Caches/TemporaryItems")
        ]

        for (_, relativePath) in targets {
            let directory = root.appendingPathComponent(relativePath, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(repeating: 4, count: 96).write(to: directory.appendingPathComponent("payload.bin"))
        }

        let scanner = CleanupScanner(
            homeDirectory: root,
            validator: ProtectedPathValidator(homeDirectory: root)
        )
        let result = scanner.scan(categories: targets.map(\.0))

        XCTAssertEqual(Set(result.items.map(\.category)), Set(targets.map(\.0)))
        XCTAssertTrue(result.items.allSatisfy { !$0.isPreselected })
        XCTAssertTrue(result.items.allSatisfy { $0.sizeBytes >= 96 })
    }

    func testCleanScannerFindsInstallerFilesWithoutIncludingOrdinaryDownloads() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let downloads = root.appendingPathComponent("Downloads", isDirectory: true)
        let homebrewDownloads = root.appendingPathComponent("Library/Caches/Homebrew/downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: homebrewDownloads, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 64).write(to: downloads.appendingPathComponent("ThermoMole.dmg"))
        try Data(repeating: 2, count: 64).write(to: downloads.appendingPathComponent("Notes.txt"))
        try Data(repeating: 3, count: 64).write(to: homebrewDownloads.appendingPathComponent("Tool.pkg"))

        let scanner = CleanupScanner(
            homeDirectory: root,
            validator: ProtectedPathValidator(homeDirectory: root)
        )
        let result = scanner.scan(categories: [.installers], preselection: .recommended)

        XCTAssertEqual(result.items.map { $0.url.lastPathComponent }, ["ThermoMole.dmg", "Tool.pkg"])
        XCTAssertTrue(result.items.allSatisfy { $0.category == .installers })
        XCTAssertTrue(result.items.allSatisfy(\.isPreselected))
        XCTAssertFalse(result.items.contains { $0.url.lastPathComponent == "Notes.txt" })
    }

    func testCleanupExecutorMovesOnlySelectedSafeItemsToTrashAndLogsOperations() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let trash = root.appendingPathComponent("Trash", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)

        let cacheRoot = root.appendingPathComponent("Library/Caches/com.example", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let selectedURL = cacheRoot.appendingPathComponent("selected.cache")
        let ignoredURL = cacheRoot.appendingPathComponent("ignored.cache")
        try Data(repeating: 1, count: 64).write(to: selectedURL)
        try Data(repeating: 2, count: 32).write(to: ignoredURL)

        let selectedItem = CleanupItem(category: .appCaches, url: selectedURL, sizeBytes: 64, isPreselected: true)
        let ignoredItem = CleanupItem(category: .appCaches, url: ignoredURL, sizeBytes: 32, isPreselected: false)
        let selection = CleanupReviewSelection(selectedIDs: [selectedItem.id])
        let executor = CleanupExecutor(
            validator: ProtectedPathValidator(homeDirectory: root),
            trashItem: { url in
                let destination = trash.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: destination)
                return destination
            }
        )

        let result = executor.execute(items: [selectedItem, ignoredItem], selection: selection, mode: .trash)

        XCTAssertEqual(result.succeededCount, 1)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(result.reclaimedBytes, 64)
        XCTAssertFalse(FileManager.default.fileExists(atPath: selectedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ignoredURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.appendingPathComponent("selected.cache").path))
        XCTAssertEqual(result.entries.map(\.status), [.succeeded])
        XCTAssertEqual(result.entries.first?.mode, .trash)
    }

    func testCleanupExecutorSkipsProtectedSelectedItems() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let item = CleanupItem(category: .appCaches, url: root, sizeBytes: 64, isPreselected: true)
        let selection = CleanupReviewSelection(selectedIDs: [item.id])
        let executor = CleanupExecutor(
            validator: ProtectedPathValidator(homeDirectory: root),
            trashItem: { _ in XCTFail("Protected item should not be trashed"); return root }
        )

        let result = executor.execute(items: [item], selection: selection, mode: .trash)

        XCTAssertEqual(result.succeededCount, 0)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(result.entries.first?.status, .skipped)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
    }

    func testTrashIsNotACleanupCategory() {
        // ~/.Trash cleanup can only work by permanently deleting, which ThermoMole
        // intentionally excludes — so Trash must not be an offered cleanup category.
        XCTAssertFalse(CleanupCategory.allCases.contains { $0.title == "Trash" })
    }
}
