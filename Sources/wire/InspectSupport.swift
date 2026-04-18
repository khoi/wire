@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import CryptoKit
import Foundation

enum InspectTarget: Equatable {
    case frontmost
    case app(String)
}

struct InspectClient {
    typealias Capture = (_ target: InspectTarget) async throws -> CapturedInspection

    var capture: Capture

    static func live() -> InspectClient {
        InspectClient(
            capture: { target in
                try LiveInspectSystem.capture(target: target)
            }
        )
    }
}

struct CapturedInspection: Equatable {
    struct App: Equatable {
        let name: String
        let bundleId: String?
        let pid: Int32
        let focused: Bool
    }

    struct Window: Equatable {
        let id: Int32
        let title: String?
        let frame: CGRect
    }

    struct Element: Equatable {
        let role: String
        let name: String
        let value: String?
        let enabled: Bool?
        let screenFrame: CGRect?
        let resolver: InspectElementResolver
    }

    let app: App
    let window: Window
    let imageData: Data
    let elements: [Element]
}

struct InspectElementResolver: Codable, Equatable {
    let appName: String
    let appBundleId: String?
    let appPID: Int32
    let windowID: Int32
    let windowTitle: String?
    let windowFrame: CGRect
    let path: [Int]
    let rawRole: String
    let rawTitle: String?
    let rawDescription: String?
    let rawValue: String?
    let screenFrame: CGRect?
    let actions: [String]
    let valueSettable: Bool
}

struct InspectData: Codable, Equatable {
    struct App: Codable, Equatable {
        let name: String
        let bundleId: String?
        let pid: Int32
        let focused: Bool
    }

    struct Element: Codable, Equatable {
        let id: String
        let role: String
        let name: String
        let value: String?
        let enabled: Bool?
        let frame: CGRect?
    }

    let app: App
    let imagePath: String
    let elements: [Element]

    func plainText(snapshot: String) -> String {
        var lines = [
            "\(app.name) pid \(app.pid)",
            "snapshot: \(snapshot)",
            "image: \(imagePath)",
            "focused: \(app.focused ? "yes" : "no")",
        ]
        if let bundleId = app.bundleId {
            lines.append(bundleId)
        }
        lines.append(contentsOf: elements.map { element in
            var parts = [element.id, element.role, element.name]
            if let value = element.value, !value.isEmpty {
                parts.append("value=\(value)")
            }
            if let enabled = element.enabled {
                parts.append("enabled=\(enabled ? "yes" : "no")")
            }
            return parts.joined(separator: "\t")
        })
        return lines.joined(separator: "\n")
    }
}

struct StoredInspectSnapshot: Codable, Equatable {
    struct Window: Codable, Equatable {
        let id: Int32
        let title: String?
        let frame: CGRect
    }

    struct Element: Codable, Equatable {
        let id: String
        let role: String
        let name: String
        let value: String?
        let enabled: Bool?
        let frame: CGRect?
        let resolver: InspectElementResolver

        var publicElement: InspectData.Element {
            InspectData.Element(
                id: id,
                role: role,
                name: name,
                value: value,
                enabled: enabled,
                frame: frame
            )
        }
    }

    let snapshot: String
    let createdAt: Date
    let app: InspectData.App
    let window: Window
    let imagePath: String
    let elements: [Element]

    var data: InspectData {
        InspectData(
            app: app,
            imagePath: imagePath,
            elements: elements.map(\.publicElement)
        )
    }

    func plainText() -> String {
        data.plainText(snapshot: snapshot)
    }
}

enum InspectError: WireError {
    case invalidTarget(String)
    case missingPermission(PermissionKind)
    case appNotRunning(String)
    case ambiguousTarget(String)
    case windowNotFound(String)
    case captureFailed(String)
    case snapshotStoreFailed(String)

