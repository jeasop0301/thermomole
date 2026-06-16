import XCTest
@testable import ThermoMoleCore

final class MenuBarActionTests: XCTestCase {
    func testMenuBarQuickActionsAreRemoved() {
        XCTAssertTrue(MenuBarAction.allCases.isEmpty)
    }
}
