@preconcurrency import ApplicationServices
import Carbon.HIToolbox
import Foundation

struct PressClient {
    typealias Perform = (_ action: PressAction) async throws -> Void

    var perform: Perform

    static func live() -> PressClient {
        PressClient(
            perform: { action in
                try LivePressSystem.press(action)
            }
        )
    }
}

struct PressData: Codable, Equatable {
    let input: String
    let normalized: String
    let key: String
    let modifiers: [String]
    let pressed: Bool

    func plainText() -> String {
        "pressed \(normalized)"
    }
}

enum PressError: WireError {
    case invalidKey(String)
    case missingPermission(PermissionKind)
    case pressActionFailed(String)

    var code: String {
        switch self {
        case .invalidKey:
            return "invalid_press_key"
        case .missingPermission(.accessibility):
            return "accessibility_permission_required"
        case .missingPermission(.screenRecording):
            return "screen_recording_permission_required"
        case .pressActionFailed:
            return "press_action_failed"
        }
    }

    var message: String {
        switch self {
        case .invalidKey(let message),
             .pressActionFailed(let message):
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

struct PressService {
    let permissions: PermissionsClient
    let client: PressClient
    let logger: Logger

    func press(input: String) async throws -> PressData {
        let action = try PressParser.parse(input)

        let permissionsService = PermissionsService(client: permissions, logger: logger)
        let statuses = try permissionsService.status()
        let granted = Dictionary(uniqueKeysWithValues: statuses.permissions.map { ($0.kind, $0.granted) })
        guard granted[.accessibility] == true else {
            throw PressError.missingPermission(.accessibility)
        }

        logger.log("pressing \(action.normalized)")
        do {
            try await client.perform(action)
        } catch let error as PressError {
            throw error
        } catch {
            throw PressError.pressActionFailed(
                "failed to press \(action.normalized): \(String(describing: error))"
            )
        }

        return PressData(
            input: action.input,
            normalized: action.normalized,
            key: action.key,
            modifiers: action.modifiers,
            pressed: true
        )
    }
}

struct PressAction: Equatable {
    let input: String
    let normalized: String
    let key: String
    let modifiers: [String]
    let keyCode: CGKeyCode
    let flagsRawValue: UInt64

    var flags: CGEventFlags {
        CGEventFlags(rawValue: flagsRawValue)
    }
}

private enum PressParser {
    static let modifierOrder: [PressModifier] = [.cmd, .ctrl, .alt, .shift, .fn]

    static func parse(_ input: String) throws -> PressAction {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PressError.invalidKey("press key cannot be empty")
        }

        let parts = trimmed
            .split(separator: "+", omittingEmptySubsequences: false)
            .map {
                PressKey.normalize(
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        guard parts.allSatisfy({ !$0.isEmpty }) else {
            throw PressError.invalidKey("invalid key combo syntax: \(trimmed)")
        }

        var modifiers = Set<PressModifier>()
        var key: PressKey?
        for part in parts {
            if let modifier = PressModifier.parse(part) {
                guard modifiers.insert(modifier).inserted else {
                    throw PressError.invalidKey("duplicate modifier in key combo: \(trimmed)")
                }
                continue
            }
            guard key == nil else {
                throw PressError.invalidKey("key combo must include exactly one key: \(trimmed)")
            }
            guard let resolved = PressKey.parse(part) else {
                throw PressError.invalidKey("unsupported key or combo: \(trimmed)")
            }
            key = resolved
        }

        guard let key else {
            throw PressError.invalidKey("key combo must include exactly one key: \(trimmed)")
        }

        let orderedModifiers = modifierOrder.filter { modifiers.contains($0) }
        let modifierNames = orderedModifiers.map(\.rawValue)
        let normalized = (modifierNames + [key.name]).joined(separator: "+")
        let flags = orderedModifiers.reduce(CGEventFlags()) { partial, modifier in
            partial.union(modifier.flag)
        }

        return PressAction(
            input: trimmed,
            normalized: normalized,
            key: key.name,
            modifiers: modifierNames,
            keyCode: key.keyCode,
            flagsRawValue: flags.rawValue
        )
    }
}

private enum PressModifier: String, CaseIterable, Hashable {
    case cmd
    case ctrl
    case alt
    case shift
    case fn

    var aliases: Set<String> {
        switch self {
        case .cmd:
            return ["cmd", "command"]
        case .ctrl:
            return ["ctrl", "control"]
        case .alt:
            return ["alt", "opt", "option"]
        case .shift:
            return ["shift"]
        case .fn:
            return ["fn", "function"]
        }
    }

    var flag: CGEventFlags {
        switch self {
        case .cmd:
            return .maskCommand
        case .ctrl:
            return .maskControl
        case .alt:
            return .maskAlternate
        case .shift:
            return .maskShift
        case .fn:
            return .maskSecondaryFn
        }
    }

    static func parse(_ token: String) -> PressModifier? {
        PressModifier.allCases.first { $0.aliases.contains(token) }
    }
}

private struct PressKey {
    let name: String
    let keyCode: CGKeyCode

    static func parse(_ token: String) -> PressKey? {
        if let named = namedKeys[token] {
            return named
        }
        guard token.count == 1 else {
            return nil
        }
        return alphaNumericKeys[token]
    }

    static func normalize(_ token: String) -> String {
        token
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
    }

    private static let alphaNumericKeys: [String: PressKey] = [
        "a": .init(name: "a", keyCode: CGKeyCode(kVK_ANSI_A)),
        "b": .init(name: "b", keyCode: CGKeyCode(kVK_ANSI_B)),
        "c": .init(name: "c", keyCode: CGKeyCode(kVK_ANSI_C)),
        "d": .init(name: "d", keyCode: CGKeyCode(kVK_ANSI_D)),
        "e": .init(name: "e", keyCode: CGKeyCode(kVK_ANSI_E)),
        "f": .init(name: "f", keyCode: CGKeyCode(kVK_ANSI_F)),
        "g": .init(name: "g", keyCode: CGKeyCode(kVK_ANSI_G)),
        "h": .init(name: "h", keyCode: CGKeyCode(kVK_ANSI_H)),
        "i": .init(name: "i", keyCode: CGKeyCode(kVK_ANSI_I)),
        "j": .init(name: "j", keyCode: CGKeyCode(kVK_ANSI_J)),
        "k": .init(name: "k", keyCode: CGKeyCode(kVK_ANSI_K)),
        "l": .init(name: "l", keyCode: CGKeyCode(kVK_ANSI_L)),
        "m": .init(name: "m", keyCode: CGKeyCode(kVK_ANSI_M)),
        "n": .init(name: "n", keyCode: CGKeyCode(kVK_ANSI_N)),
        "o": .init(name: "o", keyCode: CGKeyCode(kVK_ANSI_O)),
        "p": .init(name: "p", keyCode: CGKeyCode(kVK_ANSI_P)),
        "q": .init(name: "q", keyCode: CGKeyCode(kVK_ANSI_Q)),
        "r": .init(name: "r", keyCode: CGKeyCode(kVK_ANSI_R)),
        "s": .init(name: "s", keyCode: CGKeyCode(kVK_ANSI_S)),
        "t": .init(name: "t", keyCode: CGKeyCode(kVK_ANSI_T)),
        "u": .init(name: "u", keyCode: CGKeyCode(kVK_ANSI_U)),
        "v": .init(name: "v", keyCode: CGKeyCode(kVK_ANSI_V)),
        "w": .init(name: "w", keyCode: CGKeyCode(kVK_ANSI_W)),
        "x": .init(name: "x", keyCode: CGKeyCode(kVK_ANSI_X)),
        "y": .init(name: "y", keyCode: CGKeyCode(kVK_ANSI_Y)),
        "z": .init(name: "z", keyCode: CGKeyCode(kVK_ANSI_Z)),
        "0": .init(name: "0", keyCode: CGKeyCode(kVK_ANSI_0)),
        "1": .init(name: "1", keyCode: CGKeyCode(kVK_ANSI_1)),
        "2": .init(name: "2", keyCode: CGKeyCode(kVK_ANSI_2)),
        "3": .init(name: "3", keyCode: CGKeyCode(kVK_ANSI_3)),
        "4": .init(name: "4", keyCode: CGKeyCode(kVK_ANSI_4)),
        "5": .init(name: "5", keyCode: CGKeyCode(kVK_ANSI_5)),
        "6": .init(name: "6", keyCode: CGKeyCode(kVK_ANSI_6)),
        "7": .init(name: "7", keyCode: CGKeyCode(kVK_ANSI_7)),
        "8": .init(name: "8", keyCode: CGKeyCode(kVK_ANSI_8)),
        "9": .init(name: "9", keyCode: CGKeyCode(kVK_ANSI_9)),
    ]

    private static let namedKeys: [String: PressKey] = [
        "up": .init(name: "up", keyCode: CGKeyCode(kVK_UpArrow)),
        "down": .init(name: "down", keyCode: CGKeyCode(kVK_DownArrow)),
        "left": .init(name: "left", keyCode: CGKeyCode(kVK_LeftArrow)),
        "right": .init(name: "right", keyCode: CGKeyCode(kVK_RightArrow)),
        "home": .init(name: "home", keyCode: CGKeyCode(kVK_Home)),
        "end": .init(name: "end", keyCode: CGKeyCode(kVK_End)),
        "pageup": .init(name: "pageup", keyCode: CGKeyCode(kVK_PageUp)),
        "page_up": .init(name: "pageup", keyCode: CGKeyCode(kVK_PageUp)),
        "pagedown": .init(name: "pagedown", keyCode: CGKeyCode(kVK_PageDown)),
        "page_down": .init(name: "pagedown", keyCode: CGKeyCode(kVK_PageDown)),
        "delete": .init(name: "delete", keyCode: CGKeyCode(kVK_Delete)),
        "backspace": .init(name: "delete", keyCode: CGKeyCode(kVK_Delete)),
        "forward_delete": .init(name: "forward_delete", keyCode: CGKeyCode(kVK_ForwardDelete)),
        "forwarddelete": .init(name: "forward_delete", keyCode: CGKeyCode(kVK_ForwardDelete)),
        "clear": .init(name: "clear", keyCode: CGKeyCode(kVK_ANSI_KeypadClear)),
        "return": .init(name: "return", keyCode: CGKeyCode(kVK_Return)),
        "enter": .init(name: "enter", keyCode: CGKeyCode(kVK_ANSI_KeypadEnter)),
        "tab": .init(name: "tab", keyCode: CGKeyCode(kVK_Tab)),
        "escape": .init(name: "escape", keyCode: CGKeyCode(kVK_Escape)),
        "esc": .init(name: "escape", keyCode: CGKeyCode(kVK_Escape)),
        "space": .init(name: "space", keyCode: CGKeyCode(kVK_Space)),
        "spacebar": .init(name: "space", keyCode: CGKeyCode(kVK_Space)),
        "f1": .init(name: "f1", keyCode: CGKeyCode(kVK_F1)),
        "f2": .init(name: "f2", keyCode: CGKeyCode(kVK_F2)),
        "f3": .init(name: "f3", keyCode: CGKeyCode(kVK_F3)),
        "f4": .init(name: "f4", keyCode: CGKeyCode(kVK_F4)),
        "f5": .init(name: "f5", keyCode: CGKeyCode(kVK_F5)),
        "f6": .init(name: "f6", keyCode: CGKeyCode(kVK_F6)),
        "f7": .init(name: "f7", keyCode: CGKeyCode(kVK_F7)),
        "f8": .init(name: "f8", keyCode: CGKeyCode(kVK_F8)),
        "f9": .init(name: "f9", keyCode: CGKeyCode(kVK_F9)),
        "f10": .init(name: "f10", keyCode: CGKeyCode(kVK_F10)),
        "f11": .init(name: "f11", keyCode: CGKeyCode(kVK_F11)),
        "f12": .init(name: "f12", keyCode: CGKeyCode(kVK_F12)),
        "caps_lock": .init(name: "caps_lock", keyCode: CGKeyCode(kVK_CapsLock)),
        "capslock": .init(name: "caps_lock", keyCode: CGKeyCode(kVK_CapsLock)),
        "help": .init(name: "help", keyCode: CGKeyCode(kVK_Help)),
    ]
}

enum LivePressSystem {
    static func press(_ action: PressAction) throws {
        guard let down = CGEvent(
            keyboardEventSource: nil,
            virtualKey: action.keyCode,
            keyDown: true
        ),
        let up = CGEvent(
            keyboardEventSource: nil,
            virtualKey: action.keyCode,
            keyDown: false
        ) else {
            throw PressError.pressActionFailed("failed to create keyboard events")
        }
        down.flags = action.flags
        up.flags = action.flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
