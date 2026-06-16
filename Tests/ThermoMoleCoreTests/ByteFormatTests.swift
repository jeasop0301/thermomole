import XCTest
import ThermoMoleCore

final class ByteFormatTests: XCTestCase {
    func testFormatsBytesAndScales() {
        XCTAssertEqual(formatBytes(0), "0 B")
        XCTAssertEqual(formatBytes(512), "512 B")
        XCTAssertEqual(formatBytes(1024), "1.0 KB")
        XCTAssertEqual(formatBytes(65_536), "64.0 KB")
        XCTAssertEqual(formatBytes(1_572_864), "1.5 MB")
    }

    func testCleanupItemHasPublicInit() {
        let item = CleanupItem(category: .appCaches, url: URL(fileURLWithPath: "/tmp/x"), sizeBytes: 10, isPreselected: true)
        XCTAssertEqual(item.id, "/tmp/x")
        XCTAssertEqual(item.sizeBytes, 10)
    }
}