    var code: String {
        switch self {
        case .invalidTarget:
            return "invalid_app_target"
        case .missingPermission(.accessibility):
            return "accessibility_permission_required"
        case .missingPermission(.screenRecording):
            return "screen_recording_permission_required"
        case .appNotRunning:
            return "app_not_running"
        case .ambiguousTarget:
            return "ambiguous_app_target"
        case .windowNotFound:
            return "inspect_window_not_found"
        case .captureFailed:
            return "inspect_capture_failed"
        case .snapshotStoreFailed:
            return "snapshot_store_failed"
        }
    }

    var message: String {
        switch self {
        case .invalidTarget(let message),
             .appNotRunning(let message),
             .ambiguousTarget(let message),
             .windowNotFound(let message),
             .captureFailed(let message),
             .snapshotStoreFailed(let message):
            return message
        case .missingPermission(.accessibility):
            return "accessibility permission is required"
        case .missingPermission(.screenRecording):
            return "screen-recording permission is required"
        }
    }

    var exitCode: Int32 {
        1
    }
}

struct InspectService {
    let permissions: PermissionsClient
    let client: InspectClient
    let logger: Logger
    let currentDirectoryPath: String
    let stateDirectoryPath: String

    func inspect(target: InspectTarget) async throws -> StoredInspectSnapshot {
        let permissionsService = PermissionsService(client: permissions, logger: logger)
        let statuses = try permissionsService.status()
        let granted = Dictionary(uniqueKeysWithValues: statuses.permissions.map { ($0.kind, $0.granted) })
        guard granted[.accessibility] == true else {
            throw InspectError.missingPermission(.accessibility)
        }
        guard granted[.screenRecording] == true else {
            throw InspectError.missingPermission(.screenRecording)
        }

        logger.log("capturing inspection snapshot")
        let capturedInspection = try await client.capture(target)
        let store = SnapshotStore(
            stateDirectoryPath: stateDirectoryPath,
            currentDirectoryPath: currentDirectoryPath
        )
        do {
            return try store.store(capturedInspection)
        } catch let error as InspectError {
            throw error
        } catch {
            throw InspectError.snapshotStoreFailed(
                "failed to store snapshot: \(String(describing: error))"
            )
        }
    }
}

struct SnapshotStore {
    struct LatestPointer: Codable {
        let snapshot: String
    }

    struct SnapshotDirectoryEntry {
        let snapshot: String
        let number: Int
        let url: URL
        let createdAt: Date
    }

    let stateDirectoryPath: String
    let currentDirectoryPath: String
    let now: () -> Date
    let retentionCount: Int
    let ttl: TimeInterval

    init(
        stateDirectoryPath: String,
        currentDirectoryPath: String,
        now: @escaping () -> Date = Date.init,
        retentionCount: Int = 5,
        ttl: TimeInterval = 600
    ) {
        self.stateDirectoryPath = stateDirectoryPath
        self.currentDirectoryPath = currentDirectoryPath
        self.now = now
        self.retentionCount = retentionCount
        self.ttl = ttl
    }

    func store(_ inspection: CapturedInspection) throws -> StoredInspectSnapshot {
        let existingEntries = try cleanup()
        let snapshotID = nextSnapshotID(from: existingEntries)
        let snapshotURL = bucketSnapshotsURL().appendingPathComponent(snapshotID)
        try FileManager.default.createDirectory(at: snapshotURL, withIntermediateDirectories: true)

        let createdAt = now()
        let storedElements = storedElements(from: inspection)
        let imagePath = snapshotURL.appendingPathComponent("image.png")
        try inspection.imageData.write(to: imagePath, options: .atomic)

        let snapshot = StoredInspectSnapshot(
            snapshot: snapshotID,
            createdAt: createdAt,
            app: .init(
                name: inspection.app.name,
                bundleId: inspection.app.bundleId,
                pid: inspection.app.pid,
                focused: inspection.app.focused
            ),
            window: .init(
                id: inspection.window.id,
                title: inspection.window.title,
                frame: inspection.window.frame
            ),
            imagePath: imagePath.path,
            elements: storedElements
        )

        try writeJSON(
            snapshot,
            to: snapshotURL.appendingPathComponent("snapshot.json")
        )
        try writeJSON(
            LatestPointer(snapshot: snapshotID),
            to: latestPointerURL()
        )
        _ = try cleanup()
        return snapshot
    }

