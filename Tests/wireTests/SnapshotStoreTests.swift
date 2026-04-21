import Foundation
import XCTest
@testable import wire

final class SnapshotStoreTests: XCTestCase {
    func testStoreAssignsSnapshotIDsAndTracksLatest() throws {
        let stateDirectory = makeTemporaryDirectory()
        var now = Date(timeIntervalSince1970: 1_000)
        let store = SnapshotStore(
            stateDirectoryPath: stateDirectory.path,
            currentDirectoryPath: "/tmp/project",
            now: { now }
        )

        let first = try store.store(capturedInspection())
        now = Date(timeIntervalSince1970: 1_001)
        let second = try store.store(capturedInspection())

        XCTAssertEqual(first.snapshot, "s1")
        XCTAssertEqual(second.snapshot, "s2")
        XCTAssertEqual(try store.latestSnapshotID(), "s2")
        XCTAssertEqual(try store.load(snapshotID: "s2")?.snapshot, "s2")
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.imagePath))
    }

    func testStoreBucketsSnapshotsByWorkingDirectory() throws {
        let stateDirectory = makeTemporaryDirectory()
        let firstStore = SnapshotStore(
            stateDirectoryPath: stateDirectory.path,
            currentDirectoryPath: "/tmp/project-a"
        )
        let secondStore = SnapshotStore(
            stateDirectoryPath: stateDirectory.path,
            currentDirectoryPath: "/tmp/project-b"
        )

        let first = try firstStore.store(capturedInspection())
        let second = try secondStore.store(capturedInspection())

        XCTAssertEqual(first.snapshot, "s1")
        XCTAssertEqual(second.snapshot, "s1")
        XCTAssertNotEqual(
            URL(fileURLWithPath: first.imagePath).deletingLastPathComponent().deletingLastPathComponent().path,
            URL(fileURLWithPath: second.imagePath).deletingLastPathComponent().deletingLastPathComponent().path
        )
    }

    func testStoreEnforcesRetentionCount() throws {
        let stateDirectory = makeTemporaryDirectory()
        var now = Date(timeIntervalSince1970: 1_000)
        let store = SnapshotStore(
            stateDirectoryPath: stateDirectory.path,
            currentDirectoryPath: "/tmp/project",
            now: { now },
            retentionCount: 2,
            ttl: 10_000
        )

        _ = try store.store(capturedInspection())
        now = Date(timeIntervalSince1970: 1_001)
        _ = try store.store(capturedInspection())
        now = Date(timeIntervalSince1970: 1_002)
        let third = try store.store(capturedInspection())

        XCTAssertNil(try store.load(snapshotID: "s1"))
        XCTAssertEqual(try store.latestSnapshotID(), third.snapshot)
        XCTAssertEqual(try store.load(snapshotID: "s2")?.snapshot, "s2")
        XCTAssertEqual(try store.load(snapshotID: "s3")?.snapshot, "s3")
    }

    func testStoreExpiresSnapshotsByTTL() throws {
        let stateDirectory = makeTemporaryDirectory()
        var now = Date(timeIntervalSince1970: 1_000)
        let store = SnapshotStore(
            stateDirectoryPath: stateDirectory.path,
            currentDirectoryPath: "/tmp/project",
            now: { now },
            retentionCount: 5,
            ttl: 60
        )

        _ = try store.store(capturedInspection())
        now = Date(timeIntervalSince1970: 1_030)
        let second = try store.store(capturedInspection())
        now = Date(timeIntervalSince1970: 1_061)

        XCTAssertNil(try store.load(snapshotID: "s1"))
        XCTAssertEqual(try store.latestSnapshotID(), second.snapshot)
    }

    func testStoreMarksDisabledPressableElementAsNotClickable() throws {
        let stateDirectory = makeTemporaryDirectory()
        let store = SnapshotStore(
            stateDirectoryPath: stateDirectory.path,
            currentDirectoryPath: "/tmp/project"
        )

        let snapshot = try store.store(capturedInspection(enabled: false))
        XCTAssertEqual(snapshot.elements.count, 1)
        XCTAssertFalse(snapshot.elements[0].clickable)
        XCTAssertEqual(snapshot.elements[0].enabled, false)
    }

    private func capturedInspection(
        enabled: Bool? = true,
        actions: [String] = ["AXPress"]
    ) -> CapturedInspection {
        CapturedInspection(
            app: .init(
                name: "Google Chrome",
                bundleId: "com.google.Chrome",
                pid: 42,
                focused: false
            ),
            window: .init(
                id: 101,
                title: "Search",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600)
            ),
            imageData: Data("image".utf8),
            elements: [
                .init(
                    role: "text-field",
                    name: "Search",
                    value: nil,
                    enabled: enabled,
                    screenFrame: CGRect(x: 120, y: 620, width: 320, height: 28),
                    resolver: .init(
                        appName: "Google Chrome",
                        appBundleId: "com.google.Chrome",
                        appPID: 42,
                        windowID: 101,
                        windowTitle: "Search",
                        windowFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
                        path: [0],
                        rawRole: "AXTextField",
                        rawSubrole: nil,
                        rawTitle: "Search",
                        rawDescription: nil,
                        rawHelp: nil,
                        rawValue: nil,
                        screenFrame: CGRect(x: 120, y: 620, width: 320, height: 28),
                        actions: actions,
                        valueSettable: true
                    )
                )
            ]
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
