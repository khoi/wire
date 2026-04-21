@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import ArgumentParser
@preconcurrency import CoreGraphics
import Foundation

struct PermissionsClient: Sendable {
    var accessibilityStatus: @Sendable () throws -> Bool
    var accessibilityRequest: @Sendable () throws -> Bool
    var screenRecordingStatus: @Sendable () throws -> Bool
    var screenRecordingRequest: @Sendable () throws -> Bool

    init(
        accessibilityStatus: @escaping @Sendable () throws -> Bool,
        accessibilityRequest: @escaping @Sendable () throws -> Bool,
        screenRecordingStatus: @escaping @Sendable () throws -> Bool,
        screenRecordingRequest: @escaping @Sendable () throws -> Bool
    ) {
        self.accessibilityStatus = accessibilityStatus
        self.accessibilityRequest = accessibilityRequest
        self.screenRecordingStatus = screenRecordingStatus
        self.screenRecordingRequest = screenRecordingRequest
    }

    static let live = PermissionsClient(
        accessibilityStatus: {
            AXIsProcessTrusted()
        },
        accessibilityRequest: {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        },
        screenRecordingStatus: {
            CGPreflightScreenCaptureAccess()
        },
        screenRecordingRequest: {
            CGRequestScreenCaptureAccess()
        }
    )
}

struct WireEnvironment {
    var permissions: PermissionsClient
    var apps: AppClient
    var inspect: InspectClient
    var click: ClickClient
    var press: PressClient
    var scroll: ScrollClient
    var type: TypeClient
    var currentDirectoryPath: String
    var stateDirectoryPath: String
    var stdout: (String) -> Void
    var stderr: (String) -> Void

    init(
        permissions: PermissionsClient,
        apps: AppClient,
        inspect: InspectClient,
        click: ClickClient,
        press: PressClient,
        scroll: ScrollClient,
        type: TypeClient,
        currentDirectoryPath: String,
        stateDirectoryPath: String,
        stdout: @escaping (String) -> Void,
        stderr: @escaping (String) -> Void
    ) {
        self.permissions = permissions
        self.apps = apps
        self.inspect = inspect
        self.click = click
        self.press = press
        self.scroll = scroll
        self.type = type
        self.currentDirectoryPath = currentDirectoryPath
        self.stateDirectoryPath = stateDirectoryPath
        self.stdout = stdout
        self.stderr = stderr
    }

    static func live(
        permissions: PermissionsClient = .live,
        apps: AppClient? = nil,
        inspect: InspectClient? = nil,
        click: ClickClient? = nil,
        press: PressClient? = nil,
        scroll: ScrollClient? = nil,
        type: TypeClient? = nil,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        stateDirectoryPath: String = FileManager.default.temporaryDirectory.path
    ) -> WireEnvironment {
        WireEnvironment(
            permissions: permissions,
            apps: apps ?? .live(),
            inspect: inspect ?? .live(),
            click: click ?? .live(),
            press: press ?? .live(),
            scroll: scroll ?? .live(),
            type: type ?? .live(),
            currentDirectoryPath: currentDirectoryPath,
            stateDirectoryPath: stateDirectoryPath,
            stdout: { text in
                FileHandle.standardOutput.write(Data(text.utf8))
            },
            stderr: { text in
                FileHandle.standardError.write(Data(text.utf8))
            }
        )
    }
}

struct OutputOptions: ParsableArguments {
    @Flag(name: .long, help: "Output human-readable text.")
    var plain = false

    @Flag(name: [.customLong("verbose"), .short], help: "Write verbose logs to stderr.")
    var verbose = false
}

struct Logger {
    let isVerbose: Bool
    let write: (String) -> Void

    func log(_ message: String) {
        guard isVerbose else {
            return
        }
        write("[verbose] \(message)\n")
    }
}

struct CommandContext {
    let environment: WireEnvironment
    let logger: Logger

    var permissions: PermissionsClient {
        environment.permissions
    }

    var apps: AppClient {
        environment.apps
    }

    var inspect: InspectClient {
        environment.inspect
    }

    var click: ClickClient {
        environment.click
    }

    var press: PressClient {
        environment.press
    }

    var scroll: ScrollClient {
        environment.scroll
    }

    var type: TypeClient {
        environment.type
    }

    var currentDirectoryPath: String {
        environment.currentDirectoryPath
    }

    var stateDirectoryPath: String {
        environment.stateDirectoryPath
    }
}

enum PermissionKind: String, CaseIterable, Codable {
    case accessibility
    case screenRecording = "screen-recording"
}

struct PermissionStatusEntry: Codable, Equatable {
    let kind: PermissionKind
    let granted: Bool
}

struct PermissionGrantEntry: Codable, Equatable {
    let kind: PermissionKind
    let granted: Bool
    let requested: Bool
}

struct PermissionsStatusData: Codable, Equatable {
    let permissions: [PermissionStatusEntry]

    func plainText() -> String {
        permissions.map { entry in
            "\(entry.kind.rawValue): \(entry.granted ? "granted" : "missing")"
        }.joined(separator: "\n")
    }
}

struct PermissionsGrantData: Codable, Equatable {
    let permissions: [PermissionGrantEntry]

    func plainText() -> String {
        permissions.map { entry in
            var line = "\(entry.kind.rawValue): \(entry.granted ? "granted" : "missing")"
            if entry.requested {
                line += " requested"
            }
            return line
        }.joined(separator: "\n")
    }
}

