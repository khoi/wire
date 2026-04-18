import XCTest
@testable import wire

final class AppLaunchCommandTests: WireCommandTestCase {
    func testLaunchByAppReturnsJSONWithoutFocusByDefault() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let apps = AppState()
        apps.namedApplications["Safari"] = URL(fileURLWithPath: "/Applications/Safari.app")
        apps.launchedApplications = [
            StubRunningApplication(
                localizedName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                processIdentifier: 17,
                readyAfterChecks: 1
            )
        ]
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["app", "launch", "Safari"],
            environment: environment(state: state, output: output, apps: apps.makeClient())
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(output.stderr, "")
        XCTAssertEqual(
            apps.launchCalls,
            [
                .init(
                    appURL: URL(fileURLWithPath: "/Applications/Safari.app"),
                    openTargets: [],
                    activates: false
                ),
            ]
        )

        let response = try decode(AppLaunchEnvelope.self, from: output.stdout)
        XCTAssertEqual(
            response,
            .init(
                data: .init(
                    app: .init(
                        name: "Safari",
                        bundleId: "com.apple.Safari",
                        pid: 17
                    ),
                    opened: [],
                    ready: true,
                    focused: false
                )
            )
        )
    }

    func testLaunchByBundleIDResolvesBundleTarget() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let apps = AppState()
        apps.bundleApplications["com.apple.Notes"] = URL(fileURLWithPath: "/Applications/Notes.app")
        apps.launchedApplications = [
            StubRunningApplication(
                localizedName: "Notes",
                bundleIdentifier: "com.apple.Notes",
                processIdentifier: 23,
                readyAfterChecks: 1
            )
        ]
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["app", "launch", "--bundle-id", "com.apple.Notes"],
            environment: environment(state: state, output: output, apps: apps.makeClient())
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(
            apps.launchCalls,
            [
                .init(
                    appURL: URL(fileURLWithPath: "/Applications/Notes.app"),
                    openTargets: [],
                    activates: false
                ),
            ]
        )

        let response = try decode(AppLaunchEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.data.app.bundleId, "com.apple.Notes")
        XCTAssertEqual(response.data.app.pid, 23)
    }

    func testLaunchSupportsRepeatedOpenTargetsAndFocusFlag() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let apps = AppState()
        apps.namedApplications["Preview"] = URL(fileURLWithPath: "/Applications/Preview.app")
        let launchedApplication = StubRunningApplication(
            localizedName: "Preview",
            bundleIdentifier: "com.apple.Preview",
            processIdentifier: 44,
            readyAfterChecks: 1
        )
        apps.launchedApplications = [launchedApplication]
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: [
                "app",
                "launch",
                "Preview",
                "--open",
                "notes.txt",
                "--open",
                "https://example.com",
                "--focus",
            ],
            environment: environment(
                state: state,
                output: output,
                apps: apps.makeClient(),
                currentDirectoryPath: "/tmp/project"
            )
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(
            apps.launchCalls,
            [
                .init(
                    appURL: URL(fileURLWithPath: "/Applications/Preview.app"),
                    openTargets: [
                        URL(fileURLWithPath: "/tmp/project/notes.txt"),
                        URL(string: "https://example.com")!,
                    ],
                    activates: true
                ),
            ]
        )
        XCTAssertEqual(launchedApplication.activateCalls, 1)

        let response = try decode(AppLaunchEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.data.opened, ["/tmp/project/notes.txt", "https://example.com"])
        XCTAssertTrue(response.data.focused)
    }

    func testLaunchWaitsWhenRequested() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let apps = AppState()
        apps.namedApplications["Finder"] = URL(fileURLWithPath: "/System/Applications/Finder.app")
        let launchedApplication = StubRunningApplication(
            localizedName: "Finder",
            bundleIdentifier: "com.apple.finder",
            processIdentifier: 55,
            readyAfterChecks: 3
        )
        apps.launchedApplications = [launchedApplication]
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["app", "launch", "Finder", "--wait"],
            environment: environment(state: state, output: output, apps: apps.makeClient())
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertGreaterThanOrEqual(launchedApplication.readyChecks, 3)

        let response = try decode(AppLaunchEnvelope.self, from: output.stdout)
        XCTAssertTrue(response.data.ready)
    }

    func testLaunchWaitTimeoutReturnsStructuredError() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let apps = AppState()
        apps.namedApplications["Mail"] = URL(fileURLWithPath: "/System/Applications/Mail.app")
        apps.launchedApplications = [
            StubRunningApplication(
                localizedName: "Mail",
                bundleIdentifier: "com.apple.mail",
                processIdentifier: 61,
                readyAfterChecks: 500
            )
        ]
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["app", "launch", "Mail", "--wait"],
            environment: environment(state: state, output: output, apps: apps.makeClient())
        )

        XCTAssertEqual(exitCode, 1)
        let response = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.error.code, "app_launch_timeout")
    }

    func testLaunchValidatesTargetSelection() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["app", "launch", "Safari", "--bundle-id", "com.apple.Safari"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 1)
        let response = try decode(ErrorEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.error.code, "invalid_app_target")
    }

    func testLaunchSupportsPlainFlagAtEveryCommandLevel() async {
        let expected = "Safari pid 17\ncom.apple.Safari\nready: yes\nfocused: no\n"
        let cases = [
            ["--plain", "app", "launch", "Safari"],
            ["app", "--plain", "launch", "Safari"],
            ["app", "launch", "--plain", "Safari"],
        ]

        for arguments in cases {
            let state = PermissionState(accessibility: true, screenRecording: true)
            let apps = AppState()
            apps.namedApplications["Safari"] = URL(fileURLWithPath: "/Applications/Safari.app")
            apps.launchedApplications = [
                StubRunningApplication(
                    localizedName: "Safari",
                    bundleIdentifier: "com.apple.Safari",
                    processIdentifier: 17,
                    readyAfterChecks: 1
                )
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
