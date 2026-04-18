import Foundation
import XCTest
@testable import wire

final class InspectCommandTests: WireCommandTestCase {
    func testInspectCommandCapturesFrontmostApplication() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let inspectState = InspectState()
        let stateDirectory = makeTemporaryDirectory()

        let exitCode = await WireRunner.run(
            arguments: ["inspect"],
            environment: environment(
                state: state,
                output: output,
                inspect: inspectState.makeClient(),
                stateDirectoryPath: stateDirectory.path
            )
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(inspectState.captureCalls, [.frontmost])

        let envelope = try decode(InspectEnvelope.self, from: output.stdout)
        XCTAssertEqual(envelope.snapshot, "s1")
        XCTAssertEqual(envelope.data.app.name, "Google Chrome")
        XCTAssertEqual(envelope.data.app.bundleId, "com.google.Chrome")
        XCTAssertEqual(envelope.data.app.pid, 42)
        XCTAssertEqual(envelope.data.elements, [
            InspectItem(
                id: "@e1",
                role: "text-field",
                name: "Search",
                value: nil,
                enabled: true,
                frame: CGRect(x: 20, y: 52, width: 320, height: 28)
            )
        ])
        XCTAssertTrue(FileManager.default.fileExists(atPath: envelope.data.imagePath))
        XCTAssertEqual(output.stderr, "")
    }

    func testInspectCommandUsesNamedApplicationTarget() async {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let inspectState = InspectState()

        let exitCode = await WireRunner.run(
            arguments: ["--plain", "inspect", "--app", "Google Chrome"],
            environment: environment(
                state: state,
                output: output,
                inspect: inspectState.makeClient(),
                stateDirectoryPath: makeTemporaryDirectory().path
            )
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(inspectState.captureCalls, [.app("Google Chrome")])
        XCTAssertTrue(output.stdout.contains("snapshot: s1"))
        XCTAssertTrue(output.stdout.contains("@e1\ttext-field\tSearch"))
        XCTAssertEqual(output.stderr, "")
    }

    func testInspectCommandRequiresAccessibilityPermission() async throws {
        let state = PermissionState(accessibility: false, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["inspect"],
            environment: environment(
                state: state,
                output: output,
                stateDirectoryPath: makeTemporaryDirectory().path
            )
        )

        XCTAssertEqual(exitCode, 1)
        let envelope = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(envelope.error.code, "accessibility_permission_required")
    }

    func testInspectCommandRequiresScreenRecordingPermission() async throws {
        let state = PermissionState(accessibility: true, screenRecording: false)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["inspect"],
            environment: environment(
                state: state,
                output: output,
                stateDirectoryPath: makeTemporaryDirectory().path
            )
        )

        XCTAssertEqual(exitCode, 1)
        let envelope = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(envelope.error.code, "screen_recording_permission_required")
    }

    func testInspectHelpFlagExitsCleanly() async {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["inspect", "--help"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(output.stdout.contains("USAGE: wire inspect"))
        XCTAssertTrue(output.stdout.contains("EXAMPLES:"))
        XCTAssertTrue(output.stdout.contains("wire inspect --app"))
        XCTAssertEqual(output.stderr, "")
    }

    func testInspectRejectsEmptyApplicationName() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["inspect", "--app", "   "],
            environment: environment(
                state: state,
                output: output,
                stateDirectoryPath: makeTemporaryDirectory().path
            )
        )

        XCTAssertEqual(exitCode, 1)
        let envelope = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(envelope.error.code, "invalid_app_target")
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
