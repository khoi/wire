import XCTest
@testable import wire

final class AppQuitCommandTests: WireCommandTestCase {
    func testQuitHelpFlagExitsCleanly() async {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["app", "quit", "--help"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(output.stdout.contains("USAGE: wire app quit"))
        XCTAssertTrue(output.stdout.contains("EXAMPLES:"))
        XCTAssertTrue(output.stdout.contains("wire app quit \"Google Chrome\""))
        XCTAssertTrue(output.stdout.contains("wire app quit --pid 12345 --force"))
        XCTAssertTrue(output.stdout.contains("--pid"))
        XCTAssertTrue(output.stdout.contains("--force"))
        XCTAssertEqual(output.stderr, "")
    }

    func testQuitWithoutTargetPrintsHelp() async {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["app", "quit"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(output.stdout.contains("USAGE: wire app quit"))
        XCTAssertTrue(output.stdout.contains("EXAMPLES:"))
        XCTAssertTrue(output.stdout.contains("--pid"))
        XCTAssertEqual(output.stderr, "")
    }

    func testQuitByNameMatchesExactlyCaseInsensitive() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let apps = AppState()
        let chrome = StubRunningApplication(
            localizedName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            processIdentifier: 17,
            bundleURL: URL(fileURLWithPath: "/Applications/Google Chrome.app")
        )
        let canary = StubRunningApplication(
            localizedName: "Google Chrome Canary",
            bundleIdentifier: "com.google.Chrome.canary",
            processIdentifier: 18,
            bundleURL: URL(fileURLWithPath: "/Applications/Google Chrome Canary.app")
        )
        apps.runningApplications = [
            AppRuntimeApplication(handle: chrome),
            AppRuntimeApplication(handle: canary),
        ]
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["app", "quit", "google chrome"],
            environment: environment(state: state, output: output, apps: apps.makeClient())
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(chrome.terminateCalls, 1)
        XCTAssertEqual(chrome.forceTerminateCalls, 0)
        XCTAssertEqual(canary.terminateCalls, 0)

        let response = try decode(AppQuitEnvelope.self, from: output.stdout)
        XCTAssertEqual(
            response,
            .init(
                data: .init(
                    apps: [
                        .init(
                            name: "Google Chrome",
                            bundleId: "com.google.Chrome",
                            path: "/Applications/Google Chrome.app",
                            pid: 17,
                            terminated: true,
                            message: nil
                        ),
                    ],
                    forced: false
                )
            )
        )
    }

    func testQuitByPIDReturnsJSON() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let apps = AppState()
        let notes = StubRunningApplication(
            localizedName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            processIdentifier: 23,
            bundleURL: URL(fileURLWithPath: "/Applications/Notes.app")
        )
        apps.runningApplications = [AppRuntimeApplication(handle: notes)]
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["app", "quit", "--pid", "23"],
            environment: environment(state: state, output: output, apps: apps.makeClient())
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(notes.terminateCalls, 1)

        let response = try decode(AppQuitEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.data.apps.count, 1)
        XCTAssertEqual(response.data.apps.first?.pid, 23)
        XCTAssertFalse(response.data.forced)
    }

    func testQuitForceFlagTerminatesAllSameNameMatches() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let apps = AppState()
        let helperOne = StubRunningApplication(
            localizedName: "Helper",
            bundleIdentifier: "com.example.helper1",
            processIdentifier: 41,
            bundleURL: URL(fileURLWithPath: "/Applications/Helper 1.app")
        )
        let helperTwo = StubRunningApplication(
            localizedName: "Helper",
            bundleIdentifier: "com.example.helper2",
            processIdentifier: 42,
            bundleURL: URL(fileURLWithPath: "/Applications/Helper 2.app")
        )
        apps.runningApplications = [
            AppRuntimeApplication(handle: helperTwo),
            AppRuntimeApplication(handle: helperOne),
        ]
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["app", "quit", "Helper", "--force"],
            environment: environment(state: state, output: output, apps: apps.makeClient())
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(helperOne.terminateCalls, 0)
        XCTAssertEqual(helperTwo.terminateCalls, 0)
        XCTAssertEqual(helperOne.forceTerminateCalls, 1)
        XCTAssertEqual(helperTwo.forceTerminateCalls, 1)

