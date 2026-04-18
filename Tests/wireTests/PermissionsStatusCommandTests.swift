import XCTest
@testable import wire

final class PermissionsStatusCommandTests: WireCommandTestCase {
    func testStatusReturnsJSON() async throws {
        let state = PermissionState(accessibility: true, screenRecording: false)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["permissions", "status"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(output.stderr, "")

        let response = try decode(StatusEnvelope.self, from: output.stdout)
        XCTAssertEqual(
            response.data.permissions,
            [
                .init(kind: "accessibility", granted: true),
                .init(kind: "screen-recording", granted: false),
            ]
        )
    }

    func testStatusSupportsPlainFlagAtEveryCommandLevel() async {
        let expected = "accessibility: granted\nscreen-recording: missing\n"
        let cases = [
            ["--plain", "permissions", "status"],
            ["permissions", "--plain", "status"],
            ["permissions", "status", "--plain"],
        ]

        for arguments in cases {
            let state = PermissionState(accessibility: true, screenRecording: false)
            let output = OutputCapture()

            let exitCode = await WireRunner.run(
                arguments: arguments,
                environment: environment(state: state, output: output)
            )

            XCTAssertEqual(exitCode, 0)
            XCTAssertEqual(output.stdout, expected)
            XCTAssertEqual(output.stderr, "")
        }
    }

    func testVerboseLogsGoToStderrOnly() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["-v", "permissions", "status"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(output.stderr.contains("[verbose] checking accessibility permission"))
        XCTAssertTrue(output.stderr.contains("[verbose] checking screen-recording permission"))
        XCTAssertFalse(output.stdout.contains("[verbose]"))

        let response = try decode(StatusEnvelope.self, from: output.stdout)
        XCTAssertEqual(
            response.data.permissions,
            [
                .init(kind: "accessibility", granted: true),
                .init(kind: "screen-recording", granted: true),
            ]
        )
    }

    func testParseErrorsReturnStructuredJSON() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["permissions", "status", "--nope"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 64)
        XCTAssertEqual(output.stderr, "")

        let response = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.error.code, "parse_error")
        XCTAssertTrue(response.error.message.contains("--nope"))
    }

    func testParseErrorsIgnorePlainFlagAndReturnJSON() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["--plain", "permissions", "status", "--nope"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 64)
        XCTAssertEqual(output.stderr, "")

        let response = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.error.code, "parse_error")
        XCTAssertTrue(response.error.message.contains("--nope"))
    }
}
