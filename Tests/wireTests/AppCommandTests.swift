import XCTest
@testable import wire

final class AppCommandTests: WireCommandTestCase {
    func testAppCommandPrintsAppHelp() async {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["app"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(output.stdout.contains("USAGE: wire app"))
        XCTAssertTrue(output.stdout.contains("list"))
        XCTAssertTrue(output.stdout.contains("List running applications"))
        XCTAssertTrue(output.stdout.contains("launch"))
        XCTAssertTrue(output.stdout.contains("Launch an application"))
        XCTAssertEqual(output.stderr, "")
    }

    func testAppHelpFlagExitsCleanly() async {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["app", "--help"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(output.stdout.contains("USAGE: wire app"))
        XCTAssertTrue(output.stdout.contains("list"))
        XCTAssertTrue(output.stdout.contains("List running applications"))
        XCTAssertTrue(output.stdout.contains("launch"))
        XCTAssertTrue(output.stdout.contains("Launch an application"))
        XCTAssertEqual(output.stderr, "")
    }
}
