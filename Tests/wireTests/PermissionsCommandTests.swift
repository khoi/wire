import XCTest
@testable import wire

final class PermissionsCommandTests: WireCommandTestCase {
    func testPermissionsCommandPrintsPermissionsHelp() async {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["permissions"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(output.stdout.contains("USAGE: wire permissions"))
        XCTAssertTrue(output.stdout.contains("status"))
        XCTAssertTrue(output.stdout.contains("grant"))
        XCTAssertEqual(output.stderr, "")
    }

    func testRootHelpFlagExitsCleanly() async {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["--help"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(output.stdout.contains("USAGE: wire"))
        XCTAssertTrue(output.stdout.contains("app"))
        XCTAssertTrue(output.stdout.contains("Manage running applications"))
        XCTAssertTrue(output.stdout.contains("click"))
        XCTAssertTrue(output.stdout.contains("inspect"))
        XCTAssertTrue(output.stdout.contains("press"))
        XCTAssertTrue(output.stdout.contains("Press a key or key combo"))
        XCTAssertTrue(output.stdout.contains("scroll"))
        XCTAssertTrue(output.stdout.contains("permissions"))
        XCTAssertTrue(output.stdout.contains("Check and grant required permissions"))
        XCTAssertEqual(output.stderr, "")
    }
}
