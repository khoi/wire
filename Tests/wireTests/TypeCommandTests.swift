import Foundation
import XCTest
@testable import wire

final class TypeCommandTests: WireCommandTestCase {
    func testTypeHelpFlagExitsCleanly() async {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["type", "--help"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(output.stdout.contains("USAGE: wire type"))
        XCTAssertTrue(output.stdout.contains("EXAMPLES:"))
        XCTAssertTrue(output.stdout.contains("--into"))
        XCTAssertEqual(output.stderr, "")
    }

    func testTypeWithoutTextPrintsHelp() async {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["type"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(output.stdout.contains("USAGE: wire type"))
        XCTAssertTrue(output.stdout.contains("EXAMPLES:"))
        XCTAssertEqual(output.stderr, "")
    }

    func testTypeTypesFocusedTextWhenIntoIsMissing() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let typeState = TypeState()

        let exitCode = await WireRunner.run(
            arguments: ["type", "hello"],
            environment: environment(
                state: state,
                output: output,
                type: typeState.makeClient()
            )
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(typeState.focusedCalls, [.init(text: "hello")])
        XCTAssertTrue(typeState.elementCalls.isEmpty)

        let response = try decode(TypeEnvelope.self, from: output.stdout)
        XCTAssertEqual(
            response,
            .init(
                snapshot: nil,
                data: .init(
                    text: "hello",
                    into: nil,
                    target: nil,
                    typed: true
                )
            )
        )
    }

    func testTypeIntoUsesLatestSnapshotByDefault() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let typeState = TypeState()
        let stateDirectory = makeTemporaryDirectory()
        let store = SnapshotStore(
            stateDirectoryPath: stateDirectory.path,
            currentDirectoryPath: "/tmp/wire-tests"
        )

        _ = try store.store(capturedInspection(elements: [textFieldElement(name: "First", path: [0])]))
        let second = try store.store(capturedInspection(elements: [textFieldElement(name: "Second", path: [0])]))
        let targetID = try XCTUnwrap(second.elements.first?.id)

        let exitCode = await WireRunner.run(
            arguments: ["type", "hello", "--into", targetID],
            environment: environment(
                state: state,
                output: output,
                type: typeState.makeClient(),
                stateDirectoryPath: stateDirectory.path
            )
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(typeState.focusedCalls.isEmpty)
        XCTAssertEqual(
            typeState.elementCalls,
            [.init(elementID: targetID, text: "hello")]
        )

        let response = try decode(TypeEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.snapshot, "s2")
        XCTAssertEqual(response.data.text, "hello")
        XCTAssertEqual(response.data.into, targetID)
        XCTAssertEqual(response.data.target?.id, targetID)
    }

    func testTypeIntoMatchesRoleScopedQuery() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let typeState = TypeState()
        let stateDirectory = makeTemporaryDirectory()
        let snapshot = try storeSnapshot(
            in: stateDirectory,
            inspection: capturedInspection(elements: [
                textElement(name: "Title", path: [0]),
                textFieldElement(name: "Title", path: [1]),
            ])
        )
        let target = try XCTUnwrap(snapshot.elements.first(where: { $0.role == "text-field" }))

        let exitCode = await WireRunner.run(
            arguments: ["type", "hello", "--into", "text-field:\"Title\""],
            environment: environment(
                state: state,
                output: output,
                type: typeState.makeClient(),
                stateDirectoryPath: stateDirectory.path
            )
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(
            typeState.elementCalls,
            [.init(elementID: target.id, text: "hello")]
        )
    }

    func testTypeRequiresAccessibilityPermission() async throws {
        let state = PermissionState(accessibility: false, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["type", "hello"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 1)
        let response = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.error.code, "accessibility_permission_required")
    }

    func testTypeIntoReturnsNoSnapshotAvailableError() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let stateDirectory = makeTemporaryDirectory()

        let exitCode = await WireRunner.run(
            arguments: ["type", "hello", "--into", "@e1"],
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

    func testTypeIntoReturnsAmbiguousQuery() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let stateDirectory = makeTemporaryDirectory()
        _ = try storeSnapshot(
            in: stateDirectory,
            inspection: capturedInspection(elements: [
                textFieldElement(name: "Title", path: [0]),
                textFieldElement(name: "Title", path: [1]),
            ])
        )

        let exitCode = await WireRunner.run(
            arguments: ["type", "hello", "--into", "Title"],
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

    func testTypeIntoReturnsElementNotTypeableForDisabledElement() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let stateDirectory = makeTemporaryDirectory()
        let snapshot = try storeSnapshot(
            in: stateDirectory,
            inspection: capturedInspection(elements: [
                textFieldElement(name: "Title", path: [0], enabled: false),
            ])
        )
        let targetID = try XCTUnwrap(snapshot.elements.first?.id)

        let exitCode = await WireRunner.run(
            arguments: ["type", "hello", "--into", targetID],
            environment: environment(
                state: state,
                output: output,
                stateDirectoryPath: stateDirectory.path
            )
        )

        XCTAssertEqual(exitCode, 1)
        let response = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.error.code, "element_not_typeable")
    }

    func testTypeIntoReturnsElementNotTypeableForNonSettableElement() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let stateDirectory = makeTemporaryDirectory()
        let snapshot = try storeSnapshot(
            in: stateDirectory,
            inspection: capturedInspection(elements: [
                textFieldElement(name: "Title", path: [0], valueSettable: false),
            ])
        )
        let targetID = try XCTUnwrap(snapshot.elements.first?.id)

        let exitCode = await WireRunner.run(
            arguments: ["type", "hello", "--into", targetID],
            environment: environment(
                state: state,
                output: output,
                stateDirectoryPath: stateDirectory.path
            )
        )

        XCTAssertEqual(exitCode, 1)
        let response = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.error.code, "element_not_typeable")
    }

