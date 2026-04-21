import Foundation

struct TypeClient {
    typealias TypeFocused = (_ text: String) async throws -> Void
    typealias TypeElement = (_ element: StoredInspectSnapshot.Element, _ text: String) async throws -> Void

    var typeFocused: TypeFocused
    var typeElement: TypeElement

    static func live() -> TypeClient {
        TypeClient(
            typeFocused: { text in
                try LiveInspectSystem.type(text: text)
            },
            typeElement: { element, text in
                try LiveInspectSystem.type(element: element, text: text)
            }
        )
    }
}

struct TypeData: Codable, Equatable {
    struct Target: Codable, Equatable {
        let id: String
        let role: String
        let name: String
    }

    let text: String
    let into: String?
    let target: Target?
    let typed: Bool

    func plainText(snapshot: String?) -> String {
        if let target {
            if let snapshot {
                return "typed \(target.id) \(target.role) \(target.name) (\(snapshot))"
            }
            return "typed \(target.id) \(target.role) \(target.name)"
        }
        return "typed \(text)"
    }
}

struct TypeOutcome {
    let snapshot: String?
    let data: TypeData
}

enum TypeError: WireError {
    case invalidTarget(String)
    case missingPermission(PermissionKind)
    case noSnapshotAvailable(String)
    case elementNotFound(String)
    case ambiguousQuery(String)
    case staleRef(String)
    case elementNotTypeable(String)
    case typeActionFailed(String)

    var code: String {
        switch self {
        case .invalidTarget:
            return "invalid_type_target"
        case .missingPermission(.accessibility):
            return "accessibility_permission_required"
        case .missingPermission(.screenRecording):
            return "screen_recording_permission_required"
        case .noSnapshotAvailable:
            return "no_snapshot_available"
        case .elementNotFound:
            return "element_not_found"
        case .ambiguousQuery:
            return "ambiguous_query"
        case .staleRef:
            return "stale_ref"
        case .elementNotTypeable:
            return "element_not_typeable"
        case .typeActionFailed:
            return "type_action_failed"
        }
    }

    var message: String {
        switch self {
        case .invalidTarget(let message),
             .noSnapshotAvailable(let message),
             .elementNotFound(let message),
             .ambiguousQuery(let message),
             .staleRef(let message),
             .elementNotTypeable(let message),
             .typeActionFailed(let message):
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

struct TypeService {
    let permissions: PermissionsClient
    let client: TypeClient
    let logger: Logger
    let currentDirectoryPath: String
    let stateDirectoryPath: String

    func type(
        text: String,
        into target: SnapshotElementTarget?
    ) async throws -> TypeOutcome {
        let permissionsService = PermissionsService(client: permissions, logger: logger)
        let statuses = try permissionsService.status()
        let granted = Dictionary(uniqueKeysWithValues: statuses.permissions.map { ($0.kind, $0.granted) })
        guard granted[.accessibility] == true else {
            throw TypeError.missingPermission(.accessibility)
        }

        guard let target else {
            logger.log("typing into focused element")
            do {
                try await client.typeFocused(text)
            } catch let error as TypeError {
                throw error
            } catch {
                throw TypeError.typeActionFailed("failed to type text: \(String(describing: error))")
            }
            return TypeOutcome(
                snapshot: nil,
                data: .init(
                    text: text,
                    into: nil,
                    target: nil,
                    typed: true
                )
            )
        }

        let store = SnapshotStore(
            stateDirectoryPath: stateDirectoryPath,
            currentDirectoryPath: currentDirectoryPath
        )
        guard let snapshotID = try store.latestSnapshotID() else {
            throw TypeError.noSnapshotAvailable("no inspect snapshot is available")
        }
        guard let snapshot = try store.load(snapshotID: snapshotID) else {
            throw TypeError.noSnapshotAvailable("no inspect snapshot is available")
        }

        let element = try resolveElement(target: target, snapshot: snapshot)
        try validateTypeable(element)
        logger.log("typing \(element.id) from \(snapshot.snapshot)")

        do {
            try await client.typeElement(element, text)
        } catch let error as TypeError {
            throw error
        } catch {
            throw TypeError.typeActionFailed("failed to type \(target.description): \(String(describing: error))")
        }

        return TypeOutcome(
            snapshot: snapshot.snapshot,
            data: .init(
                text: text,
                into: target.description,
                target: .init(
                    id: element.id,
                    role: element.role,
                    name: element.name
                ),
                typed: true
            )
        )
    }

    private func resolveElement(
        target: SnapshotElementTarget,
        snapshot: StoredInspectSnapshot
    ) throws -> StoredInspectSnapshot.Element {
        try resolveSnapshotElement(
            target: target,
            snapshot: snapshot,
            queryFilter: { element in
                element.enabled != false && element.resolver.valueSettable
            },
            notFound: { description in
                TypeError.elementNotFound("element not found: \(description)")
            },
            ambiguous: { description in
                TypeError.ambiguousQuery("multiple elements matched \(description)")
            }
        )
    }

    private func validateTypeable(_ element: StoredInspectSnapshot.Element) throws {
        guard element.enabled != false, element.resolver.valueSettable else {
            throw TypeError.elementNotTypeable("\(element.id) is not typeable")
        }
    }
}
