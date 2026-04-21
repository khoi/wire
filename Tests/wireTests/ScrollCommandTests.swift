import Foundation
import XCTest
@testable import wire

final class ScrollCommandTests: WireCommandTestCase {
    func testScrollHelpFlagExitsCleanly() async {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["scroll", "--help"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(output.stdout.contains("USAGE: wire scroll"))
        XCTAssertTrue(output.stdout.contains("--up"))
        XCTAssertTrue(output.stdout.contains("--down"))
        XCTAssertTrue(output.stdout.contains("EXAMPLES:"))
        XCTAssertEqual(output.stderr, "")
    }

    func testScrollWithoutDirectionReturnsInvalidAmount() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["scroll"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 1)
        let response = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.error.code, "invalid_scroll_amount")
    }

    func testScrollWithBothDirectionsReturnsInvalidAmount() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["scroll", "--up", "1", "--down", "1"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 1)
        let response = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.error.code, "invalid_scroll_amount")
    }

    func testScrollWithNonPositiveAmountReturnsInvalidAmount() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["scroll", "--up", "0"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 1)
        let response = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.error.code, "invalid_scroll_amount")
    }

    func testScrollRequiresAccessibilityPermission() async throws {
        let state = PermissionState(accessibility: false, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["scroll", "--down", "2"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 1)
        let response = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.error.code, "accessibility_permission_required")
    }

    func testScrollWithoutTargetUsesFocusedArea() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let scrollState = ScrollState()

        let exitCode = await WireRunner.run(
            arguments: ["scroll", "--down", "3"],
            environment: environment(
                state: state,
                output: output,
                scroll: scrollState.makeClient()
            )
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(
            scrollState.focusedCalls,
            [
                .init(
                    direction: .down,
                    amount: 3
                ),
            ]
        )
        XCTAssertTrue(scrollState.elementCalls.isEmpty)

        let response = try decode(ScrollEnvelope.self, from: output.stdout)
        XCTAssertNil(response.snapshot)
        XCTAssertEqual(response.data.direction, "down")
        XCTAssertEqual(response.data.amount, 3)
        XCTAssertNil(response.data.on)
        XCTAssertNil(response.data.target)
        XCTAssertTrue(response.data.scrolled)
    }

    func testScrollWithTargetUsesLatestSnapshotByDefault() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let scrollState = ScrollState()
        let stateDirectory = makeTemporaryDirectory()
        let store = SnapshotStore(
            stateDirectoryPath: stateDirectory.path,
            currentDirectoryPath: "/tmp/wire-tests"
        )

        _ = try store.store(capturedInspection(elements: [textElement(name: "First", path: [0])]))
        let second = try store.store(capturedInspection(elements: [textElement(name: "Second", path: [0])]))
        let targetID = try XCTUnwrap(second.elements.first?.id)

        let exitCode = await WireRunner.run(
            arguments: ["scroll", targetID, "--up", "4"],
            environment: environment(
                state: state,
                output: output,
                scroll: scrollState.makeClient(),
                stateDirectoryPath: stateDirectory.path
            )
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(
            scrollState.elementCalls,
            [
                .init(
                    elementID: targetID,
                    direction: .up,
                    amount: 4
                ),
            ]
        )

        let response = try decode(ScrollEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.snapshot, "s2")
        XCTAssertEqual(response.data.direction, "up")
        XCTAssertEqual(response.data.amount, 4)
        XCTAssertEqual(response.data.on, targetID)
        XCTAssertEqual(response.data.target?.id, targetID)
        XCTAssertTrue(response.data.scrolled)
    }

    func testScrollWithTargetMatchesQuery() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let scrollState = ScrollState()
        let stateDirectory = makeTemporaryDirectory()
        let snapshot = try storeSnapshot(
            in: stateDirectory,
            inspection: capturedInspection(elements: [
                textElement(name: "Reminders", path: [0]),
            ])
        )
        let target = try XCTUnwrap(snapshot.elements.first)

        let exitCode = await WireRunner.run(
            arguments: ["scroll", "Reminders", "--down", "2"],
            environment: environment(
                state: state,
                output: output,
                scroll: scrollState.makeClient(),
                stateDirectoryPath: stateDirectory.path
            )
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(
            scrollState.elementCalls,
            [
                .init(
                    elementID: target.id,
                    direction: .down,
                    amount: 2
                ),
            ]
        )
    }

    func testScrollWithTargetMatchesRoleScopedQuery() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let scrollState = ScrollState()
        let stateDirectory = makeTemporaryDirectory()
        let snapshot = try storeSnapshot(
            in: stateDirectory,
            inspection: capturedInspection(elements: [
                textElement(name: "Notes", path: [0]),
                textFieldElement(name: "Notes", path: [1]),
            ])
        )
        let target = try XCTUnwrap(snapshot.elements.first(where: { $0.role == "text" }))

        let exitCode = await WireRunner.run(
            arguments: ["scroll", "text:\"Notes\"", "--down", "1"],
            environment: environment(
                state: state,
                output: output,
                scroll: scrollState.makeClient(),
                stateDirectoryPath: stateDirectory.path
            )
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(
            scrollState.elementCalls,
            [
                .init(
                    elementID: target.id,
                    direction: .down,
                    amount: 1
                ),
            ]
        )
    }

    func testScrollWithTargetReturnsNoSnapshotAvailableError() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let stateDirectory = makeTemporaryDirectory()

        let exitCode = await WireRunner.run(
            arguments: ["scroll", "@e1", "--up", "1"],
            environment: environment(
                state: state,
                output: output,
                stateDirectoryPath: stateDirectory.path
            )
        )

        XCTAssertEqual(exitCode, 1)
        let response = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.error.code, "no_snapshot_available")
    }

    func testScrollWithTargetReturnsAmbiguousQuery() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let stateDirectory = makeTemporaryDirectory()
        _ = try storeSnapshot(
            in: stateDirectory,
            inspection: capturedInspection(elements: [
                textElement(name: "Reminders", path: [0]),
                textElement(name: "Reminders", path: [1]),
            ])
        )

        let exitCode = await WireRunner.run(
            arguments: ["scroll", "Reminders", "--down", "1"],
            environment: environment(
                state: state,
                output: output,
                stateDirectoryPath: stateDirectory.path
            )
        )

        XCTAssertEqual(exitCode, 1)
        let response = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.error.code, "ambiguous_query")
    }

    func testScrollWithTargetReturnsClientError() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let scrollState = ScrollState()
        scrollState.elementError = ScrollError.scrollActionFailed("failed to scroll target")
        let stateDirectory = makeTemporaryDirectory()
        let snapshot = try storeSnapshot(
            in: stateDirectory,
            inspection: capturedInspection(elements: [textElement(name: "Reminders", path: [0])])
        )
        let targetID = try XCTUnwrap(snapshot.elements.first?.id)

        let exitCode = await WireRunner.run(
            arguments: ["scroll", targetID, "--up", "1"],
            environment: environment(
                state: state,
                output: output,
                scroll: scrollState.makeClient(),
                stateDirectoryPath: stateDirectory.path
            )
        )

        XCTAssertEqual(exitCode, 1)
        let response = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.error.code, "scroll_action_failed")
    }

    func testScrollWithTargetReturnsStaleRefError() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let scrollState = ScrollState()
        scrollState.elementError = ScrollError.staleRef("@e1 is no longer valid")
        let stateDirectory = makeTemporaryDirectory()
        let snapshot = try storeSnapshot(
            in: stateDirectory,
            inspection: capturedInspection(elements: [textElement(name: "Reminders", path: [0])])
        )
        let targetID = try XCTUnwrap(snapshot.elements.first?.id)

        let exitCode = await WireRunner.run(
            arguments: ["scroll", targetID, "--up", "1"],
            environment: environment(
                state: state,
                output: output,
                scroll: scrollState.makeClient(),
                stateDirectoryPath: stateDirectory.path
            )
        )

        XCTAssertEqual(exitCode, 1)
        let response = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.error.code, "stale_ref")
    }

    private func storeSnapshot(
        in stateDirectory: URL,
        inspection: CapturedInspection
    ) throws -> StoredInspectSnapshot {
        let store = SnapshotStore(
            stateDirectoryPath: stateDirectory.path,
            currentDirectoryPath: "/tmp/wire-tests"
        )
        return try store.store(inspection)
    }

    private func capturedInspection(
        elements: [CapturedInspection.Element]? = nil
    ) -> CapturedInspection {
        CapturedInspection(
            app: .init(
                name: "Reminders",
                bundleId: "com.apple.reminders",
                pid: 42,
                focused: false
            ),
            window: .init(
                id: 101,
                title: "Reminders",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600)
            ),
            imageData: Data("image".utf8),
            elements: elements ?? [textElement(name: "Reminders", path: [0])]
        )
    }

    private func textElement(
        name: String,
        path: [Int],
        enabled: Bool? = true
    ) -> CapturedInspection.Element {
        let frame = CGRect(
            x: 120 + CGFloat(path.last ?? 0) * 20,
            y: 180,
            width: 120,
            height: 18
        )
        return .init(
            role: "text",
            name: name,
            value: nil,
            enabled: enabled,
            screenFrame: frame,
            resolver: .init(
                appName: "Reminders",
                appBundleId: "com.apple.reminders",
                appPID: 42,
                windowID: 101,
                windowTitle: "Reminders",
                windowFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
                path: path,
                rawRole: "AXStaticText",
                rawSubrole: nil,
                rawTitle: name,
                rawDescription: nil,
                rawHelp: nil,
                rawValue: nil,
                screenFrame: frame,
                actions: [],
                valueSettable: false
            )
        )
    }

    private func textFieldElement(
        name: String,
        path: [Int]
    ) -> CapturedInspection.Element {
        let frame = CGRect(
            x: 120 + CGFloat(path.last ?? 0) * 20,
            y: 220,
            width: 180,
            height: 26
        )
        return .init(
            role: "text-field",
            name: name,
            value: nil,
            enabled: true,
            screenFrame: frame,
            resolver: .init(
                appName: "Reminders",
                appBundleId: "com.apple.reminders",
                appPID: 42,
                windowID: 101,
                windowTitle: "Reminders",
                windowFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
                path: path,
                rawRole: "AXTextField",
                rawSubrole: nil,
                rawTitle: name,
                rawDescription: nil,
                rawHelp: nil,
                rawValue: nil,
                screenFrame: frame,
                actions: [],
                valueSettable: true
            )
        )
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
