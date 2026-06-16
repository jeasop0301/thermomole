import Foundation
import XCTest
@testable import ThermoMoleCore

final class ProtectedPathTests: XCTestCase {
    func testProtectedPathCatalogDocumentsDefaultPolicyForSettings() {
        let catalog = ProtectedPathCatalog.default(homeDirectory: URL(fileURLWithPath: "/Users/jisub"))

        XCTAssertEqual(catalog.summary, "Trash actions are limited to known disposable locations.")
        XCTAssertTrue(catalog.protectedRoots.contains("/System"))
        XCTAssertTrue(catalog.protectedRoots.contains("/Applications"))
        XCTAssertTrue(catalog.protectedRoots.contains("/Users/jisub/Documents"))
        XCTAssertTrue(catalog.allowedDeletePrefixes.contains("/Users/jisub/Library/Caches/"))
        XCTAssertTrue(catalog.allowedDeletePrefixes.contains("/Users/jisub/Library/Logs/"))
        XCTAssertTrue(catalog.defaultScanSkips.contains("~/Music"))
        XCTAssertTrue(catalog.defaultScanSkips.contains("~/Pictures"))
        XCTAssertTrue(catalog.defaultScanSkips.contains("~/Desktop"))
    }

    func testRejectsProtectedRoots() {
        let validator = ProtectedPathValidator(homeDirectory: URL(fileURLWithPath: "/Users/jisub"))

        XCTAssertFalse(validator.canDelete(URL(fileURLWithPath: "/")))
        XCTAssertFalse(validator.canDelete(URL(fileURLWithPath: "/System/Library/Caches")))
        XCTAssertFalse(validator.canDelete(URL(fileURLWithPath: "/Users/jisub")))
    }

    func testAllowsCacheDescendants() {
        let validator = ProtectedPathValidator(homeDirectory: URL(fileURLWithPath: "/Users/jisub"))

        XCTAssertTrue(validator.canDelete(URL(fileURLWithPath: "/Users/jisub/Library/Caches/com.example.cache")))
        XCTAssertTrue(validator.canDelete(URL(fileURLWithPath: "/Users/jisub/Library/Logs/example.log")))
    }

    func testRejectsSymlinkEscape() {
        let validator = ProtectedPathValidator(homeDirectory: URL(fileURLWithPath: "/Users/jisub"))

        XCTAssertFalse(validator.canDelete(
            URL(fileURLWithPath: "/Users/jisub/Library/Caches/link"),
            resolvedURL: URL(fileURLWithPath: "/private/etc/passwd")
        ))
    }

    func testAllowsAppBundlesInApplicationRoots() {
        let validator = ProtectedPathValidator(homeDirectory: URL(fileURLWithPath: "/Users/jisub"))

        XCTAssertTrue(validator.canTrashAppBundle(URL(fileURLWithPath: "/Applications/Example.app")))
        XCTAssertTrue(validator.canTrashAppBundle(URL(fileURLWithPath: "/Applications/Utilities/Nested.app")))
        XCTAssertTrue(validator.canTrashAppBundle(URL(fileURLWithPath: "/Users/jisub/Applications/Setapp/Tool.app")))
    }

    func testRejectsNonAppBundlePathsForUninstall() {
        let validator = ProtectedPathValidator(homeDirectory: URL(fileURLWithPath: "/Users/jisub"))

        XCTAssertFalse(validator.canTrashAppBundle(URL(fileURLWithPath: "/Applications")))
        XCTAssertFalse(validator.canTrashAppBundle(URL(fileURLWithPath: "/Applications/notanapp")))
    }

    func testRejectsAppBundlesOutsideAllowedRoots() {
        let validator = ProtectedPathValidator(homeDirectory: URL(fileURLWithPath: "/Users/jisub"))

        XCTAssertFalse(validator.canTrashAppBundle(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")))
        XCTAssertFalse(validator.canTrashAppBundle(URL(fileURLWithPath: "/Users/jisub/Documents/Evil.app")))
    }

    func testRejectsAppBundleSymlinkEscape() {
        let validator = ProtectedPathValidator(homeDirectory: URL(fileURLWithPath: "/Users/jisub"))

        XCTAssertFalse(validator.canTrashAppBundle(
            URL(fileURLWithPath: "/Applications/Evil.app"),
            resolvedURL: URL(fileURLWithPath: "/System/Library/Evil")
        ))
    }
}
