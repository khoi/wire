import XCTest
@testable import wire

final class PermissionsCommandTests: WireCommandTestCase {
    func testPermissionsCommandPrintsPermissionsHelp() {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = WireRunner.run(
            arguments: ["permissions"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(output.stdout.contains("USAGE: wire permissions"))
        XCTAssertTrue(output.stdout.contains("status"))
        XCTAssertTrue(output.stdout.contains("grant"))
        XCTAssertEqual(output.stderr, "")
    }
}
