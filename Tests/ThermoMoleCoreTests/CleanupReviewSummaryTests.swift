import XCTest
@testable import ThermoMoleCore

final class CleanupReviewSummaryTests: XCTestCase {
    func testCleanupReviewSummaryGroupsByCategoryAndPreselection() {
        let root = URL(fileURLWithPath: "/tmp/thermomole-tests", isDirectory: true)
        let result = CleanupScanResult(items: [
            CleanupItem(category: .appCaches, url: root.appendingPathComponent("cache-a"), sizeBytes: 100, isPreselected: true),
            CleanupItem(category: .appCaches, url: root.appendingPathComponent("cache-b"), sizeBytes: 300, isPreselected: false),
            CleanupItem(category: .logs, url: root.appendingPathComponent("log"), sizeBytes: 200, isPreselected: true)
        ], skipped: ["/System"])

        let summary = CleanupReviewSummary(result)

        XCTAssertEqual(summary.totalBytes, 600)
        XCTAssertEqual(summary.preselectedBytes, 300)
        XCTAssertEqual(summary.itemCount, 3)
        XCTAssertEqual(summary.skippedCount, 1)
        XCTAssertEqual(summary.categories.map(\.category), [.appCaches, .logs])
        XCTAssertEqual(summary.categories.map(\.bytes), [400, 200])
        XCTAssertEqual(summary.categories.map(\.itemCount), [2, 1])
    }

    func testCleanupReviewSelectionStartsWithPreselectedItemsAndTracksBytes() {
        let root = URL(fileURLWithPath: "/tmp/thermomole-tests", isDirectory: true)
        let first = CleanupItem(category: .appCaches, url: root.appendingPathComponent("cache-a"), sizeBytes: 100, isPreselected: true)
        let second = CleanupItem(category: .logs, url: root.appendingPathComponent("log"), sizeBytes: 200, isPreselected: false)
        let items = [first, second]

        var selection = CleanupReviewSelection(items: items)
        XCTAssertTrue(selection.contains(first))
        XCTAssertFalse(selection.contains(second))
        XCTAssertEqual(selection.selectedBytes(in: items), 100)

        selection.setSelected(second, isSelected: true)
        XCTAssertTrue(selection.contains(second))
        XCTAssertEqual(selection.selectedBytes(in: items), 300)

        selection.setSelected(first, isSelected: false)
        XCTAssertFalse(selection.contains(first))
        XCTAssertEqual(selection.selectedBytes(in: items), 200)
    }

    func testCleanupReviewFilterMatchesQueryCategoryAndSorts() {
        let root = URL(fileURLWithPath: "/tmp/thermomole-tests", isDirectory: true)
        let items = [
            CleanupItem(category: .appCaches, url: root.appendingPathComponent("Chrome Cache"), sizeBytes: 300, isPreselected: false),
            CleanupItem(category: .logs, url: root.appendingPathComponent("chrome.log"), sizeBytes: 100, isPreselected: false),
            CleanupItem(category: .developerArtifacts, url: root.appendingPathComponent("DerivedData"), sizeBytes: 900, isPreselected: false)
        ]

        let filtered = CleanupReviewFilter(
            query: "chrome",
            category: .appCaches,
            sort: .nameAscending
        ).apply(to: items)

        XCTAssertEqual(filtered.map { $0.url.lastPathComponent }, ["Chrome Cache"])
    }

    func testCleanupReviewFilterSortsLargestFirstByDefault() {
        let root = URL(fileURLWithPath: "/tmp/thermomole-tests", isDirectory: true)
        let items = [
            CleanupItem(category: .logs, url: root.appendingPathComponent("small"), sizeBytes: 10, isPreselected: false),
            CleanupItem(category: .logs, url: root.appendingPathComponent("large"), sizeBytes: 500, isPreselected: false),
            CleanupItem(category: .logs, url: root.appendingPathComponent("medium"), sizeBytes: 100, isPreselected: false)
        ]

        let filtered = CleanupReviewFilter(query: "", category: nil, sort: .largestFirst).apply(to: items)

        XCTAssertEqual(filtered.map { $0.url.lastPathComponent }, ["large", "medium", "small"])
    }

