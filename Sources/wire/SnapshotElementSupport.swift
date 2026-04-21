import Foundation

enum SnapshotElementTarget: Equatable {
    case reference(String)
    case query(SnapshotElementQuery)

    static func parse(
        _ input: String,
        emptyMessage: String,
        invalid: (String) -> any Error
    ) throws -> SnapshotElementTarget {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw invalid(emptyMessage)
        }
        if SnapshotElementTarget.isReference(trimmed) {
            return .reference(trimmed)
        }
        return .query(
            try SnapshotElementQuery.parse(
                trimmed,
                emptyMessage: emptyMessage,
                invalid: invalid
            )
        )
    }

    var description: String {
        switch self {
        case .reference(let id):
            return id
        case .query(let query):
            return query.description
        }
    }

    private static func isReference(_ value: String) -> Bool {
        guard value.hasPrefix("@e"), value.count > 2 else {
            return false
        }
        return value.dropFirst(2).allSatisfy(\.isNumber)
    }
}

struct SnapshotElementQuery: Equatable {
    let role: String?
    let name: String

    static func parse(
        _ input: String,
        emptyMessage: String,
        invalid: (String) -> any Error
    ) throws -> SnapshotElementQuery {
        if let query = SnapshotElementQuery.parseScopedQuery(input) {
            return query
        }
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw invalid(emptyMessage)
        }
        return SnapshotElementQuery(role: nil, name: name)
    }

    func matches(_ element: StoredInspectSnapshot.Element) -> Bool {
        guard element.name.compare(name, options: [.caseInsensitive]) == .orderedSame else {
            return false
        }
        if let role,
           element.role.compare(role, options: [.caseInsensitive]) != .orderedSame
        {
            return false
        }
        return true
    }

    var description: String {
        if let role {
            return "\(role):\"\(name)\""
        }
        return "\"\(name)\""
    }

    private static func parseScopedQuery(_ input: String) -> SnapshotElementQuery? {
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
        return SnapshotElementQuery(role: role, name: name)
    }
}

func resolveSnapshotElement(
    target: SnapshotElementTarget,
    snapshot: StoredInspectSnapshot,
    queryFilter: (StoredInspectSnapshot.Element) -> Bool,
    notFound: (String) -> any Error,
    ambiguous: (String) -> any Error
) throws -> StoredInspectSnapshot.Element {
    switch target {
    case .reference(let reference):
        guard let element = snapshot.elements.first(where: { $0.id == reference }) else {
            throw notFound(reference)
        }
        return element
    case .query(let query):
        let matches = snapshot.elements.filter { element in
            query.matches(element) && queryFilter(element)
        }
        guard !matches.isEmpty else {
            throw notFound(query.description)
        }
        guard matches.count == 1 else {
            throw ambiguous(query.description)
        }
        return matches[0]
    }
}
