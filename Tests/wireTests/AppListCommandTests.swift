import XCTest
@testable import wire

final class AppListCommandTests: WireCommandTestCase {
    func testListReturnsSortedJSON() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let apps = AppState()
        apps.runningApplications = [
            AppRuntimeApplication(
                handle: StubRunningApplication(
                    localizedName: "Safari",
                    bundleIdentifier: "com.apple.Safari",
                    processIdentifier: 41,
                    bundleURL: URL(fileURLWithPath: "/Applications/Safari.app")
                )
            ),
            AppRuntimeApplication(
                handle: StubRunningApplication(
                    localizedName: "Google Chrome",
                    bundleIdentifier: "com.google.Chrome",
                    processIdentifier: 52,
                    bundleURL: URL(fileURLWithPath: "/Applications/Google Chrome.app")
                )
            ),
        ]
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["app", "list"],
            environment: environment(state: state, output: output, apps: apps.makeClient())
        )

        XCTAssertEqual(exitCode, 0)
        let response = try decode(AppListEnvelope.self, from: output.stdout)
        XCTAssertEqual(
            response,
            .init(
                data: .init(
                    apps: [
                        .init(
                            name: "Google Chrome",
                            bundleId: "com.google.Chrome",
                            path: "/Applications/Google Chrome.app",
                            pid: 52
                        ),
                        .init(
                            name: "Safari",
                            bundleId: "com.apple.Safari",
                            path: "/Applications/Safari.app",
                            pid: 41
                        ),
                    ]
                )
            )
        )
    }

    func testListAliasLsReturnsSameData() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let apps = AppState()
        apps.runningApplications = [
            AppRuntimeApplication(
                handle: StubRunningApplication(
                    localizedName: "Finder",
                    bundleIdentifier: "com.apple.finder",
                    processIdentifier: 1,
                    bundleURL: URL(fileURLWithPath: "/System/Applications/Finder.app")
                )
            ),
        ]
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["app", "ls"],
            environment: environment(state: state, output: output, apps: apps.makeClient())
        )

        XCTAssertEqual(exitCode, 0)
        let response = try decode(AppListEnvelope.self, from: output.stdout)
        XCTAssertEqual(response.data.apps.count, 1)
        XCTAssertEqual(response.data.apps.first?.name, "Finder")
    }

    func testListSupportsPlainFlagAtEveryCommandLevel() async {
        let expected = "Google Chrome\tcom.google.Chrome\t52\t/Applications/Google Chrome.app\n"
        let cases = [
            ["--plain", "app", "list"],
            ["app", "--plain", "list"],
            ["app", "list", "--plain"],
        ]

        for arguments in cases {
            let state = PermissionState(accessibility: true, screenRecording: true)
            let apps = AppState()
            apps.runningApplications = [
                AppRuntimeApplication(
                    handle: StubRunningApplication(
                        localizedName: "Google Chrome",
                        bundleIdentifier: "com.google.Chrome",
                        processIdentifier: 52,
                        bundleURL: URL(fileURLWithPath: "/Applications/Google Chrome.app")
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

    func testListHelpFlagExitsCleanly() async {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["app", "list", "--help"],
            environment: environment(state: state, output: output)
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(output.stdout.contains("USAGE: wire app list"))
        XCTAssertTrue(output.stdout.contains("--include-accessory"))
        XCTAssertEqual(output.stderr, "")
    }

    func testListIncludeAccessoryFlagPassesThrough() async {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let apps = AppState()
        let output = OutputCapture()

        let exitCode = await WireRunner.run(
            arguments: ["app", "list", "--include-accessory"],
            environment: environment(state: state, output: output, apps: apps.makeClient())
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(apps.runningIncludeAccessoryCalls, [true])
    }
}
