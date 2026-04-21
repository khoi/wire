import Foundation

typealias ScrollTarget = SnapshotElementTarget

enum ScrollDirection: String, Codable, Equatable {
    case up
    case down

    var wheelDelta: Int32 {
        switch self {
        case .up:
            return 1
        case .down:
            return -1
        }
    }
}

struct ScrollClient {
    typealias ScrollFocused = (_ direction: ScrollDirection, _ amount: Int) async throws -> Void
    typealias ScrollElement = (
        _ element: StoredInspectSnapshot.Element,
        _ direction: ScrollDirection,
        _ amount: Int
    ) async throws -> Void

    var scrollFocused: ScrollFocused
    var scrollElement: ScrollElement

    static func live() -> ScrollClient {
        ScrollClient(
            scrollFocused: { direction, amount in
                try LiveInspectSystem.scroll(direction: direction, amount: amount)
            },
            scrollElement: { element, direction, amount in
                try LiveInspectSystem.scroll(
                    element: element,
                    direction: direction,
                    amount: amount
                )
            }
        )
    }
}

struct ScrollData: Codable, Equatable {
    struct Target: Codable, Equatable {
        let id: String
        let role: String
        let name: String
    }

    let direction: ScrollDirection
    let amount: Int
    let on: String?
    let target: Target?
    let scrolled: Bool

    func plainText(snapshot: String?) -> String {
        if let target {
            if let snapshot {
                return "scrolled \(direction.rawValue) \(amount) \(target.id) \(target.role) \(target.name)"
                    + " (\(snapshot))"
            }
            return "scrolled \(direction.rawValue) \(amount) \(target.id) \(target.role) \(target.name)"
        }
        return "scrolled \(direction.rawValue) \(amount) focused"
    }
}

struct ScrollOutcome {
    let snapshot: String?
    let data: ScrollData
}

enum ScrollError: WireError {
    case invalidTarget(String)
    case invalidAmount(String)
    case missingPermission(PermissionKind)
    case noSnapshotAvailable(String)
    case elementNotFound(String)
    case ambiguousQuery(String)
    case staleRef(String)
    case elementGeometryUnavailable(String)
    case scrollActionFailed(String)

    var code: String {
        switch self {
        case .invalidTarget:
            return "invalid_scroll_target"
        case .invalidAmount:
            return "invalid_scroll_amount"
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
        case .elementGeometryUnavailable:
            return "element_geometry_unavailable"
        case .scrollActionFailed:
            return "scroll_action_failed"
        }
    }

    var message: String {
        switch self {
        case .invalidTarget(let message),
             .invalidAmount(let message),
             .noSnapshotAvailable(let message),
             .elementNotFound(let message),
             .ambiguousQuery(let message),
             .staleRef(let message),
             .elementGeometryUnavailable(let message),
             .scrollActionFailed(let message):
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

struct ScrollService {
    let permissions: PermissionsClient
    let client: ScrollClient
    let logger: Logger
    let currentDirectoryPath: String
    let stateDirectoryPath: String

    func scroll(
        direction: ScrollDirection,
        amount: Int,
        on target: ScrollTarget?
    ) async throws -> ScrollOutcome {
        let permissionsService = PermissionsService(client: permissions, logger: logger)
        let statuses = try permissionsService.status()
        let granted = Dictionary(uniqueKeysWithValues: statuses.permissions.map { ($0.kind, $0.granted) })
        guard granted[.accessibility] == true else {
            throw ScrollError.missingPermission(.accessibility)
        }

        guard let target else {
            logger.log("scrolling focused area \(direction.rawValue) by \(amount)")
            do {
                try await client.scrollFocused(direction, amount)
            } catch let error as ScrollError {
                throw error
            } catch {
                throw ScrollError.scrollActionFailed(
                    "failed to scroll focused area: \(String(describing: error))"
                )
            }
            return ScrollOutcome(
                snapshot: nil,
                data: .init(
                    direction: direction,
                    amount: amount,
                    on: nil,
                    target: nil,
                    scrolled: true
                )
            )
        }

        let store = SnapshotStore(
            stateDirectoryPath: stateDirectoryPath,
            currentDirectoryPath: currentDirectoryPath
        )
        guard let snapshotID = try store.latestSnapshotID() else {
            throw ScrollError.noSnapshotAvailable("no inspect snapshot is available")
        }
        guard let snapshot = try store.load(snapshotID: snapshotID) else {
            throw ScrollError.noSnapshotAvailable("no inspect snapshot is available")
        }

        let element = try resolveElement(
            target: target,
            snapshot: snapshot
        )
        logger.log("scrolling \(target.description) from \(snapshot.snapshot) \(direction.rawValue) by \(amount)")
        do {
            try await client.scrollElement(element, direction, amount)
        } catch let error as ScrollError {
            throw error
        } catch {
            throw ScrollError.scrollActionFailed(
                "failed to scroll \(target.description): \(String(describing: error))"
            )
        }

        return ScrollOutcome(
            snapshot: snapshot.snapshot,
            data: .init(
                direction: direction,
                amount: amount,
                on: target.description,
                target: .init(
                    id: element.id,
                    role: element.role,
                    name: element.name
                ),
                scrolled: true
            )
        )
    }

    private func resolveElement(
        target: ScrollTarget,
        snapshot: StoredInspectSnapshot
    ) throws -> StoredInspectSnapshot.Element {
        try resolveSnapshotElement(
            target: target,
            snapshot: snapshot,
            queryFilter: { element in
                element.enabled != false && element.resolver.screenFrame != nil
            },
            notFound: { description in
                ScrollError.elementNotFound("element not found: \(description)")
            },
            ambiguous: { description in
                ScrollError.ambiguousQuery("multiple elements matched \(description)")
            }
        )
    }
}
