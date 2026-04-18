@preconcurrency import AppKit
import Foundation

protocol RunningApplicationHandle: AnyObject {
    var localizedName: String? { get }
    var bundleIdentifier: String? { get }
    var processIdentifier: Int32 { get }
    var isFinishedLaunching: Bool { get }
    @discardableResult
    func activate(options: NSApplication.ActivationOptions) -> Bool
}

extension NSRunningApplication: RunningApplicationHandle {}

enum AppLaunchTarget: Equatable {
    case app(String)
    case bundleID(String)
}

struct AppClient {
    var resolveApplicationURL: (_ target: AppLaunchTarget, _ currentDirectoryPath: String) async throws -> URL
    var launchApplication: (_ appURL: URL, _ openTargets: [URL], _ activates: Bool) async throws -> any RunningApplicationHandle

    init(
        resolveApplicationURL: @escaping (_ target: AppLaunchTarget, _ currentDirectoryPath: String) async throws -> URL,
        launchApplication: @escaping (_ appURL: URL, _ openTargets: [URL], _ activates: Bool) async throws -> any RunningApplicationHandle
    ) {
        self.resolveApplicationURL = resolveApplicationURL
        self.launchApplication = launchApplication
    }

    static func live() -> AppClient {
        AppClient(
            resolveApplicationURL: { target, currentDirectoryPath in
                try LiveAppSystem.resolveApplicationURL(
                    target: target,
                    currentDirectoryPath: currentDirectoryPath
                )
            },
            launchApplication: { appURL, openTargets, activates in
                try await LiveAppSystem.launchApplication(
                    appURL: appURL,
                    openTargets: openTargets,
                    activates: activates
                )
            }
        )
    }
}

struct AppLaunchData: Codable, Equatable {
    struct App: Codable, Equatable {
        let name: String
        let bundleId: String?
        let pid: Int32
    }

    let app: App
    let opened: [String]
    let ready: Bool
    let focused: Bool

