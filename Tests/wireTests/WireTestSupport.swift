import AppKit
import XCTest
@testable import wire

class WireCommandTestCase: XCTestCase {
    func environment(
        state: PermissionState,
        output: OutputCapture,
        apps: AppClient? = nil,
        currentDirectoryPath: String = "/tmp/wire-tests"
    ) -> WireEnvironment {
        WireEnvironment(
            permissions: state.makeClient(),
            apps: apps ?? AppState().makeClient(),
            currentDirectoryPath: currentDirectoryPath,
            stdout: output.writeStdout,
            stderr: output.writeStderr
        )
    }

    func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(string.utf8))
    }
}

final class PermissionState: @unchecked Sendable {
    var accessibility: Bool
    var screenRecording: Bool
    var accessibilityRequests = 0
    var screenRecordingRequests = 0
    var grantAccessibilityOnRequest = false
    var grantScreenRecordingOnRequest = false

    init(accessibility: Bool, screenRecording: Bool) {
        self.accessibility = accessibility
        self.screenRecording = screenRecording
    }

    func makeClient() -> PermissionsClient {
        PermissionsClient(
            accessibilityStatus: {
                self.accessibility
            },
            accessibilityRequest: {
                self.accessibilityRequests += 1
                if self.grantAccessibilityOnRequest {
                    self.accessibility = true
                }
                return self.accessibility
            },
            screenRecordingStatus: {
                self.screenRecording
            },
            screenRecordingRequest: {
                self.screenRecordingRequests += 1
                if self.grantScreenRecordingOnRequest {
                    self.screenRecording = true
                }
                return self.screenRecording
            }
        )
    }
}

final class OutputCapture {
    var stdout = ""
    var stderr = ""

    func writeStdout(_ text: String) {
        stdout += text
    }

    func writeStderr(_ text: String) {
        stderr += text
    }
}

final class StubRunningApplication: RunningApplicationHandle {
    enum TerminationMode {
        case graceful
        case force
    }

    var localizedName: String?
    var bundleIdentifier: String?
    var bundleURL: URL?
    var processIdentifier: Int32
    var readyAfterChecks: Int
    var readyChecks = 0
    var activateCalls = 0
    var activateResult = true
    var terminated = false
    var terminationMode: TerminationMode?
    var terminationChecks = 0
    var terminateAfterChecks = 1
    var forceTerminateAfterChecks = 1
    var terminateCalls = 0
    var terminateResult = true
    var forceTerminateCalls = 0
    var forceTerminateResult = true

    init(
        localizedName: String? = "StubApp",
        bundleIdentifier: String? = "com.example.stub",
        processIdentifier: Int32 = 42,
        readyAfterChecks: Int = 1,
        bundleURL: URL? = nil
    ) {
        self.localizedName = localizedName
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.readyAfterChecks = readyAfterChecks
        self.bundleURL = bundleURL
    }

    var isFinishedLaunching: Bool {
        readyChecks += 1
        return readyChecks >= readyAfterChecks
    }

    var isTerminated: Bool {
        if terminated {
            return true
        }
        guard let terminationMode else {
            return false
        }
        terminationChecks += 1
        let requiredChecks = switch terminationMode {
        case .graceful:
            terminateAfterChecks
        case .force:
            forceTerminateAfterChecks
        }
        if terminationChecks >= requiredChecks {
            terminated = true
        }
        return terminated
    }

    @discardableResult
    func activate(options: NSApplication.ActivationOptions) -> Bool {
        activateCalls += 1
        return activateResult
    }

    @discardableResult
    func terminate() -> Bool {
        terminateCalls += 1
        guard terminateResult else {
            return false
        }
        terminationMode = .graceful
        terminationChecks = 0
        return true
    }

    @discardableResult
    func forceTerminate() -> Bool {
        forceTerminateCalls += 1
        guard forceTerminateResult else {
            return false
        }
        terminationMode = .force
        terminationChecks = 0
        return true
    }
}

final class AppState {
    struct LaunchCall: Equatable {
        let appURL: URL
        let openTargets: [URL]
        let activates: Bool
    }

    var namedApplications: [String: URL] = [:]
    var bundleApplications: [String: URL] = [:]
    var launchCalls: [LaunchCall] = []
    var launchedApplications: [StubRunningApplication] = []
    var launchError: Error?
    var runningApplications: [AppRuntimeApplication] = []
    var runningIncludeAccessoryCalls: [Bool] = []

    func makeClient() -> AppClient {
        AppClient(
            resolveApplicationURL: { target, _ in
                switch target {
                case .app(let app):
                    if let url = self.namedApplications[app] {
                        return url
                    }
                    throw AppLaunchError.appNotFound("application not found: \(app)")
                case .bundleID(let bundleID):
                    if let url = self.bundleApplications[bundleID] {
                        return url
                    }
                    throw AppLaunchError.appNotFound("application not found for bundle id \(bundleID)")
                }
            },
            launchApplication: { appURL, openTargets, activates in
                self.launchCalls.append(
                    .init(
                        appURL: appURL,
                        openTargets: openTargets,
                        activates: activates
                    )
                )
                if let launchError = self.launchError {
                    throw launchError
                }
                if !self.launchedApplications.isEmpty {
                    return self.launchedApplications.removeFirst()
                }
                return StubRunningApplication()
            },
            runningApplications: { includeAccessory in
                self.runningIncludeAccessoryCalls.append(includeAccessory)
                return self.runningApplications
            }
        )
    }
}

struct StatusEnvelope: Decodable, Equatable {
    let data: StatusData
}

struct StatusData: Decodable, Equatable {
    let permissions: [StatusPermission]
}

struct StatusPermission: Decodable, Equatable {
    let kind: String
    let granted: Bool
}

struct GrantEnvelope: Decodable, Equatable {
    let data: GrantData
}

struct GrantData: Decodable, Equatable {
    let permissions: [GrantPermission]
}

struct GrantPermission: Decodable, Equatable {
    let kind: String
    let granted: Bool
    let requested: Bool
}

struct ErrorEnvelope: Decodable, Equatable {
    let error: ErrorBody
}

struct ErrorBody: Decodable, Equatable {
    let code: String
    let message: String
}

struct AppLaunchEnvelope: Decodable, Equatable {
    let data: AppLaunchPayload
}

struct AppLaunchPayload: Decodable, Equatable {
    let app: AppLaunchApp
    let opened: [String]
    let ready: Bool
    let focused: Bool
}

struct AppLaunchApp: Decodable, Equatable {
    let name: String
    let bundleId: String?
    let pid: Int32
}

struct AppListEnvelope: Decodable, Equatable {
    let data: AppListPayload
}

struct AppListPayload: Decodable, Equatable {
    let apps: [AppListItem]
}

struct AppListItem: Decodable, Equatable {
    let name: String
    let bundleId: String?
    let path: String?
    let pid: Int32
}

struct AppQuitEnvelope: Decodable, Equatable {
    let data: AppQuitPayload
}

struct AppQuitPayload: Decodable, Equatable {
    let apps: [AppQuitItem]
    let forced: Bool
}

struct AppQuitItem: Decodable, Equatable {
    let name: String
    let bundleId: String?
    let path: String?
    let pid: Int32
    let terminated: Bool
    let message: String?
}
