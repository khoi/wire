@preconcurrency import ApplicationServices
import ArgumentParser
@preconcurrency import CoreGraphics
import Foundation

public struct PermissionsClient: Sendable {
    var accessibilityStatus: @Sendable () throws -> Bool
    var accessibilityRequest: @Sendable () throws -> Bool
    var screenRecordingStatus: @Sendable () throws -> Bool
    var screenRecordingRequest: @Sendable () throws -> Bool

    public init(
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

    public static let live = PermissionsClient(
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

public struct WireEnvironment {
    public var permissions: PermissionsClient
    public var stdout: (String) -> Void
    public var stderr: (String) -> Void

    public init(
        permissions: PermissionsClient,
        stdout: @escaping (String) -> Void,
        stderr: @escaping (String) -> Void
    ) {
        self.permissions = permissions
        self.stdout = stdout
        self.stderr = stderr
    }

    public static func live(permissions: PermissionsClient = .live) -> WireEnvironment {
        WireEnvironment(
            permissions: permissions,
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

    static func detect(arguments: [String]) -> OutputOptions {
        var options = OutputOptions()
        options.plain = arguments.contains("--plain")
        options.verbose = arguments.contains("--verbose") || arguments.contains("-v")
        return options
    }

    init() {}
}

struct Logger {
    let isVerbose: Bool
    let write: (String) -> Void

    func log(_ message: String) {
        guard isVerbose else {
            return
        }
        write("[wire] \(message)\n")
    }
}

struct CommandContext {
    let options: OutputOptions
    let environment: WireEnvironment

    var permissions: PermissionsClient {
        environment.permissions
    }

    var logger: Logger {
        Logger(isVerbose: options.verbose, write: environment.stderr)
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
    let before: Bool
    let after: Bool
    let requested: Bool
}

struct PermissionsStatusData: Codable, Equatable {
    let ready: Bool
    let permissions: [PermissionStatusEntry]

    init(permissions: [PermissionStatusEntry]) {
        self.permissions = permissions
        ready = permissions.allSatisfy(\.granted)
    }

    func plainText() -> String {
        ([readyLine] + permissions.map { entry in
            "\(entry.kind.rawValue): \(entry.granted ? "granted" : "missing")"
        }).joined(separator: "\n")
    }

    private var readyLine: String {
        "ready: \(ready ? "yes" : "no")"
    }
}

struct PermissionsGrantData: Codable, Equatable {
    let ready: Bool
    let permissions: [PermissionGrantEntry]

    init(permissions: [PermissionGrantEntry]) {
        self.permissions = permissions
        ready = permissions.allSatisfy(\.after)
    }

    func plainText() -> String {
        ([readyLine] + permissions.map { entry in
            var line = "\(entry.kind.rawValue): \(entry.after ? "granted" : "missing")"
            if entry.requested {
                line += " requested"
            }
            return line
        }).joined(separator: "\n")
    }

    private var readyLine: String {
        "ready: \(ready ? "yes" : "no")"
    }
}

struct SuccessEnvelope<Payload: Encodable>: Encodable {
    let ok = true
    let command: String
    let data: Payload
}

struct FailureEnvelope: Encodable {
    let ok = false
    let command: String
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
        command: String,
        data: Payload,
        plainText: String,
        exitCode: Int32 = 0
    ) throws -> CommandExecution {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try encoder.encode(SuccessEnvelope(command: command, data: data))
        return CommandExecution(
            exitCode: exitCode,
            plainText: plainText,
            jsonText: String(decoding: json, as: UTF8.self)
        )
    }

    func write(options: OutputOptions, environment: WireEnvironment) {
        let text = options.plain ? plainText : jsonText
        environment.stdout(text.hasSuffix("\n") ? text : text + "\n")
    }
}

struct WireFailure: Error {
    let command: String
    let code: String
    let message: String
    let exitCode: Int32

    func write(options: OutputOptions, environment: WireEnvironment) {
        if options.plain {
            environment.stdout(message.hasSuffix("\n") ? message : message + "\n")
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try? encoder.encode(
            FailureEnvelope(
                command: command,
                error: FailureBody(code: code, message: message)
            )
        )
        if let json {
            let text = String(decoding: json, as: UTF8.self)
            environment.stdout(text.hasSuffix("\n") ? text : text + "\n")
            return
        }
        environment.stdout("{\"command\":\"\(command)\",\"error\":{\"code\":\"\(code)\",\"message\":\"\(message)\"},\"ok\":false}\n")
    }
}

enum PermissionsServiceError: Error {
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
            permissions: PermissionKind.allCases.map { kind in
                PermissionGrantEntry(
                    kind: kind,
                    before: value(for: kind, in: before),
                    after: value(for: kind, in: after),
                    requested: requested.contains(kind)
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

    private func value(for kind: PermissionKind, in entries: [PermissionStatusEntry]) -> Bool {
        entries.first(where: { $0.kind == kind })?.granted ?? false
    }
}

protocol WireExecutableCommand {
    var outputOptions: OutputOptions { get }
    func execute(context: CommandContext) throws -> CommandExecution
}