struct SuccessEnvelope<Payload: Encodable>: Encodable {
    let snapshot: String?
    let data: Payload

    private enum CodingKeys: String, CodingKey {
        case snapshot
        case data
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(snapshot, forKey: .snapshot)
        try container.encode(data, forKey: .data)
    }
}

struct FailureEnvelope: Encodable {
    let error: FailureBody
}

struct FailureBody: Encodable {
    let code: String
    let message: String
}

struct CommandExecution {
    let exitCode: Int32
    let plainText: String
    let jsonText: String

    static func success<Payload: Encodable>(
        data: Payload,
        plainText: String,
        snapshot: String? = nil,
        exitCode: Int32 = 0
    ) -> CommandExecution {
        CommandExecution(
            exitCode: exitCode,
            plainText: plainText,
            jsonText: encodeJSON(SuccessEnvelope(snapshot: snapshot, data: data))
        )
    }

    func write(options: OutputOptions, environment: WireEnvironment) {
        let text = options.plain ? plainText : jsonText
        environment.stdout(terminated(text))
    }
}

protocol WireError: Error {
    var code: String { get }
    var message: String { get }
    var exitCode: Int32 { get }
}

extension WireError {
    func write(options: OutputOptions, environment: WireEnvironment) {
        if options.plain {
            environment.stdout(terminated(message))
            return
        }
        writeJSON(environment: environment)
    }

    func writeJSON(environment: WireEnvironment) {
        let payload = FailureEnvelope(error: FailureBody(code: code, message: message))
        environment.stdout(terminated(encodeJSON(payload)))
    }
}

enum WireRuntimeError: WireError {
    case parse(String)

    var code: String {
        switch self {
        case .parse:
            return "parse_error"
        }
    }

    var message: String {
        switch self {
        case .parse(let message):
            return message
        }
    }

    var exitCode: Int32 {
        64
    }
}

enum PermissionsServiceError: WireError {
    case status(PermissionKind, Error)
    case request(PermissionKind, Error)

    var code: String {
        switch self {
        case .status(let kind, _):
            return "\(kind.rawValue.replacingOccurrences(of: "-", with: "_"))_status_failed"
        case .request(let kind, _):
            return "\(kind.rawValue.replacingOccurrences(of: "-", with: "_"))_request_failed"
        }
    }

    var message: String {
        switch self {
        case .status(let kind, let error):
            return "failed to read \(kind.rawValue) permission: \(String(describing: error))"
        case .request(let kind, let error):
            return "failed to request \(kind.rawValue) permission: \(String(describing: error))"
        }
    }

    var exitCode: Int32 {
        1
    }
}

struct PermissionsService {
    let client: PermissionsClient
    let logger: Logger

    func status() throws -> PermissionsStatusData {
        logger.log("checking accessibility permission")
        let accessibility = try readStatus(.accessibility)
        logger.log("checking screen-recording permission")
        let screenRecording = try readStatus(.screenRecording)
        return PermissionsStatusData(
            permissions: [
                PermissionStatusEntry(kind: .accessibility, granted: accessibility),
                PermissionStatusEntry(kind: .screenRecording, granted: screenRecording),
            ]
        )
    }

    func grant() throws -> PermissionsGrantData {
        logger.log("checking current permission state")
        let before = try snapshot()
        let missing = before.filter { !$0.granted }.map(\.kind)

        if missing.isEmpty {
            logger.log("all permissions already granted")
        } else {
            logger.log("missing permissions: \(missing.map(\.rawValue).joined(separator: ", "))")
        }

        for kind in missing {
            logger.log("requesting \(kind.rawValue) permission")
            try request(kind)
        }

        logger.log("re-checking permission state")
        let after = try snapshot()
        let requested = Set(missing)

        return PermissionsGrantData(
            permissions: after.map { entry in
                PermissionGrantEntry(
                    kind: entry.kind,
                    granted: entry.granted,
                    requested: requested.contains(entry.kind)
                )
            }
        )
    }

    private func snapshot() throws -> [PermissionStatusEntry] {
        try PermissionKind.allCases.map { kind in
            PermissionStatusEntry(kind: kind, granted: try readStatus(kind))
        }
    }

    private func readStatus(_ kind: PermissionKind) throws -> Bool {
        do {
            switch kind {
            case .accessibility:
                return try client.accessibilityStatus()
            case .screenRecording:
                return try client.screenRecordingStatus()
            }
        } catch {
            throw PermissionsServiceError.status(kind, error)
        }
    }

    private func request(_ kind: PermissionKind) throws {
        do {
            switch kind {
            case .accessibility:
                _ = try client.accessibilityRequest()
            case .screenRecording:
                _ = try client.screenRecordingRequest()
            }
        } catch {
            throw PermissionsServiceError.request(kind, error)
        }
    }
}

protocol WireExecutableCommand {
    var outputOptions: OutputOptions { get }
    func execute(context: CommandContext) async throws -> CommandExecution
}

private func terminated(_ text: String) -> String {
    text.hasSuffix("\n") ? text : text + "\n"
}

private func encodeJSON<Value: Encodable>(_ value: Value) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    do {
        let data = try encoder.encode(value)
        guard let text = String(bytes: data, encoding: .utf8) else {
            preconditionFailure("failed to decode JSON output as UTF-8")
        }
        return text
    } catch {
        preconditionFailure("failed to encode JSON: \(error)")
    }
}