    func plainText() -> String {
        var lines = ["\(app.name) pid \(app.pid)"]
        if let bundleId = app.bundleId {
            lines.append(bundleId)
        }
        lines.append("ready: \(ready ? "yes" : "no")")
        lines.append("focused: \(focused ? "yes" : "no")")
        if !opened.isEmpty {
            lines.append("opened: \(opened.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }
}

enum AppLaunchError: WireError {
    case invalidTarget(String)
    case appNotFound(String)
    case invalidOpenTarget(String)
    case launchFailed(String)
    case waitTimedOut(String)

    var code: String {
        switch self {
        case .invalidTarget:
            return "invalid_app_target"
        case .appNotFound:
            return "app_not_found"
        case .invalidOpenTarget:
            return "invalid_open_target"
        case .launchFailed:
            return "app_launch_failed"
        case .waitTimedOut:
            return "app_launch_timeout"
        }
    }

    var message: String {
        switch self {
        case .invalidTarget(let message),
             .appNotFound(let message),
             .invalidOpenTarget(let message),
             .launchFailed(let message),
             .waitTimedOut(let message):
            return message
        }
    }

    var exitCode: Int32 {
        1
    }
}

struct AppLaunchService {
    let client: AppClient
    let logger: Logger
    let currentDirectoryPath: String

    func launch(
        target: AppLaunchTarget,
        openTargets: [String],
        wait: Bool,
        focus: Bool
    ) async throws -> AppLaunchData {
        logger.log("resolving application target")
        let appURL = try await client.resolveApplicationURL(target, currentDirectoryPath)
        logger.log("resolved application to \(appURL.path)")
        let resolvedOpenTargets = try openTargets.map { try resolveOpenTarget($0) }
        if resolvedOpenTargets.isEmpty {
            logger.log("launching application")
        } else {
            logger.log("launching application with \(resolvedOpenTargets.count) open target(s)")
        }
        let application: any RunningApplicationHandle
        do {
            application = try await client.launchApplication(appURL, resolvedOpenTargets, focus)
        } catch {
            throw AppLaunchError.launchFailed("failed to launch \(appURL.lastPathComponent): \(String(describing: error))")
        }
        if wait {
            logger.log("waiting for application to finish launching")
            try await waitUntilReady(application)
        }
        let focused = focus ? mainThread { application.activate(options: []) } : false
        let appName = mainThread { application.localizedName } ?? displayName(for: appURL)
        let bundleID = mainThread { application.bundleIdentifier } ?? Bundle(url: appURL)?.bundleIdentifier
        let ready = mainThread { application.isFinishedLaunching }
        return AppLaunchData(
            app: .init(
                name: appName,
                bundleId: bundleID,
                pid: mainThread { application.processIdentifier }
            ),
            opened: resolvedOpenTargets.map(normalizedTarget),
            ready: ready,
            focused: focused
        )
    }

    private func waitUntilReady(
        _ application: any RunningApplicationHandle,
        timeout: TimeInterval = 10
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !mainThread({ application.isFinishedLaunching }) {
            if Date() >= deadline {
                throw AppLaunchError.waitTimedOut("application did not finish launching within \(Int(timeout)) seconds")
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private func resolveOpenTarget(_ value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppLaunchError.invalidOpenTarget("open target must not be empty")
        }
        if let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty {
            return url
        }
        let expanded = NSString(string: trimmed).expandingTildeInPath
        let absolutePath = if expanded.hasPrefix("/") {
            expanded
        } else {
            NSString(string: currentDirectoryPath).appendingPathComponent(expanded)
        }
        return URL(fileURLWithPath: absolutePath)
    }

    private func normalizedTarget(_ url: URL) -> String {
        url.isFileURL ? url.path : url.absoluteString
    }

    private func displayName(for appURL: URL) -> String {
        appURL.deletingPathExtension().lastPathComponent
    }
}

enum LiveAppSystem {
    static func resolveApplicationURL(
        target: AppLaunchTarget,
        currentDirectoryPath: String
    ) throws -> URL {
        try mainThread {
            switch target {
            case .bundleID(let bundleID):
                guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                    throw AppLaunchError.appNotFound("application not found for bundle id \(bundleID)")
                }
                return appURL
            case .app(let app):
                if let appURL = resolvePath(app, currentDirectoryPath: currentDirectoryPath) {
                    return appURL
                }
                if let appURL = resolveNamedApplication(app) {
                    return appURL
                }
                throw AppLaunchError.appNotFound("application not found: \(app)")
            }
        }
    }

    static func launchApplication(
        appURL: URL,
        openTargets: [URL],
        activates: Bool
    ) async throws -> any RunningApplicationHandle {
        if openTargets.isEmpty {
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.main.async {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = activates
                    NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { application, error in
                        if let application {
                            continuation.resume(returning: application)
                            return
                        }
                        continuation.resume(throwing: error ?? AppLaunchError.launchFailed("launch returned no application"))
                    }
                }
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = activates
                NSWorkspace.shared.open(openTargets, withApplicationAt: appURL, configuration: configuration) { application, error in
                    if let application {
                        continuation.resume(returning: application)
                        return
                    }
                    continuation.resume(throwing: error ?? AppLaunchError.launchFailed("launch returned no application"))
                }
            }
        }
    }

    private static func resolvePath(_ app: String, currentDirectoryPath: String) -> URL? {
        guard app.hasPrefix("/") || app.hasPrefix("~") || app.hasPrefix(".") || app.contains("/") else {
            return nil
        }
        let expanded = NSString(string: app).expandingTildeInPath
        let absolutePath = if expanded.hasPrefix("/") {
            expanded
        } else {
            NSString(string: currentDirectoryPath).appendingPathComponent(expanded)
        }
        guard FileManager.default.fileExists(atPath: absolutePath) else {
            return nil
        }
        return URL(fileURLWithPath: absolutePath)
    }

    private static func resolveNamedApplication(_ app: String) -> URL? {
        let names = app.hasSuffix(".app") ? [app] : [app, "\(app).app"]
        for directory in applicationSearchDirectories {
            for name in names {
                let appURL = directory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: appURL.path) {
                    return appURL
                }
            }
        }
        return nil
    }

    private static var applicationSearchDirectories: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: NSString(string: "~/Applications").expandingTildeInPath),
        ]
    }
}

private func mainThread<T>(_ body: () throws -> T) rethrows -> T {
    if Thread.isMainThread {
        return try body()
    }
    return try DispatchQueue.main.sync(execute: body)
}
