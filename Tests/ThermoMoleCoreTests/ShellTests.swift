import XCTest
@testable import ThermoMoleCore

final class ShellTests: XCTestCase {
    func testShellRunTimesOutLongRunningProcess() {
        let startedAt = Date()
        let result = Shell.run("/bin/sleep", ["2"], timeoutSeconds: 0.1)

        XCTAssertEqual(result.status, 124)
        XCTAssertTrue(result.stderr.localizedCaseInsensitiveContains("timed out"))
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 1.0)
    }

    func testShellRunDrainsLargeStdoutWhileProcessRuns() {
        let script = """
        i=0
        while [ "$i" -lt 20000 ]; do
          printf 'thermomole-sample-output-line-%05d-abcdefghijklmnopqrstuvwxyz\\n' "$i"
          i=$((i + 1))
        done
        """

        let result = Shell.run("/bin/sh", ["-c", script], timeoutSeconds: 2.0)

        XCTAssertEqual(result.status, 0)
        XCTAssertGreaterThan(result.stdout.count, 1_000_000)
        XCTAssertEqual(result.stderr, "")
    }
}
