@preconcurrency import AppKit
import Foundation

protocol RunningApplicationHandle: AnyObject {
    var localizedName: String? { get }
    var bundleIdentifier: String? { get }
    var bundleURL: URL? { get }
    var processIdentifier: Int32 { get }
    var isFinishedLaunching: Bool { get }
    var isTerminated: Bool { get }
    @discardableResult
    func activate(options: NSApplication.ActivationOptions) -> Bool
    @discardableResult
    func terminate() -> Bool
    @discardableResult
    func forceTerminate() -> Bool
}

extension NSRunningApplication: RunningApplicationHandle {}

enum AppLaunchTarget: Equatable {
    case app(String)
    case bundleID(String)
}

enum AppQuitTarget: Equatable {
    case app(String)
    case pid(Int32)
}

struct AppRuntimeApplication {
    let name: String
    let bundleId: String?
    let path: String?
    let pid: Int32
    let handle: any RunningApplicationHandle

    init(handle: any RunningApplicationHandle) {
        name =
            handle.localizedName
            ?? handle.bundleURL?.deletingPathExtension().lastPathComponent
            ?? handle.bundleIdentifier
            ?? "Unknown"
        bundleId = handle.bundleIdentifier
        path = handle.bundleURL?.path
        pid = handle.processIdentifier
        self.handle = handle
    }

    var listEntry: AppListEntry {
        AppListEntry(
            name: name,
            bundleId: bundleId,
            path: path,
            pid: pid
        )
    }
}

struct AppClient {
    typealias ResolveApplicationURL = (
        _ target: AppLaunchTarget,
        _ currentDirectoryPath: String
    ) async throws -> URL
    typealias LaunchApplication = (
        _ appURL: URL,
        _ openTargets: [URL],
        _ activates: Bool
    ) async throws -> any RunningApplicationHandle
    typealias RunningApplications = (_ includeAccessory: Bool) async throws -> [AppRuntimeApplication]

    var resolveApplicationURL: ResolveApplicationURL
    var launchApplication: LaunchApplication
    var runningApplications: RunningApplications

    init(
        resolveApplicationURL: @escaping ResolveApplicationURL,
        launchApplication: @escaping LaunchApplication,
        runningApplications: @escaping RunningApplications
    ) {
        self.resolveApplicationURL = resolveApplicationURL
        self.launchApplication = launchApplication
        self.runningApplications = runningApplications
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
            },
            runningApplications: { includeAccessory in
                try LiveAppSystem.runningApplications(includeAccessory: includeAccessory)
            }
        )
    }
}

struct AppListEntry: Codable, Equatable {
    let name: String
    let bundleId: String?
    let path: String?
    let pid: Int32
}

struct AppListData: Codable, Equatable {
    let apps: [AppListEntry]