    func load(snapshotID: String) throws -> StoredInspectSnapshot? {
        let entries = try cleanup()
        guard entries.contains(where: { $0.snapshot == snapshotID }) else {
            return nil
        }
        return try readSnapshot(at: snapshotURL(for: snapshotID))
    }

    func latestSnapshotID() throws -> String? {
        let entries = try cleanup()
        guard !entries.isEmpty else {
            return nil
        }
        if let pointer = try readLatestPointer(),
           entries.contains(where: { $0.snapshot == pointer.snapshot })
        {
            return pointer.snapshot
        }
        return entries.sorted { snapshotSortsBefore($0, $1) }.first?.snapshot
    }

    private func storedElements(from inspection: CapturedInspection) -> [StoredInspectSnapshot.Element] {
        let sorted = inspection.elements
            .compactMap { candidate in
                let publicFrame = candidate.screenFrame.map {
                    windowRelativeFrame($0, in: inspection.window.frame)
                }
                return StoredInspectSnapshot.Element(
                    id: "",
                    role: candidate.role,
                    name: candidate.name,
                    value: candidate.value,
                    enabled: candidate.enabled,
                    frame: publicFrame,
                    resolver: candidate.resolver
                )
            }
            .sorted { lhs, rhs in
                inspectElementSortsBefore(lhs, rhs)
            }

        var deduplicated: [StoredInspectSnapshot.Element] = []
        var seen = Set<String>()
        for element in sorted {
            let key = dedupeKey(for: element)
            guard seen.insert(key).inserted else {
                continue
            }
            deduplicated.append(element)
        }

        return deduplicated.enumerated().map { index, element in
            StoredInspectSnapshot.Element(
                id: "@e\(index + 1)",
                role: element.role,
                name: element.name,
                value: element.value,
                enabled: element.enabled,
                frame: element.frame,
                resolver: element.resolver
            )
        }
    }

    private func dedupeKey(for element: StoredInspectSnapshot.Element) -> String {
        let frame = element.frame.map {
            [
                Int($0.origin.x.rounded()),
                Int($0.origin.y.rounded()),
                Int($0.size.width.rounded()),
                Int($0.size.height.rounded()),
            ]
            .map(String.init)
            .joined(separator: ":")
        } ?? "-"
        return [element.role, element.name, element.value ?? "-", frame].joined(separator: "|")
    }

    private func nextSnapshotID(from entries: [SnapshotDirectoryEntry]) -> String {
        let next = (entries.map(\.number).max() ?? 0) + 1
        return "s\(next)"
    }

    private func cleanup() throws -> [SnapshotDirectoryEntry] {
        let fileManager = FileManager.default
        let snapshotsURL = bucketSnapshotsURL()
        try fileManager.createDirectory(at: snapshotsURL, withIntermediateDirectories: true)

        let cutoff = now().addingTimeInterval(-ttl)
        let entries = try listSnapshotEntries()
        var retained = entries

        for entry in entries where entry.createdAt < cutoff {
            try? fileManager.removeItem(at: entry.url)
            retained.removeAll { $0.snapshot == entry.snapshot }
        }

        retained.sort { snapshotSortsBefore($0, $1) }
        if retained.count > retentionCount {
            for entry in retained.dropFirst(retentionCount) {
                try? fileManager.removeItem(at: entry.url)
            }
            retained = Array(retained.prefix(retentionCount))
        }

        if let latest = retained.first {
            try writeJSON(
                LatestPointer(snapshot: latest.snapshot),
                to: latestPointerURL()
            )
        } else if fileManager.fileExists(atPath: latestPointerURL().path) {
            try? fileManager.removeItem(at: latestPointerURL())
        }

        return retained
    }

