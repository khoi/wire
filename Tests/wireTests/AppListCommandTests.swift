import XCTest
@testable import wire

final class AppListCommandTests: WireCommandTestCase {
    func testListReturnsSortedJSON() async throws {
        let state = PermissionState(accessibility: true, screenRecording: true)
        let apps = AppState()
        apps.listedApplications = [
            .init(
                name: "Safari",
                bundleId: "com.apple.Safari",
                path: "/Applications/Safari.app",
                pid: 41
            ),
            .init(
                name: "Google Chrome",
                bundleId: "com.google.Chrome",
                path: "/Applications/Google Chrome.app",
                pid: 52
            )
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
        apps.listedApplications = [
            .init(
                name: "Finder",
                bundleId: "com.apple.finder",
                path: "/System/Applications/Finder.app",
                pid: 1
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
            apps.listedApplications = [
                .init(
                    name: "Google Chrome",
                    bundleId: "com.google.Chrome",
                    path: "/Applications/Google Chrome.app",
                    pid: 52
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
        XCTAssertEqual(output.stderr, "")
    }
}
