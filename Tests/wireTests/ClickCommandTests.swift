import Foundation
import XCTest
@testable import wire

final class ClickCommandTests: WireCommandTestCase {
    func testClickHelpFlagExitsCleanly() async {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["click", "--help"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(output.stdout.contains("USAGE: wire click"))
        XCTAssertTrue(output.stdout.contains("EXAMPLES:"))
        XCTAssertTrue(output.stdout.contains("wire click @e20 @e22 @e21 @e26 --snapshot s11"))
        XCTAssertTrue(output.stdout.contains("--snapshot"))
        XCTAssertTrue(output.stdout.contains("--right"))
        XCTAssertEqual(output.stderr, "")
    }

    func testClickWithoutTargetPrintsHelp() async {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["click"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(output.stdout.contains("USAGE: wire click"))
        XCTAssertTrue(output.stdout.contains("EXAMPLES:"))
        XCTAssertEqual(output.stderr, "")
    }

    func testClickUsesLatestSnapshotByDefault() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let clickState = ClickState()
        let stateDirectory = makeTemporaryDirectory()
        let store = SnapshotStore(
            stateDirectoryPath: stateDirectory.path,
            currentDirectoryPath: "/tmp/wire-tests"
        )

        _ = try store.store(capturedInspection())
        let second = try store.store(capturedInspection())
        let targetID = try XCTUnwrap(second.elements.first?.id)

        let exitCode = await WireRunner.run(
            arguments: ["click", targetID],
            environment: environment(
                state: state,
                output: output,
                click: clickState.makeClient(),
                stateDirectoryPath: stateDirectory.path
            )
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(
            clickState.calls,
            [.init(snapshot: "s2", elementID: targetID, right: false)]
        )

        let response = try decode(ClickEnvelope.self, from: output.stdout)
        XCTAssertEqual(
            response,
            .init(
                data: .init(
                    snapshot: "s2",
                    right: false,
                    clicks: [
                        .init(
                            target: targetID,
                            id: targetID,
                            role: "button",
                            name: "Continue",
                            clicked: true,
                            failure: nil
                        ),
                    ]
                )
            )
        )
    }

    func testClickSupportsExplicitSnapshotSelection() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let clickState = ClickState()
        let stateDirectory = makeTemporaryDirectory()
        let store = SnapshotStore(
            stateDirectoryPath: stateDirectory.path,
            currentDirectoryPath: "/tmp/wire-tests"
        )

        let first = try store.store(capturedInspection())
        _ = try store.store(capturedInspection(elements: [buttonElement(name: "Other", path: [0])]))
        let targetID = try XCTUnwrap(first.elements.first?.id)

        let exitCode = await WireRunner.run(
            arguments: ["click", targetID, "--snapshot", "s1"],
            environment: environment(
                state: state,
                output: output,
                click: clickState.makeClient(),
                stateDirectoryPath: stateDirectory.path
            )
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(
            clickState.calls,
            [.init(snapshot: "s1", elementID: targetID, right: false)]
        )
    }

    func testClickMatchesExactNameQuery() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let clickState = ClickState()
        let stateDirectory = makeTemporaryDirectory()
        let snapshot = try storeSnapshot(
            in: stateDirectory,
            inspection: capturedInspection(elements: [buttonElement(name: "Continue", path: [0])])
        )

        let exitCode = await WireRunner.run(
            arguments: ["click", "continue"],
            environment: environment(
                state: state,
                output: output,
                click: clickState.makeClient(),
                stateDirectoryPath: stateDirectory.path
            )
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(
            clickState.calls,
            [.init(snapshot: snapshot.snapshot, elementID: snapshot.elements[0].id, right: false)]
        )
    }

    func testClickMatchesRoleScopedQuery() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let clickState = ClickState()
        let stateDirectory = makeTemporaryDirectory()
        let snapshot = try storeSnapshot(
            in: stateDirectory,
            inspection: capturedInspection(elements: [
                textElement(name: "Continue", path: [0]),
                buttonElement(name: "Continue", path: [1]),
            ])
        )
        let button = try XCTUnwrap(snapshot.elements.first(where: { $0.role == "button" }))

        let exitCode = await WireRunner.run(
            arguments: ["click", "button:\"Continue\""],
            environment: environment(
                state: state,
                output: output,
                click: clickState.makeClient(),
                stateDirectoryPath: stateDirectory.path
            )
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(
            clickState.calls,
            [.init(snapshot: snapshot.snapshot, elementID: button.id, right: false)]
        )
    }

    func testClickPrefersPressableCandidateForPlainQuery() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let clickState = ClickState()
        let stateDirectory = makeTemporaryDirectory()
        let snapshot = try storeSnapshot(
            in: stateDirectory,
            inspection: capturedInspection(elements: [
                textElement(name: "Morning", path: [0]),
                buttonElement(name: "Morning", path: [1]),
            ])
        )
        let button = try XCTUnwrap(snapshot.elements.first(where: { $0.role == "button" }))

        let exitCode = await WireRunner.run(
            arguments: ["click", "Morning"],
            environment: environment(
                state: state,
                output: output,
                click: clickState.makeClient(),
                stateDirectoryPath: stateDirectory.path
            )
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(
            clickState.calls,
            [.init(snapshot: snapshot.snapshot, elementID: button.id, right: false)]
        )
    }

    func testClickQuerySkipsDisabledElements() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let clickState = ClickState()
        let stateDirectory = makeTemporaryDirectory()
        let snapshot = try storeSnapshot(
            in: stateDirectory,
            inspection: capturedInspection(elements: [
                buttonElement(name: "Continue", path: [0], enabled: false),
                buttonElement(name: "Continue", path: [1], enabled: true),
            ])
        )
        let enabledButton = try XCTUnwrap(
            snapshot.elements.first(where: { $0.name == "Continue" && $0.enabled == true })
        )

        let exitCode = await WireRunner.run(
            arguments: ["click", "Continue"],
            environment: environment(
                state: state,
                output: output,
                click: clickState.makeClient(),
                stateDirectoryPath: stateDirectory.path
            )
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(
            clickState.calls,
            [.init(snapshot: snapshot.snapshot, elementID: enabledButton.id, right: false)]
        )
    }

    func testClickReturnsBatchFailureForAmbiguousQuery() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let stateDirectory = makeTemporaryDirectory()
        _ = try storeSnapshot(
            in: stateDirectory,
            inspection: capturedInspection(elements: [
                buttonElement(name: "Continue", path: [0]),
                buttonElement(name: "Continue", path: [1]),
            ])
        )

        let exitCode = await WireRunner.run(
            arguments: ["click", "Continue"],
            environment: environment(
                state: state,
                output: output,
                stateDirectoryPath: stateDirectory.path
            )
        )

        XCTAssertEqual(exitCode, 1)
        let response = try decode(ClickEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.data.clicks.count, 1)
        XCTAssertFalse(response.data.clicks[0].clicked)
        XCTAssertEqual(response.data.clicks[0].failure?.code, "ambiguous_query")
    }

    func testClickReturnsNoSnapshotAvailableError() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let stateDirectory = makeTemporaryDirectory()

        let exitCode = await WireRunner.run(
            arguments: ["click", "@e1"],
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

    func testClickReturnsSnapshotNotFoundError() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let stateDirectory = makeTemporaryDirectory()
        _ = try storeSnapshot(in: stateDirectory, inspection: capturedInspection())

        let exitCode = await WireRunner.run(
            arguments: ["click", "@e1", "--snapshot", "s9"],
            environment: environment(
                state: state,
                output: output,
                stateDirectoryPath: stateDirectory.path
            )
        )

        XCTAssertEqual(exitCode, 1)
        let response = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.error.code, "snapshot_not_found")
    }