    func plainText() -> String {
        apps.map { app in
            [
                app.name,
                app.bundleId ?? "-",
                String(app.pid),
                app.path ?? "-",
            ].joined(separator: "\t")
        }.joined(separator: "\n")
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

struct AppQuitData: Codable, Equatable {
    struct App: Codable, Equatable {
        let name: String
        let bundleId: String?
        let path: String?
        let pid: Int32
        let terminated: Bool
        let message: String?
    }

    let apps: [App]
    let forced: Bool

    var exitCode: Int32 {
        apps.allSatisfy(\.terminated) ? 0 : 1
    }

    func plainText() -> String {
        apps.map { app in
            [
                app.name,
                app.bundleId ?? "-",
                String(app.pid),
                app.path ?? "-",
                app.terminated
                    ? (forced ? "force-quit" : "quit")
                    : "failed: \(app.message ?? "quit failed")",
            ].joined(separator: "\t")
        }.joined(separator: "\n")
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

enum AppQuitError: WireError {
    case invalidTarget(String)
    case appNotRunning(String)

    var code: String {
        switch self {
        case .invalidTarget:
            return "invalid_app_target"
        case .appNotRunning:
            return "app_not_running"
        }
    }

    var message: String {
        switch self {
        case .invalidTarget(let message),
             .appNotRunning(let message):
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
            throw AppLaunchError.launchFailed(
                "failed to launch \(appURL.lastPathComponent): \(String(describing: error))"
            )
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

struct AppQuitService {
    private struct RequestedApplication {
        let application: AppRuntimeApplication
        let requestAccepted: Bool
    }

    let client: AppClient
    let logger: Logger
    let timeout: TimeInterval
    let pollInterval: Duration

    init(
        client: AppClient,
        logger: Logger,
        timeout: TimeInterval = 10,
        pollInterval: Duration = .milliseconds(100)
    ) {
        self.client = client
        self.logger = logger
        self.timeout = timeout
        self.pollInterval = pollInterval
    }

    func quit(
        target: AppQuitTarget,
        force: Bool
    ) async throws -> AppQuitData {
        logger.log("resolving running application target")
        let runningApplications = try await client.runningApplications(true)
        let matchedApplications = try matchingApplications(
            for: target,
            in: runningApplications
        ).sorted(by: appSortsBefore)
        logger.log("\(force ? "force quitting" : "quitting") \(matchedApplications.count) application(s)")
        let requestedApplications = matchedApplications.map { application in
            RequestedApplication(
                application: application,
                requestAccepted: mainThread {
                    force ? application.handle.forceTerminate() : application.handle.terminate()
                }
            )
        }
        await waitUntilTerminated(requestedApplications)
        return AppQuitData(
            apps: requestedApplications.map { requested in
                let terminated = mainThread { requested.application.handle.isTerminated }
                return AppQuitData.App(
                    name: requested.application.name,
                    bundleId: requested.application.bundleId,
                    path: requested.application.path,
                    pid: requested.application.pid,
                    terminated: terminated,
                    message: quitMessage(
                        terminated: terminated,
                        requestAccepted: requested.requestAccepted,
                        force: force
                    )
                )
            },
            forced: force
        )
    }

    private func matchingApplications(
        for target: AppQuitTarget,
        in applications: [AppRuntimeApplication]
    ) throws -> [AppRuntimeApplication] {
        switch target {
        case .app(let name):
            let matches = applications.filter {
                $0.name.compare(name, options: [.caseInsensitive]) == .orderedSame
            }
            guard !matches.isEmpty else {
                throw AppQuitError.appNotRunning("application not running: \(name)")
            }
            return matches
        case .pid(let pid):
            guard let match = applications.first(where: { $0.pid == pid }) else {
                throw AppQuitError.appNotRunning("application not running with pid \(pid)")
            }
            return [match]
        }
    }

    private func waitUntilTerminated(_ applications: [RequestedApplication]) async {
        let deadline = Date().addingTimeInterval(timeout)
        while applications.contains(where: { application in
            !mainThread { application.application.handle.isTerminated }
        }) {
            if Date() >= deadline {
                return
            }
            try? await Task.sleep(for: pollInterval)
        }
    }

    private func quitMessage(
        terminated: Bool,
        requestAccepted: Bool,
        force: Bool
    ) -> String? {
        guard !terminated else {
            return nil
        }
        if requestAccepted {
            return force
                ? "application did not terminate within \(Int(timeout)) seconds"
                : "application did not quit within \(Int(timeout)) seconds"
        }
        return force
            ? "failed to force terminate application"
            : "failed to request application quit"
    }
}

struct AppListService {
    let client: AppClient

    func list(includeAccessory: Bool) async throws -> AppListData {
        let apps = try await client.runningApplications(includeAccessory).map(\.listEntry)
        return AppListData(
            apps: apps.sorted {
                appSortsBefore($0, $1)
            }
        )
    }
}

enum LiveAppSystem {
    static func runningApplications(includeAccessory: Bool) throws -> [AppRuntimeApplication] {
        mainThread {
            NSWorkspace.shared.runningApplications.compactMap { application in
                guard shouldListApplication(
                    isTerminated: application.isTerminated,
                    activationPolicy: application.activationPolicy,
                    includeAccessory: includeAccessory
                ) else {
                    return nil
                }
                return AppRuntimeApplication(handle: application)
            }
        }
    }

    static func shouldListApplication(
        isTerminated: Bool,
        activationPolicy: NSApplication.ActivationPolicy,
        includeAccessory: Bool
    ) -> Bool {
        guard !isTerminated else {
            return false
        }
        switch activationPolicy {
        case .regular:
            return true
        case .accessory:
            return includeAccessory
        case .prohibited:
            return false
        @unknown default:
            return false
        }
    }

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
        let emptyLaunch = AppLaunchError.launchFailed("launch returned no application")
        if openTargets.isEmpty {
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.main.async {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = activates
                    NSWorkspace.shared.openApplication(
                        at: appURL,
                        configuration: configuration
                    ) { application, error in
                        if let application {
                            continuation.resume(returning: application)
                            return
                        }
                        continuation.resume(throwing: error ?? emptyLaunch)
                    }
                }
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = activates
                NSWorkspace.shared.open(
                    openTargets,
                    withApplicationAt: appURL,
                    configuration: configuration
                ) { application, error in
                    if let application {
                        continuation.resume(returning: application)
                        return
                    }
                    continuation.resume(throwing: error ?? emptyLaunch)
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

private func appSortsBefore(_ lhs: AppRuntimeApplication, _ rhs: AppRuntimeApplication) -> Bool {
    let lhsName = lhs.name.lowercased()
    let rhsName = rhs.name.lowercased()
    if lhsName != rhsName {
        return lhsName < rhsName
    }

    let lhsBundleId = lhs.bundleId ?? ""
    let rhsBundleId = rhs.bundleId ?? ""
    if lhsBundleId != rhsBundleId {
        return lhsBundleId < rhsBundleId
    }

    let lhsPath = lhs.path ?? ""
    let rhsPath = rhs.path ?? ""
    if lhsPath != rhsPath {
        return lhsPath < rhsPath
    }

    return lhs.pid < rhs.pid
}

private func appSortsBefore(_ lhs: AppListEntry, _ rhs: AppListEntry) -> Bool {
    let lhsName = lhs.name.lowercased()
    let rhsName = rhs.name.lowercased()
    if lhsName != rhsName {
        return lhsName < rhsName
    }

    let lhsBundleId = lhs.bundleId ?? ""
    let rhsBundleId = rhs.bundleId ?? ""
    if lhsBundleId != rhsBundleId {
        return lhsBundleId < rhsBundleId
    }

    let lhsPath = lhs.path ?? ""
    let rhsPath = rhs.path ?? ""
    if lhsPath != rhsPath {
        return lhsPath < rhsPath
    }

    return lhs.pid < rhs.pid
}

private func mainThread<T>(_ body: () throws -> T) rethrows -> T {
    if Thread.isMainThread {
        return try body()
    }
    return try DispatchQueue.main.sync(execute: body)
}