    func testCleanupReviewSelectionCanSelectAndClearBatches() {
        let root = URL(fileURLWithPath: "/tmp/thermomole-tests", isDirectory: true)
        let first = CleanupItem(category: .appCaches, url: root.appendingPathComponent("cache-a"), sizeBytes: 100, isPreselected: false)
        let second = CleanupItem(category: .logs, url: root.appendingPathComponent("log"), sizeBytes: 200, isPreselected: false)
        var selection = CleanupReviewSelection(items: [])

        selection.setSelected([first, second], isSelected: true)
        XCTAssertTrue(selection.contains(first))
        XCTAssertTrue(selection.contains(second))
        XCTAssertEqual(selection.selectedBytes(in: [first, second]), 300)

        selection.setSelected([first], isSelected: false)
        XCTAssertFalse(selection.contains(first))
        XCTAssertTrue(selection.contains(second))
        XCTAssertEqual(selection.selectedBytes(in: [first, second]), 200)
    }

    func testSmartCleanupReviewPlanSummarizesPreselectedItemsForOneClickConfirmation() {
        let root = URL(fileURLWithPath: "/tmp/thermomole-tests", isDirectory: true)
        let first = CleanupItem(category: .appCaches, url: root.appendingPathComponent("cache-a"), sizeBytes: 100, isPreselected: true)
        let second = CleanupItem(category: .logs, url: root.appendingPathComponent("log"), sizeBytes: 200, isPreselected: true)
        let manual = CleanupItem(category: .developerArtifacts, url: root.appendingPathComponent("DerivedData"), sizeBytes: 900, isPreselected: false)
        let result = CleanupScanResult(items: [first, second, manual], skipped: ["/System"])

        let plan = SmartCleanupReviewPlan(result)

        XCTAssertTrue(plan.hasSelection)
        XCTAssertEqual(plan.selectedItemCount, 2)
        XCTAssertEqual(plan.selectedBytes, 300)
        XCTAssertEqual(plan.skippedCount, 1)
        XCTAssertEqual(plan.selection.selectedIDs, [first.id, second.id])
    }

    func testCleanupConfirmationSummaryDescribesSelectedItemsByCategoryAndExamplePaths() {
        let root = URL(fileURLWithPath: "/tmp/thermomole-tests", isDirectory: true)
        let cache = CleanupItem(category: .appCaches, url: root.appendingPathComponent("cache-a"), sizeBytes: 100, isPreselected: true)
        let logs = CleanupItem(category: .logs, url: root.appendingPathComponent("logs"), sizeBytes: 500, isPreselected: true)
        let browser = CleanupItem(category: .browserCaches, url: root.appendingPathComponent("browser"), sizeBytes: 300, isPreselected: true)
        let unselected = CleanupItem(category: .developerArtifacts, url: root.appendingPathComponent("DerivedData"), sizeBytes: 900, isPreselected: false)
        let result = CleanupScanResult(items: [cache, logs, browser, unselected], skipped: ["/System", "/private/var"])
        let selection = CleanupReviewSelection(items: [cache, logs, browser, unselected])

        let summary = CleanupConfirmationSummary(result: result, selection: selection)

        XCTAssertTrue(summary.hasSelection)
        XCTAssertEqual(summary.itemCount, 3)
        XCTAssertEqual(summary.selectedBytes, 900)
        XCTAssertEqual(summary.skippedCount, 2)
        XCTAssertEqual(summary.categoryLines, [
            "Logs: 1 item",
            "Browser Caches: 1 item",
            "App Caches: 1 item"
        ])
        XCTAssertEqual(summary.examplePaths, [
            "/tmp/thermomole-tests/logs",
            "/tmp/thermomole-tests/browser",
            "/tmp/thermomole-tests/cache-a"
        ])
        XCTAssertTrue(summary.confirmationMessage.contains("3 items"))
        XCTAssertTrue(summary.confirmationMessage.contains("900 B"))
        XCTAssertFalse(summary.confirmationMessage.contains("DerivedData"))
    }
}
