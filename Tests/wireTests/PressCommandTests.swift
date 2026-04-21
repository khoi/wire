import Foundation
import XCTest
@testable import wire

final class PressCommandTests: WireCommandTestCase {
    func testPressHelpFlagExitsCleanly() async {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["press", "--help"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(output.stdout.contains("USAGE: wire press"))
        XCTAssertTrue(output.stdout.contains("EXAMPLES:"))
        XCTAssertTrue(output.stdout.contains("wire press cmd+l"))
        XCTAssertEqual(output.stderr, "")
    }

    func testPressWithoutInputPrintsHelp() async {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["press"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(output.stdout.contains("USAGE: wire press"))
        XCTAssertTrue(output.stdout.contains("EXAMPLES:"))
        XCTAssertEqual(output.stderr, "")
    }

    func testPressNamedKeySucceeds() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let pressState = PressState()

        let exitCode = await WireRunner.run(
            arguments: ["press", "enter"],
            environment: environment(
                state: state,
                output: output,
                press: pressState.makeClient()
            )
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(
            pressState.calls,
            [
                .init(
                    input: "enter",
                    normalized: "enter",
                    key: "enter",
                    modifiers: []
                ),
            ]
        )

        let response = try decode(PressEnvelope.self, from: output.stdout)
        XCTAssertEqual(
            response,
            .init(
                data: .init(
                    input: "enter",
                    normalized: "enter",
                    key: "enter",
                    modifiers: [],
                    pressed: true
                )
            )
        )
    }

    func testPressComboNormalizesModifiersAndPlainOutput() async {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let pressState = PressState()

        let exitCode = await WireRunner.run(
            arguments: ["--plain", "press", "command+SHIFT+l"],
            environment: environment(
                state: state,
                output: output,
                press: pressState.makeClient()
            )
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(
            pressState.calls,
            [
                .init(
                    input: "command+SHIFT+l",
                    normalized: "cmd+shift+l",
                    key: "l",
                    modifiers: ["cmd", "shift"]
                ),
            ]
        )
        XCTAssertEqual(output.stdout, "pressed cmd+shift+l\n")
    }

    func testPressRejectsMalformedCombo() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["press", "cmd++l"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 1)
        let response = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.error.code, "invalid_press_key")
    }

    func testPressRejectsModifierOnlyCombo() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["press", "cmd"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 1)
        let response = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.error.code, "invalid_press_key")
    }

    func testPressRejectsUnsupportedKey() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["press", "banana"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 1)
        let response = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.error.code, "invalid_press_key")
    }

    func testPressRequiresAccessibilityPermission() async throws {
        let state = PermissionState(accessibility: false, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["press", "enter"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 1)
        let response = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.error.code, "accessibility_permission_required")
    }

    func testPressMapsUnexpectedClientError() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let pressState = PressState()
        pressState.error = NSError(domain: "wire.test", code: 1)

        let exitCode = await WireRunner.run(
            arguments: ["press", "enter"],
            environment: environment(
                state: state,
                output: output,
                press: pressState.makeClient()
            )
        )

        XCTAssertEqual(exitCode, 1)
        let response = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.error.code, "press_action_failed")
    }
}
