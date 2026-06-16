import Foundation
import XCTest
@testable import ThermoMoleCore

final class AppUninstallExecutorTests: XCTestCase {
    private func app(at path: String) -> InstalledApp {
        InstalledApp(name: "Example", bundleIdentifier: "com.example.app", bundlePath: path)
    }

    func testRefusesAppBundleOutsideAllowedRoots() {
        let sentinel = URL(fileURLWithPath: "/sentinel/trashed")
        let executor = AppUninstallExecutor(trashItem: { _ in sentinel })

        let result = executor.moveToTrash(app(at: "/System/Library/CoreServices/Finder.app"))

        XCTAssertEqual(result.status, .failed)
        XCTAssertNil(result.destinationURL)
        XCTAssertEqual(result.message, "Protected path blocked")
    }

    func testRefusesNonAppBundlePath() {
        let sentinel = URL(fileURLWithPath: "/sentinel/trashed")
        let executor = AppUninstallExecutor(trashItem: { _ in sentinel })

        let result = executor.moveToTrash(app(at: "/Applications"))

        XCTAssertEqual(result.status, .failed)
        XCTAssertNil(result.destinationURL)
    }

    func testTrashesAppBundleInApplications() {
        let sentinel = URL(fileURLWithPath: "/Users/example/.Trash/Example.app")
        let executor = AppUninstallExecutor(trashItem: { _ in sentinel })

        let result = executor.moveToTrash(app(at: "/Applications/Example.app"))

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.destinationURL, sentinel)
    }
}
