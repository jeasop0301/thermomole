import XCTest
@testable import ThermoMoleCore

final class AttributionCatalogTests: XCTestCase {
    func testDefaultCatalogIncludesReferencedProjectsAndLicenseNotes() {
        let catalog = AttributionCatalog.default

        XCTAssertEqual(catalog.summary, "ThermoMole is private local software.")
        XCTAssertEqual(catalog.entries.map(\.name), ["MacMonitor", "Mole", "Mole product site"])
        XCTAssertEqual(catalog.entries.map(\.url), [
            "https://github.com/ryyansafar/MacMonitor",
            "https://github.com/tw93/mole",
            "https://mole.fit/"
        ])
        XCTAssertTrue(catalog.entries[0].note.contains("SMC access pattern"))
        XCTAssertTrue(catalog.entries[1].note.contains("five-tool product shape"))
        XCTAssertTrue(catalog.licenseNotice.contains("MacMonitor is MIT"))
        XCTAssertTrue(catalog.licenseNotice.contains("Mole's GitHub repository includes GPL-3.0"))
    }
}
