import AppKit
import XCTest
@testable import wire

class WireCommandTestCase: XCTestCase {
    func environment(
        state: PermissionState,
        output: OutputCapture,
        apps: AppClient? = nil,
        inspect: InspectClient? = nil,
        click: ClickClient? = nil,
        scroll: ScrollClient? = nil,
        type: TypeClient? = nil,
        currentDirectoryPath: String = "/tmp/wire-tests",
        stateDirectoryPath: String = "/tmp/wire-state-tests"
    ) -> WireEnvironment {
        WireEnvironment(
            permissions: state.makeClient(),
            apps: apps ?? AppState().makeClient(),
            inspect: inspect ?? InspectState().makeClient(),
            click: click ?? ClickState().makeClient(),
            scroll: scroll ?? ScrollState().makeClient(),
            type: type ?? TypeState().makeClient(),
            currentDirectoryPath: currentDirectoryPath,
            stateDirectoryPath: stateDirectoryPath,
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

final class InspectState {
    var captureCalls: [InspectTarget] = []
    var nextCapture = CapturedInspection(
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
                enabled: true,
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
                    actions: ["AXPress"],
                    valueSettable: true
                )
            )
        ]
    )
    var captureError: Error?

    func makeClient() -> InspectClient {
        InspectClient(
            capture: { target in
                self.captureCalls.append(target)
                if let captureError = self.captureError {
                    throw captureError
                }
                return self.nextCapture
            }
        )
    }
}

final class ClickState {
    struct Call: Equatable {
        let snapshot: String
        let elementID: String
        let right: Bool
    }

    var calls: [Call] = []
    var clickError: Error?

    func makeClient() -> ClickClient {
        ClickClient(
            perform: { snapshotID, element, right in
                self.calls.append(
                    .init(
                        snapshot: snapshotID,
                        elementID: element.id,
                        right: right
                    )
                )
                if let clickError = self.clickError {
                    throw clickError
                }
            }
        )
    }
}

final class TypeState {
    struct FocusedCall: Equatable {
        let text: String
    }

    struct ElementCall: Equatable {
        let elementID: String
        let text: String
    }

    var focusedCalls: [FocusedCall] = []
    var elementCalls: [ElementCall] = []
    var focusedError: Error?
    var elementError: Error?

    func makeClient() -> TypeClient {
        TypeClient(
            typeFocused: { text in
                self.focusedCalls.append(.init(text: text))
                if let focusedError = self.focusedError {
                    throw focusedError
                }
            },
            typeElement: { element, text in
                self.elementCalls.append(.init(elementID: element.id, text: text))
                if let elementError = self.elementError {
                    throw elementError
                }
            }
        )
    }
}

final class ScrollState {
    struct FocusedCall: Equatable {
        let direction: ScrollDirection
        let amount: Int
    }

    struct ElementCall: Equatable {
        let elementID: String
        let direction: ScrollDirection
        let amount: Int
    }

    var focusedCalls: [FocusedCall] = []
    var elementCalls: [ElementCall] = []
    var focusedError: Error?
    var elementError: Error?

    func makeClient() -> ScrollClient {
        ScrollClient(
            scrollFocused: { direction, amount in
                self.focusedCalls.append(
                    .init(
                        direction: direction,
                        amount: amount
                    )
                )
                if let focusedError = self.focusedError {
                    throw focusedError
                }
            },
            scrollElement: { element, direction, amount in
                self.elementCalls.append(
                    .init(
                        elementID: element.id,
                        direction: direction,
                        amount: amount
                    )
                )
                if let elementError = self.elementError {
                    throw elementError
                }
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

struct TypeEnvelope: Decodable, Equatable {
    let snapshot: String?
    let data: TypePayload
}

struct TypePayload: Decodable, Equatable {
    struct Target: Decodable, Equatable {
        let id: String
        let role: String
        let name: String
    }

    let text: String
    let into: String?
    let target: Target?
    let typed: Bool
}

struct ScrollEnvelope: Decodable, Equatable {
    let snapshot: String?
    let data: ScrollPayload
}

struct ScrollPayload: Decodable, Equatable {
    struct Target: Decodable, Equatable {
        let id: String
        let role: String
        let name: String
    }

    let direction: String
    let amount: Int
    let on: String?
    let target: Target?
    let scrolled: Bool
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

struct InspectEnvelope: Decodable, Equatable {
    let snapshot: String
    let data: InspectPayload
}

struct InspectPayload: Decodable, Equatable {
    let app: InspectApp
    let imagePath: String
    let elements: [InspectItem]
}

struct InspectApp: Decodable, Equatable {
    let name: String
    let bundleId: String?
    let pid: Int32
    let focused: Bool
}

struct InspectItem: Decodable, Equatable {
    let id: String
    let role: String
    let name: String
    let clickable: Bool
    let value: String?
    let enabled: Bool?
}

struct ClickEnvelope: Decodable, Equatable {
    let data: ClickPayload
}

struct ClickPayload: Decodable, Equatable {
    let snapshot: String
    let right: Bool
    let clicks: [ClickedItem]
}

struct ClickedItem: Decodable, Equatable {
    let target: String
    let id: String?
    let role: String?
    let name: String?
    let clicked: Bool
    let failure: ClickFailure?
}

struct ClickFailure: Decodable, Equatable {
    let code: String
    let message: String
}