        let response = try decode(AppQuitEnvelope.self, from: output.stdout)
        XCTAssertEqual(
            response,
            .init(
                data: .init(
                    apps: [
                        .init(
                            name: "Helper",
                            bundleId: "com.example.helper1",
                            path: "/Applications/Helper 1.app",
                            pid: 41,
                            terminated: true,
                            message: nil
                        ),
                        .init(
                            name: "Helper",
                            bundleId: "com.example.helper2",
                            path: "/Applications/Helper 2.app",
                            pid: 42,
                            terminated: true,
                            message: nil
                        ),
                    ],
                    forced: true
                )
            )
        )
    }

    func testQuitReturnsStructuredErrorWhenAppIsNotRunning() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let apps = AppState()
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["app", "quit", "Safari"],
            environment: environment(state: state, output: output, apps: apps.makeClient())
        )

        XCTAssertEqual(exitCode, 1)
        let response = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.error.code, "app_not_running")
    }

    func testQuitValidatesTargetSelection() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["app", "quit", "Safari", "--pid", "17"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 1)
        let response = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.error.code, "invalid_app_target")
    }

    func testQuitMixedResultsReturnPayloadAndNonZeroExit() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let apps = AppState()
        let fast = StubRunningApplication(
            localizedName: "Safari",
            bundleIdentifier: "com.apple.Safari.one",
            processIdentifier: 61,
            bundleURL: URL(fileURLWithPath: "/Applications/Safari One.app")
        )
        let slow = StubRunningApplication(
            localizedName: "Safari",
            bundleIdentifier: "com.apple.Safari.two",
            processIdentifier: 62,
            bundleURL: URL(fileURLWithPath: "/Applications/Safari Two.app")
        )
        slow.terminateAfterChecks = 200
        apps.runningApplications = [
            AppRuntimeApplication(handle: slow),
            AppRuntimeApplication(handle: fast),
        ]
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["app", "quit", "Safari"],
            environment: environment(state: state, output: output, apps: apps.makeClient())
        )

        XCTAssertEqual(exitCode, 1)
        let response = try decode(AppQuitEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.data.forced, false)
        XCTAssertEqual(
            response.data.apps,
            [
                .init(
                    name: "Safari",
                    bundleId: "com.apple.Safari.one",
                    path: "/Applications/Safari One.app",
                    pid: 61,
                    terminated: true,
                    message: nil
                ),
                .init(
                    name: "Safari",
                    bundleId: "com.apple.Safari.two",
                    path: "/Applications/Safari Two.app",
                    pid: 62,
                    terminated: false,
                    message: "application did not quit within 10 seconds"
                ),
            ]
        )
    }

    func testQuitSupportsPlainFlagAtEveryCommandLevel() async {
        let expected = "Safari\tcom.apple.Safari\t17\t/Applications/Safari.app\tquit\n"
        let cases = [
            ["--plain", "app", "quit", "Safari"],
            ["app", "--plain", "quit", "Safari"],
            ["app", "quit", "--plain", "Safari"],
        ]

        for arguments in cases {
            let state = PermissionState(accessibility: true, screenRecording: true)
            let apps = AppState()
            apps.runningApplications = [
                AppRuntimeApplication(
                    handle: StubRunningApplication(
                        localizedName: "Safari",
                        bundleIdentifier: "com.apple.Safari",
                        processIdentifier: 17,
                        bundleURL: URL(fileURLWithPath: "/Applications/Safari.app")
                    )
                ),
            ]
            let output = OutputCapture()

            let exitCode = await WireRunner.run(
                arguments: arguments,
                environment: environment(state: state, output: output, apps: apps.makeClient())
            )

            XCTAssertEqual(exitCode, 0)
            XCTAssertEqual(output.stdout, expected)
            XCTAssertEqual(output.stderr, "")
        }
    }
}
