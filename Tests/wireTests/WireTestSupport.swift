import XCTest
@testable import wire

class WireCommandTestCase: XCTestCase {
    func environment(state: PermissionState, output: OutputCapture) -> WireEnvironment {
        WireEnvironment(
            permissions: state.makeClient(),
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

struct StatusEnvelope: Decodable, Equatable {
    let ok: Bool
    let data: StatusData
}

struct StatusData: Decodable, Equatable {
    let ready: Bool
    let permissions: [StatusPermission]
}

struct StatusPermission: Decodable, Equatable {
    let kind: String
    let granted: Bool
}

struct GrantEnvelope: Decodable, Equatable {
    let ok: Bool
    let data: GrantData
}

struct GrantData: Decodable, Equatable {
    let ready: Bool
    let permissions: [GrantPermission]
}

struct GrantPermission: Decodable, Equatable {
    let kind: String
    let before: Bool
    let after: Bool
    let requested: Bool
}

struct ErrorEnvelope: Decodable, Equatable {
    let ok: Bool
    let error: ErrorBody
}

struct ErrorBody: Decodable, Equatable {
    let code: String
    let message: String
}