    private func listSnapshotEntries() throws -> [SnapshotDirectoryEntry] {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: bucketSnapshotsURL(),
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        )

        return contents.compactMap { url in
            guard url.hasDirectoryPath else {
                return nil
            }
            let name = url.lastPathComponent
            guard name.hasPrefix("s"),
                  let number = Int(name.dropFirst())
            else {
                return nil
            }
            let createdAt = (try? readSnapshot(at: url.appendingPathComponent("snapshot.json")).createdAt)
                ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
                ?? .distantPast
            return SnapshotDirectoryEntry(
                snapshot: name,
                number: number,
                url: url,
                createdAt: createdAt
            )
        }
    }

    private func latestPointerURL() -> URL {
        bucketURL().appendingPathComponent("latest.json")
    }

    private func bucketSnapshotsURL() -> URL {
        bucketURL().appendingPathComponent("snapshots")
    }

    private func snapshotURL(for snapshotID: String) -> URL {
        bucketSnapshotsURL().appendingPathComponent(snapshotID).appendingPathComponent("snapshot.json")
    }

    private func bucketURL() -> URL {
        let root = URL(fileURLWithPath: stateDirectoryPath, isDirectory: true)
            .standardizedFileURL
            .appendingPathComponent("wire", isDirectory: true)
            .appendingPathComponent(snapshotBucketName(for: currentDirectoryPath), isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func snapshotBucketName(for path: String) -> String {
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let digest = SHA256.hash(data: Data(standardizedPath.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func readLatestPointer() throws -> LatestPointer? {
        let url = latestPointerURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try JSONDecoder().decode(LatestPointer.self, from: Data(contentsOf: url))
    }

    private func readSnapshot(at url: URL) throws -> StoredInspectSnapshot {
        try JSONDecoder().decode(StoredInspectSnapshot.self, from: Data(contentsOf: url))
    }

    private func writeJSON<Value: Encodable>(_ value: Value, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func windowRelativeFrame(_ frame: CGRect, in windowFrame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX - windowFrame.minX,
            y: windowFrame.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }
}

enum LiveInspectSystem {
    private struct VisibleWindow {
        let id: Int32
        let title: String?
        let frame: CGRect
        let ownerPID: Int32
        let order: Int
    }

    private struct AXWindowDescriptor {
        let element: AXUIElement
        let title: String?
        let frame: CGRect?
    }

    private struct ElementCandidate {
        let role: String
        let name: String
        let value: String?
        let enabled: Bool?
        let screenFrame: CGRect?
        let resolver: InspectElementResolver
    }

    private struct TraversalContext {
        let app: ResolvedApplication
        let window: VisibleWindow
    }

    static func capture(target: InspectTarget) throws -> CapturedInspection {
        let application = try resolveApplication(target: target)
        let window = try resolveWindow(for: application)
        let imageData = try captureWindowImage(windowID: CGWindowID(window.id))
        let appElement = AXUIElementCreateApplication(application.processID)
        let windowElement = try resolveWindowElement(
            for: appElement,
            matching: window
        )
        let candidates = try collectCandidates(
            root: windowElement,
            app: application,
            window: window
        )
        return CapturedInspection(
            app: .init(
                name: application.name,
                bundleId: application.bundleId,
                pid: application.pid,
                focused: application.focused
            ),
            window: .init(
                id: window.id,
                title: window.title,
                frame: window.frame
            ),
            imageData: imageData,
            elements: candidates.map {
                CapturedInspection.Element(
                    role: publicRole(for: $0.role, actions: $0.resolver.actions),
                    name: $0.name,
                    value: $0.value,
                    enabled: $0.enabled,
                    screenFrame: $0.screenFrame,
                    resolver: $0.resolver
                )
            }
        )
    }

    private static func resolveApplication(target: InspectTarget) throws -> ResolvedApplication {
        let frontmostPID = runOnMainThread {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
        let running: [ResolvedApplication] = runOnMainThread {
            NSWorkspace.shared.runningApplications.compactMap { application -> ResolvedApplication? in
                guard LiveAppSystem.shouldListApplication(
                    isTerminated: application.isTerminated,
                    activationPolicy: application.activationPolicy,
                    includeAccessory: true
                ) else {
                    return nil
                }
                return ResolvedApplication(
                    name: application.localizedName
                        ?? application.bundleURL?.deletingPathExtension().lastPathComponent
                        ?? application.bundleIdentifier
                        ?? "Unknown",
                    bundleId: application.bundleIdentifier,
                    pid: application.processIdentifier,
                    focused: application.processIdentifier == frontmostPID
                )
            }
        }

        switch target {
        case .frontmost:
            guard let frontmost = running.first(where: { $0.focused }) else {
                throw InspectError.captureFailed("frontmost application not found")
            }
            return frontmost
        case .app(let name):
            let matches = running.filter {
                $0.name.compare(name, options: String.CompareOptions.caseInsensitive) == .orderedSame
            }
            guard !matches.isEmpty else {
                throw InspectError.appNotRunning("application not running: \(name)")
            }
            if matches.count == 1 {
                return matches[0]
            }
            let visibleWindowPIDs = Set(visibleWindows().map(\.ownerPID))
            let visibleMatches = matches.filter { visibleWindowPIDs.contains($0.pid) }
            if visibleMatches.count == 1 {
                return visibleMatches[0]
            }
            if let frontmostMatch = matches.first(where: { $0.focused }) {
                return frontmostMatch
            }
            throw InspectError.ambiguousTarget("multiple running applications matched \(name)")
        }
    }

    private static func resolveWindow(for application: ResolvedApplication) throws -> VisibleWindow {
        let windows = visibleWindows().filter { $0.ownerPID == application.pid }
        guard !windows.isEmpty else {
            throw InspectError.windowNotFound("no visible window found for \(application.name)")
        }

        let appElement = AXUIElementCreateApplication(application.processID)
        if let focused = try matchingVisibleWindow(
            descriptor: try windowDescriptor(
                appElement: appElement,
                attribute: kAXFocusedWindowAttribute as CFString
            ),
            in: windows
        ) {
            return focused
        }
        if let main = try matchingVisibleWindow(
            descriptor: try windowDescriptor(
                appElement: appElement,
                attribute: kAXMainWindowAttribute as CFString
            ),
            in: windows
        ) {
            return main
        }
        return windows.sorted { $0.order < $1.order }[0]
    }

    private static func resolveWindowElement(
        for appElement: AXUIElement,
        matching window: VisibleWindow
    ) throws -> AXUIElement {
        let descriptors = try windowDescriptors(appElement: appElement)
        if let matched = bestMatchingDescriptor(in: descriptors, window: window) {
            return matched.element
        }
        if let focused = try windowDescriptor(appElement: appElement, attribute: kAXFocusedWindowAttribute as CFString),
           windowScore(descriptor: focused, window: window) > 0 {
            return focused.element
        }
        if let main = try windowDescriptor(appElement: appElement, attribute: kAXMainWindowAttribute as CFString),
           windowScore(descriptor: main, window: window) > 0 {
            return main.element
        }
        throw InspectError.windowNotFound("failed to resolve accessibility window")
    }

    private static func collectCandidates(
        root: AXUIElement,
        app: ResolvedApplication,
        window: VisibleWindow
    ) throws -> [ElementCandidate] {
        var visited = Set<CFHashCode>()
        var candidates: [ElementCandidate] = []
        try traverse(
            element: root,
            path: [],
            context: .init(app: app, window: window),
            visited: &visited,
            candidates: &candidates
        )
        return candidates
    }

    private static func traverse(
        element: AXUIElement,
        path: [Int],
        context: TraversalContext,
        visited: inout Set<CFHashCode>,
        candidates: inout [ElementCandidate]
    ) throws {
        let hash = CFHash(element)
        guard visited.insert(hash).inserted else {
            return
        }

        let rawRole = try stringAttribute(element, attribute: kAXRoleAttribute as CFString) ?? "AXUnknown"
        let rawTitle = try stringAttribute(element, attribute: kAXTitleAttribute as CFString)
        let rawDescription = try stringAttribute(element, attribute: kAXDescriptionAttribute as CFString)
        let rawValue = try stringValueAttribute(element, attribute: kAXValueAttribute as CFString)
        let enabled = try boolAttribute(element, attribute: kAXEnabledAttribute as CFString)
        let screenFrame = try frameAttribute(element)
        let actions = try actionNames(element)
        let valueSettable = try isValueSettable(element)
        let name = displayName(
            role: rawRole,
            title: rawTitle,
            description: rawDescription,
            value: rawValue
        )

        if shouldIncludeElement(role: rawRole, actions: actions, name: name) {
            candidates.append(
                ElementCandidate(
                    role: rawRole,
                    name: name,
                    value: publicValue(name: name, rawValue: rawValue),
                    enabled: enabled,
                    screenFrame: screenFrame,
                    resolver: .init(
                        appName: context.app.name,
                        appBundleId: context.app.bundleId,
                        appPID: context.app.pid,
                        windowID: context.window.id,
                        windowTitle: context.window.title,
                        windowFrame: context.window.frame,
                        path: path,
                        rawRole: rawRole,
                        rawTitle: rawTitle,
                        rawDescription: rawDescription,
                        rawValue: rawValue,
                        screenFrame: screenFrame,
                        actions: actions,
                        valueSettable: valueSettable
                    )
                )
            )
        }

        for (index, child) in try children(of: element).enumerated() {
            try traverse(
                element: child,
                path: path + [index],
                context: context,
                visited: &visited,
                candidates: &candidates
            )
        }
    }

    private static func visibleWindows() -> [VisibleWindow] {
        guard let values = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return values.enumerated().compactMap { index, value in
            guard let windowID = value[kCGWindowNumber as String] as? Int,
                  let ownerPID = value[kCGWindowOwnerPID as String] as? Int,
                  let layer = value[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let boundsValue = value[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: boundsValue as CFDictionary),
                  frame.width > 1,
                  frame.height > 1
            else {
                return nil
            }

            if let alpha = value[kCGWindowAlpha as String] as? Double, alpha <= 0 {
                return nil
            }

            return VisibleWindow(
                id: Int32(windowID),
                title: value[kCGWindowName as String] as? String,
                frame: frame,
                ownerPID: Int32(ownerPID),
                order: index
            )
        }
    }

    private static func windowDescriptor(
        appElement: AXUIElement,
        attribute: CFString
    ) throws -> AXWindowDescriptor? {
        guard let windowElement = try elementAttribute(appElement, attribute: attribute) else {
            return nil
        }
        return AXWindowDescriptor(
            element: windowElement,
            title: try stringAttribute(windowElement, attribute: kAXTitleAttribute as CFString),
            frame: try frameAttribute(windowElement)
        )
    }

    private static func windowDescriptors(appElement: AXUIElement) throws -> [AXWindowDescriptor] {
        try childrenAttribute(appElement, attribute: kAXWindowsAttribute as CFString).map { element in
            AXWindowDescriptor(
                element: element,
                title: try stringAttribute(element, attribute: kAXTitleAttribute as CFString),
                frame: try frameAttribute(element)
            )
        }
    }

    private static func matchingVisibleWindow(
        descriptor: AXWindowDescriptor?,
        in windows: [VisibleWindow]
    ) throws -> VisibleWindow? {
        guard let descriptor else {
            return nil
        }
        return windows
            .map { ($0, windowScore(descriptor: descriptor, window: $0)) }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.order < rhs.0.order
                }
                return lhs.1 > rhs.1
            }
            .first?
            .0
    }

    private static func bestMatchingDescriptor(
        in descriptors: [AXWindowDescriptor],
        window: VisibleWindow
    ) -> AXWindowDescriptor? {
        descriptors
            .map { ($0, windowScore(descriptor: $0, window: window)) }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                lhs.1 > rhs.1
            }
            .first?
            .0
    }

    private static func windowScore(
        descriptor: AXWindowDescriptor,
        window: VisibleWindow
    ) -> Int {
        var score = 0
        if let frame = descriptor.frame,
           frameDistance(frame, window.frame) < 12
        {
            score += 10
        }
        if let title = descriptor.title?.lowercased(),
           let windowTitle = window.title?.lowercased(),
           !title.isEmpty,
           title == windowTitle
        {
            score += 5
        }
        return score
    }

    private static func frameDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.origin.x - rhs.origin.x)
            + abs(lhs.origin.y - rhs.origin.y)
            + abs(lhs.size.width - rhs.size.width)
            + abs(lhs.size.height - rhs.size.height)
    }

    private static func captureWindowImage(windowID: CGWindowID) throws -> Data {
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.bestResolution]
        ) else {
            throw InspectError.captureFailed("failed to capture window image")
        }
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw InspectError.captureFailed("failed to encode window image")
        }
        return data
    }

    private static func shouldIncludeElement(
        role: String,
        actions: [String],
        name: String
    ) -> Bool {
        let publicRole = publicRole(for: role, actions: actions)
        switch publicRole {
        case "button", "text-field", "link", "checkbox", "radio-button", "slider", "menu-item":
            return true
        case "text":
            return !name.isEmpty
        default:
            return false
        }
    }

    private static func publicRole(for rawRole: String, actions: [String]) -> String {
        switch rawRole {
        case "AXButton", "AXMenuButton", "AXPopUpButton", "AXDisclosureTriangle":
            return "button"
        case "AXTextField", "AXTextArea", "AXSecureTextField", "AXSearchField", "AXComboBox":
            return "text-field"
        case "AXLink":
            return "link"
        case "AXCheckBox":
            return "checkbox"
        case "AXRadioButton":
            return "radio-button"
        case "AXSlider":
            return "slider"
        case "AXMenuItem", "AXMenuBarItem":
            return "menu-item"
        case "AXStaticText":
            return "text"
        default:
            return actions.contains("AXPress") ? "button" : "other"
        }
    }

    private static func displayName(
        role: String,
        title: String?,
        description: String?,
        value: String?
    ) -> String {
        let preferred = [title, description].compactMap { text in
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        if let first = preferred.first {
            return first
        }
        if role == "AXStaticText" || role == "AXTextField" || role == "AXTextArea" || role == "AXSecureTextField" {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }

    private static func publicValue(name: String, rawValue: String?) -> String? {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, trimmed != name else {
            return nil
        }
        return trimmed
    }

    private static func stringAttribute(
        _ element: AXUIElement,
        attribute: CFString
    ) throws -> String? {
        guard let value = try attributeValue(element, attribute: attribute) else {
            return nil
        }
        if let string = value as? String {
            return string
        }
        if let string = value as? NSString {
            return string as String
        }
        return nil
    }

    private static func stringValueAttribute(
        _ element: AXUIElement,
        attribute: CFString
    ) throws -> String? {
        guard let value = try attributeValue(element, attribute: attribute) else {
            return nil
        }
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func boolAttribute(
        _ element: AXUIElement,
        attribute: CFString
    ) throws -> Bool? {
        guard let value = try attributeValue(element, attribute: attribute) else {
            return nil
        }
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return nil
    }

    private static func frameAttribute(_ element: AXUIElement) throws -> CGRect? {
        guard let positionValue = try attributeValue(element, attribute: kAXPositionAttribute as CFString),
              let sizeValue = try attributeValue(element, attribute: kAXSizeAttribute as CFString),
              let positionAXValue = axValue(positionValue),
              let sizeAXValue = axValue(sizeValue)
        else {
            return nil
        }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetType(positionAXValue) == .cgPoint,
              AXValueGetValue(positionAXValue, .cgPoint, &point),
              AXValueGetType(sizeAXValue) == .cgSize,
              AXValueGetValue(sizeAXValue, .cgSize, &size)
        else {
            return nil
        }
        return CGRect(origin: point, size: size)
    }

    private static func actionNames(_ element: AXUIElement) throws -> [String] {
        var names: CFArray?
        let error = AXUIElementCopyActionNames(element, &names)
        switch error {
        case .success:
            if let names = names as? [String] {
                return names
            }
            return []
        case .attributeUnsupported, .noValue:
            return []
        default:
            throw InspectError.captureFailed("failed to read accessibility actions")
        }
    }

    private static func isValueSettable(_ element: AXUIElement) throws -> Bool {
        var settable = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        switch error {
        case .success:
            return settable.boolValue
        case .attributeUnsupported:
            return false
        default:
            throw InspectError.captureFailed("failed to read accessibility mutability")
        }
    }

    private static func children(of element: AXUIElement) throws -> [AXUIElement] {
        try childrenAttribute(element, attribute: kAXChildrenAttribute as CFString)
    }

    private static func childrenAttribute(
        _ element: AXUIElement,
        attribute: CFString
    ) throws -> [AXUIElement] {
        guard let value = try attributeValue(element, attribute: attribute) else {
            return []
        }
        if let array = value as? [AnyObject] {
            return array.compactMap(axUIElement)
        }
        if let array = value as? NSArray {
            return array.compactMap { value in
                guard let value = value as AnyObject? else {
                    return nil
                }
                return axUIElement(value)
            }
        }
        return []
    }

    private static func elementAttribute(
        _ element: AXUIElement,
        attribute: CFString
    ) throws -> AXUIElement? {
        guard let value = try attributeValue(element, attribute: attribute) else {
            return nil
        }
        return axUIElement(value)
    }

    private static func attributeValue(
        _ element: AXUIElement,
        attribute: CFString
    ) throws -> AnyObject? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        switch error {
        case .success:
            return value
        case .noValue, .attributeUnsupported:
            return nil
        default:
            throw InspectError.captureFailed(
                "failed to read accessibility attribute \(attribute as String)"
            )
        }
    }

    private static func axValue(_ value: AnyObject) -> AXValue? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXValue.self)
    }

    private static func axUIElement(_ value: AnyObject) -> AXUIElement? {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
}

