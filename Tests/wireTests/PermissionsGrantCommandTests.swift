import XCTest
@testable import wire

final class PermissionsGrantCommandTests: WireCommandTestCase {
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
        XCTAssertEqual(
            response.data.permissions,
            [
                .init(kind: "accessibility", before: true, after: true, requested: false),
                .init(kind: "screen-recording", before: true, after: true, requested: false),
            ]
        )
    }
}