    func testClickRequiresAccessibilityPermission() async throws {
        let state = PermissionState(accessibility: false, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["click", "@e1"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 1)
        let response = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.error.code, "accessibility_permission_required")
    }

    func testRightClickUsesNamedElementWithGeometry() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let clickState = ClickState()
        let stateDirectory = makeTemporaryDirectory()
        let snapshot = try storeSnapshot(
            in: stateDirectory,
            inspection: capturedInspection(elements: [textElement(name: "Morning", path: [0])])
        )

        let exitCode = await WireRunner.run(
            arguments: ["--plain", "click", "Morning", "--right"],
            environment: environment(
                state: state,
                output: output,
                click: clickState.makeClient(),
                stateDirectoryPath: stateDirectory.path
            )
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(
            clickState.calls,
            [.init(snapshot: snapshot.snapshot, elementID: snapshot.elements[0].id, right: true)]
        )
        XCTAssertEqual(output.stdout, "right-clicked \(snapshot.elements[0].id) text Morning (\(snapshot.snapshot))\n")
    }

    func testClickReturnsBatchFailureForClientError() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let clickState = ClickState()
        clickState.clickError = ClickError.targetNotFrontmost("target app is not frontmost")
        let stateDirectory = makeTemporaryDirectory()
        let snapshot = try storeSnapshot(in: stateDirectory, inspection: capturedInspection())
        let targetID = try XCTUnwrap(snapshot.elements.first?.id)