private struct ResolvedApplication {
    let name: String
    let bundleId: String?
    let pid: Int32
    let focused: Bool

    var processID: Darwin.pid_t {
        Darwin.pid_t(pid)
    }
}

private func inspectElementSortsBefore(
    _ lhs: StoredInspectSnapshot.Element,
    _ rhs: StoredInspectSnapshot.Element
) -> Bool {
    switch (lhs.frame, rhs.frame) {
    case let (.some(lhsFrame), .some(rhsFrame)):
        if abs(lhsFrame.origin.y - rhsFrame.origin.y) >= 1 {
            return lhsFrame.origin.y < rhsFrame.origin.y
        }
        if abs(lhsFrame.origin.x - rhsFrame.origin.x) >= 1 {
            return lhsFrame.origin.x < rhsFrame.origin.x
        }
    case (.some, nil):
        return true
    case (nil, .some):
        return false
    case (nil, nil):
        break
    }

    if lhs.role != rhs.role {
        return lhs.role < rhs.role
    }
    if lhs.name != rhs.name {
        return lhs.name < rhs.name
    }
    return (lhs.value ?? "") < (rhs.value ?? "")
}

private func snapshotSortsBefore(
    _ lhs: SnapshotStore.SnapshotDirectoryEntry,
    _ rhs: SnapshotStore.SnapshotDirectoryEntry
) -> Bool {
    if lhs.number != rhs.number {
        return lhs.number > rhs.number
    }
    return lhs.createdAt > rhs.createdAt
}

private func runOnMainThread<T>(_ body: () throws -> T) rethrows -> T {
    if Thread.isMainThread {
        return try body()
    }
    return try DispatchQueue.main.sync(execute: body)
}
