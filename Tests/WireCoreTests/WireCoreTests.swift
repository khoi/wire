import XCTest
@testable import WireCore

final class WireCoreTests: XCTestCase {
    func testStatusReturnsJSON() throws {
        let state = PermissionState(accessibility: true, screenRecording: false)
        let output = OutputCapture()

        let exitCode = WireRunner.run(
            arguments: ["permissions", "status"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(output.stderr, "")

        let response = try decode(StatusEnvelope.self, from: output.stdout)
        XCTAssertTrue(response.ok)
        XCTAssertFalse(response.data.ready)
        XCTAssertEqual(
            response.data.permissions,
            [
                .init(kind: "accessibility", granted: true),
                .init(kind: "screen-recording", granted: false),
            ]
        )
    }

    func testStatusSupportsPlainFlagAtEveryCommandLevel() {
        let expected = "ready: no\naccessibility: granted\nscreen-recording: missing\n"
        let cases = [
            ["--plain", "permissions", "status"],
            ["permissions", "--plain", "status"],
            ["permissions", "status", "--plain"],
        ]

        for arguments in cases {
            let state = PermissionState(accessibility: true, screenRecording: false)
            let output = OutputCapture()

            let exitCode = WireRunner.run(
                arguments: arguments,
                environment: environment(state: state, output: output)
            )

            XCTAssertEqual(exitCode, 0)
            XCTAssertEqual(output.stdout, expected)
            XCTAssertEqual(output.stderr, "")
        }
    }

    func testGrantRequestsOnlyMissingPermissions() throws {
        let state = PermissionState(accessibility: false, screenRecording: true)
        state.grantAccessibilityOnRequest = true
        let output = OutputCapture()

        let exitCode = WireRunner.run(
            arguments: ["permissions", "grant"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(state.accessibilityRequests, 1)
        XCTAssertEqual(state.screenRecordingRequests, 0)

        let response = try decode(GrantEnvelope.self, from: output.stdout)
        XCTAssertTrue(response.ok)
        XCTAssertTrue(response.data.ready)
        XCTAssertEqual(
            response.data.permissions,
            [
                .init(kind: "accessibility", before: false, after: true, requested: true),
                .init(kind: "screen-recording", before: true, after: true, requested: false),
            ]
        )
    }

    func testGrantExitsNonZeroWhenPermissionRemainsMissing() throws {
        let state = PermissionState(accessibility: true, screenRecording: false)
        let output = OutputCapture()

        let exitCode = WireRunner.run(
            arguments: ["permissions", "grant"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 1)
        XCTAssertEqual(state.accessibilityRequests, 0)
        XCTAssertEqual(state.screenRecordingRequests, 1)

        let response = try decode(GrantEnvelope.self, from: output.stdout)
        XCTAssertTrue(response.ok)
        XCTAssertFalse(response.data.ready)
        XCTAssertEqual(
            response.data.permissions,
            [
                .init(kind: "accessibility", before: true, after: true, requested: false),
                .init(kind: "screen-recording", before: false, after: false, requested: true),
            ]
        )
    }

    func testGrantSkipsRequestsWhenEverythingIsAlreadyGranted() throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = WireRunner.run(
            arguments: ["permissions", "grant"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(state.accessibilityRequests, 0)
        XCTAssertEqual(state.screenRecordingRequests, 0)

        let response = try decode(GrantEnvelope.self, from: output.stdout)
        XCTAssertTrue(response.data.ready)
        XCTAssertEqual(
            response.data.permissions,
            [
                .init(kind: "accessibility", before: true, after: true, requested: false),
                .init(kind: "screen-recording", before: true, after: true, requested: false),
            ]
        )
    }

    func testVerboseLogsGoToStderrOnly() throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = WireRunner.run(
            arguments: ["-v", "permissions", "status"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(output.stderr.contains("[wire] checking accessibility permission"))
        XCTAssertTrue(output.stderr.contains("[wire] checking screen-recording permission"))
        XCTAssertFalse(output.stdout.contains("[wire]"))

        let response = try decode(StatusEnvelope.self, from: output.stdout)
        XCTAssertTrue(response.data.ready)
    }

    private func environment(state: PermissionState, output: OutputCapture) -> WireEnvironment {
        WireEnvironment(
            permissions: state.makeClient(),
            stdout: output.writeStdout,
            stderr: output.writeStderr
        )
    }

    private func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(string.utf8))
    }
}

private final class PermissionState: @unchecked Sendable {
    var accessibility: Bool
    var screenRecording: Bool
    var accessibilityRequests = 0
    var screenRecordingRequests = 0
    var grantAccessibilityOnRequest = false
    var grantScreenRecordingOnRequest = false

    init(accessibility: Bool, screenRecording: Bool) {
        self.accessibility = accessibility
        self.screenRecording = screenRecording
    }

    func makeClient() -> PermissionsClient {
        PermissionsClient(
            accessibilityStatus: {
                self.accessibility
            },
            accessibilityRequest: {
                self.accessibilityRequests += 1
                if self.grantAccessibilityOnRequest {
                    self.accessibility = true
                }
                return self.accessibility
            },
            screenRecordingStatus: {
                self.screenRecording
            },
            screenRecordingRequest: {
                self.screenRecordingRequests += 1
                if self.grantScreenRecordingOnRequest {
                    self.screenRecording = true
                }
                return self.screenRecording
            }
        )
    }
}

private final class OutputCapture {
    var stdout = ""
    var stderr = ""

    func writeStdout(_ text: String) {
        stdout += text
    }

    func writeStderr(_ text: String) {
        stderr += text
    }
}

private struct StatusEnvelope: Decodable, Equatable {
    let ok: Bool
    let data: StatusData
}

private struct StatusData: Decodable, Equatable {
    let ready: Bool
    let permissions: [StatusPermission]
}

private struct StatusPermission: Decodable, Equatable {
    let kind: String
    let granted: Bool
}

private struct GrantEnvelope: Decodable, Equatable {
    let ok: Bool
    let data: GrantData
}

private struct GrantData: Decodable, Equatable {
    let ready: Bool
    let permissions: [GrantPermission]
}

private struct GrantPermission: Decodable, Equatable {
    let kind: String
    let before: Bool
    let after: Bool
    let requested: Bool
}