        let exitCode = await WireRunner.run(
            arguments: ["click", targetID, "--right"],
            environment: environment(
                state: state,
                output: output,
                click: clickState.makeClient(),
                stateDirectoryPath: stateDirectory.path
            )
        )

        XCTAssertEqual(exitCode, 1)
        let response = try decode(ClickEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.data.clicks.count, 1)
        XCTAssertFalse(response.data.clicks[0].clicked)
        XCTAssertEqual(response.data.clicks[0].failure?.code, "target_not_frontmost")
    }

    func testClickSupportsMultipleTargetsAndMixedResults() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let clickState = ClickState()
        let stateDirectory = makeTemporaryDirectory()
        let snapshot = try storeSnapshot(
            in: stateDirectory,
            inspection: capturedInspection(elements: [buttonElement(name: "Continue", path: [0])])
        )
        let targetID = try XCTUnwrap(snapshot.elements.first?.id)

        let exitCode = await WireRunner.run(
            arguments: ["click", targetID, "@e99"],
            environment: environment(
                state: state,
                output: output,
                click: clickState.makeClient(),
                stateDirectoryPath: stateDirectory.path
            )
        )

        XCTAssertEqual(exitCode, 1)
        XCTAssertEqual(
            clickState.calls,
            [.init(snapshot: snapshot.snapshot, elementID: targetID, right: false)]
        )
        let response = try decode(ClickEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.data.clicks.count, 2)
        XCTAssertTrue(response.data.clicks[0].clicked)
        XCTAssertFalse(response.data.clicks[1].clicked)
        XCTAssertEqual(response.data.clicks[1].failure?.code, "element_not_found")
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
            elements: elements ?? [buttonElement(name: "Continue", path: [0])]
        )
    }

    private func buttonElement(
        name: String,
        path: [Int],
        enabled: Bool? = true
    ) -> CapturedInspection.Element {
        .init(
            role: "button",
            name: name,
            value: nil,
            enabled: enabled,
            screenFrame: CGRect(x: 120 + CGFloat(path.last ?? 0) * 20, y: 140, width: 80, height: 28),
            resolver: .init(
                appName: "Reminders",
                appBundleId: "com.apple.reminders",
                appPID: 42,
                windowID: 101,
                windowTitle: "Reminders",
                windowFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
                path: path,
                rawRole: "AXButton",
                rawSubrole: nil,
                rawTitle: name,
                rawDescription: nil,
                rawHelp: nil,
                rawValue: nil,
                screenFrame: CGRect(x: 120 + CGFloat(path.last ?? 0) * 20, y: 140, width: 80, height: 28),
                actions: ["AXPress"],
                valueSettable: false
            )
        )
    }

    private func textElement(
        name: String,
        path: [Int]
    ) -> CapturedInspection.Element {
        .init(
            role: "text",
            name: name,
            value: nil,
            enabled: nil,
            screenFrame: CGRect(x: 120 + CGFloat(path.last ?? 0) * 20, y: 180, width: 120, height: 18),
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
                screenFrame: CGRect(x: 120 + CGFloat(path.last ?? 0) * 20, y: 180, width: 120, height: 18),
                actions: [],
                valueSettable: false
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
