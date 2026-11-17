import Carbon
import Foundation

/// Value types and pure functions: no keyboard, preferences or UI access.
struct HotKeyModifiers: OptionSet, Codable, Equatable {
    let rawValue: UInt32
    static let control = Self(rawValue: UInt32(controlKey))
    static let option = Self(rawValue: UInt32(optionKey))
    static let shift = Self(rawValue: UInt32(shiftKey))
    static let command = Self(rawValue: UInt32(cmdKey))
    static let supported: Self = [.control, .option, .shift, .command]
}

struct HotKeyShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: HotKeyModifiers

    static let `default` = Self(keyCode: UInt32(kVK_ANSI_R), modifiers: [.control, .option, .command])

    enum ValidationError: Error, Equatable {
        case missingModifier, modifierOnly, escapeReserved, unsupportedKey, unsupportedModifiers
        case shiftOnly, reservedShortcut

        var detail: String {
            switch self {
            case .missingModifier: return "请至少同时按住一个修饰键：⌘、⌥ 或 ⌃，也可搭配 ⇧。"
            case .modifierOnly: return "请在修饰键之外，再按一个字母、数字或其他按键。"
            case .escapeReserved: return "Esc 用于取消录制，不能用作快捷键。"
            case .unsupportedKey: return "暂不支持这个按键，请选择字母、数字、功能键或方向键。"
            case .unsupportedModifiers: return "快捷键修饰键仅支持 ⌘、⌥、⌃ 和 ⇧。"
            case .shiftOnly: return "不能只用 Shift 搭配另一个按键，以免影响打字或选择文字。请加入 ⌘、⌥ 或 ⌃。"
            case .reservedShortcut: return "这个组合用于常用的编辑或系统操作，不能设为全局定位键。请换一个组合，例如 ⌃⌥⌘R。"
            }
        }
    }

    func validationError() -> ValidationError? {
        if keyCode == UInt32(kVK_Escape) { return .escapeReserved }
        if Self.modifierKeyCodes.contains(keyCode) { return .modifierOnly }
        if modifiers.isEmpty { return .missingModifier }
        if !modifiers.subtracting(.supported).isEmpty { return .unsupportedModifiers }
        if Self.keyNames[keyCode] == nil { return .unsupportedKey }
        if modifiers == .shift { return .shiftOnly }
        if Self.reservedShortcuts.contains(self) { return .reservedShortcut }
        return nil
    }

    private static let reservedShortcuts: [Self] = {
        let common = [kVK_ANSI_A, kVK_ANSI_C, kVK_ANSI_X, kVK_ANSI_V, kVK_ANSI_Z,
                      kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_S, kVK_ANSI_O, kVK_ANSI_N,
                      kVK_ANSI_F, kVK_ANSI_H, kVK_ANSI_M, kVK_Tab, kVK_Space,
                      kVK_Delete, kVK_ANSI_Comma]
        return common.flatMap { code in
            [Self(keyCode: UInt32(code), modifiers: .command),
             Self(keyCode: UInt32(code), modifiers: [.command, .shift])]
        } + [Self(keyCode: UInt32(kVK_ANSI_V), modifiers: [.command, .option, .shift]),
             Self(keyCode: UInt32(kVK_ANSI_Q), modifiers: [.command, .control]),
             Self(keyCode: UInt32(kVK_Space), modifiers: .control),
             Self(keyCode: UInt32(kVK_Space), modifiers: [.control, .option]),
             Self(keyCode: UInt32(kVK_Space), modifiers: [.command, .option])]
    }()

    var displayName: String {
        let symbols: [(HotKeyModifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined()
            + (Self.keyNames[keyCode] ?? "Key \(keyCode)")
    }

    enum RecordingResult: Equatable {
        case cancelled, ignored, invalid(ValidationError), shortcut(HotKeyShortcut)
    }

    static func recordingResult(keyCode: UInt32, modifiers: HotKeyModifiers) -> RecordingResult {
        if keyCode == UInt32(kVK_Escape) { return .cancelled }
        if modifierKeyCodes.contains(keyCode) { return .ignored }
        let shortcut = Self(keyCode: keyCode, modifiers: modifiers)
        if let error = shortcut.validationError() { return .invalid(error) }
        return .shortcut(shortcut)
    }

    static func decodePreference(_ data: Data?) -> Self {
        guard let data, let shortcut = try? JSONDecoder().decode(Self.self, from: data),
              shortcut.validationError() == nil else { return .default }
        return shortcut
    }

    // Carbon registers physical virtual key codes. Use stable ANSI key names,
    // independent of input method, shifted characters and Caps Lock.
    private static let modifierKeyCodes: Set<UInt32> = Set(54...63)
    private static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        10: "§", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc",
        64: "F17", 65: "Keypad .", 67: "Keypad *", 69: "Keypad +", 71: "Clear",
        75: "Keypad /", 76: "Keypad Enter", 78: "Keypad -", 79: "F18", 80: "F19", 81: "Keypad =",
        82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3", 86: "Keypad 4",
        87: "Keypad 5", 88: "Keypad 6", 89: "Keypad 7", 90: "F20", 91: "Keypad 8", 92: "Keypad 9",
        93: "¥", 94: "_", 95: "Keypad ,", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
        101: "F9", 102: "英数", 103: "F11", 104: "かな", 105: "F13", 106: "F16", 107: "F14",
        109: "F10", 111: "F12", 113: "F15", 114: "Help", 115: "Home", 116: "Page Up",
        117: "Forward Delete", 118: "F4", 119: "End", 120: "F2", 121: "Page Down", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
}

protocol HotKeyPreferences {
    func load() -> HotKeyShortcut
    func save(_ shortcut: HotKeyShortcut)
}

struct UserDefaultsHotKeyPreferences: HotKeyPreferences {
    static let key = "globalHotKey"
    var defaults: UserDefaults = .standard

    func load() -> HotKeyShortcut {
        HotKeyShortcut.decodePreference(defaults.data(forKey: Self.key))
    }

    func save(_ shortcut: HotKeyShortcut) {
        guard shortcut.validationError() == nil, let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
