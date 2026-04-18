@preconcurrency import ApplicationServices
import Foundation

enum ClickTarget: Equatable {
    case reference(String)
    case query(ClickQuery)

    init(parsing input: String) throws {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ClickError.invalidTarget("click target cannot be empty")
        }
        if ClickTarget.isReference(trimmed) {
            self = .reference(trimmed)
            return
        }
        self = .query(try ClickQuery(parsing: trimmed))
    }

    private static func isReference(_ value: String) -> Bool {
        guard value.hasPrefix("@e"), value.count > 2 else {
            return false
        }
        return value.dropFirst(2).allSatisfy(\.isNumber)
    }
}

struct ClickQuery: Equatable {
    let role: String?
    let name: String

    init(role: String?, name: String) {
        self.role = role
        self.name = name
    }

    init(parsing input: String) throws {
        if let query = ClickQuery.parseScopedQuery(input) {
            self = query
            return
        }
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw ClickError.invalidTarget("click target cannot be empty")
        }
        self = ClickQuery(role: nil, name: name)
    }

    private static func parseScopedQuery(_ input: String) -> ClickQuery? {
        guard let colonIndex = input.firstIndex(of: ":") else {
            return nil
        }
        let role = input[..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let remainder = input[input.index(after: colonIndex)...]
        guard remainder.first == "\"", remainder.last == "\"", remainder.count >= 2 else {
            return nil
        }
        let name = remainder
            .dropFirst()
            .dropLast()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !role.isEmpty, !name.isEmpty else {
            return nil
        }
        return ClickQuery(role: role, name: name)
    }
}

struct ClickClient {
    typealias Perform = (
        _ snapshotID: String,
        _ element: StoredInspectSnapshot.Element,
        _ right: Bool
    ) async throws -> Void

    var perform: Perform

    static func live() -> ClickClient {
        ClickClient(
            perform: { _, element, right in
                try LiveInspectSystem.click(element: element, right: right)
            }
        )
    }
}

struct ClickData: Codable, Equatable {
    struct Clicked: Codable, Equatable {
        let id: String
        let role: String
        let name: String
    }

    let snapshot: String
    let clicked: Clicked
    let right: Bool

    func plainText() -> String {
        "\(right ? "right-clicked" : "clicked") \(clicked.id) \(clicked.role) \(clicked.name) (\(snapshot))"
    }
}

enum ClickError: WireError {
    case invalidTarget(String)
    case missingPermission(PermissionKind)
    case noSnapshotAvailable(String)
    case snapshotNotFound(String)
    case elementNotFound(String)
    case ambiguousQuery(String)
    case staleRef(String)
    case elementNotClickable(String)
    case elementActionFailed(String)
    case targetNotFrontmost(String)
    case elementGeometryUnavailable(String)

    var code: String {
        switch self {
        case .invalidTarget:
            return "invalid_click_target"
        case .missingPermission(.accessibility):
            return "accessibility_permission_required"
        case .missingPermission(.screenRecording):
            return "screen_recording_permission_required"
        case .noSnapshotAvailable:
            return "no_snapshot_available"
        case .snapshotNotFound:
            return "snapshot_not_found"
        case .elementNotFound:
            return "element_not_found"
        case .ambiguousQuery:
            return "ambiguous_query"
        case .staleRef:
            return "stale_ref"
        case .elementNotClickable:
            return "element_not_clickable"
        case .elementActionFailed:
            return "element_action_failed"
        case .targetNotFrontmost:
            return "target_not_frontmost"
        case .elementGeometryUnavailable:
            return "element_geometry_unavailable"
        }
    }

    var message: String {
        switch self {
        case .invalidTarget(let message),
             .noSnapshotAvailable(let message),
             .snapshotNotFound(let message),
             .elementNotFound(let message),
             .ambiguousQuery(let message),
             .staleRef(let message),
             .elementNotClickable(let message),
             .elementActionFailed(let message),
             .targetNotFrontmost(let message),
             .elementGeometryUnavailable(let message):
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

struct ClickService {
    let permissions: PermissionsClient
    let client: ClickClient
    let logger: Logger
    let currentDirectoryPath: String
    let stateDirectoryPath: String

    func click(
        target: ClickTarget,
        snapshotID: String?,
        right: Bool
    ) async throws -> ClickData {
        let permissionsService = PermissionsService(client: permissions, logger: logger)
        let statuses = try permissionsService.status()
        let granted = Dictionary(uniqueKeysWithValues: statuses.permissions.map { ($0.kind, $0.granted) })
        guard granted[.accessibility] == true else {
            throw ClickError.missingPermission(.accessibility)
        }

        let store = SnapshotStore(
            stateDirectoryPath: stateDirectoryPath,
            currentDirectoryPath: currentDirectoryPath
        )
        let resolvedSnapshotID = if let snapshotID {
            snapshotID
        } else if let latest = try store.latestSnapshotID() {
            latest
        } else {
            throw ClickError.noSnapshotAvailable("no inspect snapshot is available")
        }
        guard let snapshot = try store.load(snapshotID: resolvedSnapshotID) else {
            throw ClickError.snapshotNotFound("snapshot not found: \(resolvedSnapshotID)")
        }

        let element = try resolveElement(
            target: target,
            snapshot: snapshot,
            right: right
        )
        logger.log("\(right ? "right-clicking" : "clicking") \(element.id) from \(snapshot.snapshot)")
        try await client.perform(snapshot.snapshot, element, right)
        return ClickData(
            snapshot: snapshot.snapshot,
            clicked: .init(
                id: element.id,
                role: element.role,
                name: element.name
            ),
            right: right
        )
    }

    private func resolveElement(
        target: ClickTarget,
        snapshot: StoredInspectSnapshot,
        right: Bool
    ) throws -> StoredInspectSnapshot.Element {
        switch target {
        case .reference(let reference):
            guard let element = snapshot.elements.first(where: { $0.id == reference }) else {
                throw ClickError.elementNotFound("element not found: \(reference)")
            }
            return element
        case .query(let query):
            let matches = snapshot.elements.filter { element in
                guard element.name.compare(query.name, options: [.caseInsensitive]) == .orderedSame else {
                    return false
                }
                if let role = query.role,
                   element.role.compare(role, options: [.caseInsensitive]) != .orderedSame
                {
                    return false
                }
                if right {
                    return element.resolver.screenFrame != nil
                }
                return element.resolver.actions.contains("AXPress")
            }
            guard !matches.isEmpty else {
                throw ClickError.elementNotFound("element not found: \(query.description)")
            }
            guard matches.count == 1 else {
                throw ClickError.ambiguousQuery("multiple elements matched \(query.description)")
            }
            return matches[0]
        }
    }
}

private extension ClickQuery {
    var description: String {
        if let role {
            return "\(role):\"\(name)\""
        }
        return "\"\(name)\""
    }
}
