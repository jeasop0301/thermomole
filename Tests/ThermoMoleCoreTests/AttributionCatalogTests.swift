import XCTest
@testable import ThermoMoleCore

final class AttributionCatalogTests: XCTestCase {
    func testDefaultCatalogIncludesReferencedProjectsAndLicenseNotes() {
        let catalog = AttributionCatalog.default

        XCTAssertEqual(catalog.summary, "ThermoMole is an open-source macOS menu-bar utility for Apple Silicon, released under the GNU General Public License v3.0.")
        XCTAssertEqual(catalog.entries.map(\.name), ["MacMonitor", "Mole", "Mole product site"])
        XCTAssertEqual(catalog.entries.map(\.url), [
            "https://github.com/ryyansafar/MacMonitor",
            "https://github.com/tw93/mole",
            "https://mole.fit/"
        ])
        XCTAssertTrue(catalog.entries[0].note.contains("SMC access pattern"))
        XCTAssertTrue(catalog.entries[1].note.contains("five-tool product shape"))
        XCTAssertTrue(catalog.licenseNotice.contains("GNU General Public License v3.0"))
        XCTAssertTrue(catalog.licenseNotice.contains("no code is copied"))
        XCTAssertTrue(catalog.licenseNotice.contains("independent reimplementation"))
    }
}