    func testTypeIntoReturnsStaleRefWhenClientReportsStaleRef() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let typeState = TypeState()
        typeState.elementError = TypeError.staleRef("@e1 is no longer valid")
        let stateDirectory = makeTemporaryDirectory()
        let snapshot = try storeSnapshot(
            in: stateDirectory,
            inspection: capturedInspection(elements: [textFieldElement(name: "Title", path: [0])])
        )
        let targetID = try XCTUnwrap(snapshot.elements.first?.id)

        let exitCode = await WireRunner.run(
            arguments: ["type", "hello", "--into", targetID],
            environment: environment(
                state: state,
                output: output,
                type: typeState.makeClient(),
                stateDirectoryPath: stateDirectory.path
            )
        )

        XCTAssertEqual(exitCode, 1)
        let response = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.error.code, "stale_ref")
    }

    func testTypeIntoReturnsTypeActionFailedForUnexpectedClientError() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()
        let typeState = TypeState()
        typeState.elementError = NSError(domain: "wire.test", code: 1)
        let stateDirectory = makeTemporaryDirectory()
        let snapshot = try storeSnapshot(
            in: stateDirectory,
            inspection: capturedInspection(elements: [textFieldElement(name: "Title", path: [0])])
        )
        let targetID = try XCTUnwrap(snapshot.elements.first?.id)

        let exitCode = await WireRunner.run(
            arguments: ["type", "hello", "--into", targetID],
            environment: environment(
                state: state,
                output: output,
                type: typeState.makeClient(),
                stateDirectoryPath: stateDirectory.path
            )
        )

        XCTAssertEqual(exitCode, 1)
        let response = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.error.code, "type_action_failed")
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
            elements: elements ?? [textFieldElement(name: "Title", path: [0])]
        )
    }

    private func textFieldElement(
        name: String,
        path: [Int],
        enabled: Bool? = true,
        valueSettable: Bool = true
    ) -> CapturedInspection.Element {
        .init(
            role: "text-field",
            name: name,
            value: nil,
            enabled: enabled,
            screenFrame: CGRect(x: 120 + CGFloat(path.last ?? 0) * 20, y: 140, width: 220, height: 28),
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
                screenFrame: CGRect(x: 120 + CGFloat(path.last ?? 0) * 20, y: 140, width: 220, height: 28),
                actions: [],
                valueSettable: valueSettable
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
            enabled: true,
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
