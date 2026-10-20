import AppKit
import Carbon

/// Everything a keyboard shortcut can trigger.
enum Action: String, CaseIterable, Identifiable, Codable {
    case toggle, undo, clear, stop, color1, color2, color3, color4

    var id: String { rawValue }

    /// Only `toggle` works from any app. The others work while the pen is on.
    var isGlobal: Bool { self == .toggle }

    var title: String {
        switch self {
        case .toggle: return String(localized: "Turn the pen on or off")
        case .undo: return String(localized: "Undo last stroke")
        case .clear: return String(localized: "Clear everything")
        case .stop: return String(localized: "Stop drawing")
        case .color1: return String(localized: "Color 1")
        case .color2: return String(localized: "Color 2")
        case .color3: return String(localized: "Color 3")
        case .color4: return String(localized: "Color 4")
        }
    }

    var colorIndex: Int? {
        switch self {
        case .color1: return 0
        case .color2: return 1
        case .color3: return 2
        case .color4: return 3
        default: return nil
        }
    }
}

/// A physical key plus modifiers. Stored by key code so it follows the user's keyboard layout.
struct Shortcut: Codable, Hashable {
    var keyCode: UInt16
    var modifiers: UInt

    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.relevantModifiers).rawValue
    }

    init(event: NSEvent) {
        self.init(keyCode: event.keyCode, modifiers: event.modifierFlags)
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode && event.modifierFlags.intersection(Self.relevantModifiers) == flags
    }

    var hasCommandLikeModifier: Bool {
        !flags.intersection([.command, .option, .control]).isEmpty
    }

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    var display: String { Self.symbols(for: flags) + KeyNames.name(for: keyCode) }

    static func symbols(for flags: NSEvent.ModifierFlags) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s
    }

    /// Defaults are looked up by character so that, for example, Undo stays on the Z key with an AZERTY keyboard.
    static func defaults() -> [Action: Shortcut] {
        func key(_ character: String, fallback: Int) -> UInt16 {
            KeyNames.keyCode(for: character) ?? UInt16(fallback)
        }
        return [
            .toggle: Shortcut(keyCode: key("p", fallback: kVK_ANSI_P), modifiers: [.command, .option]),
            .undo: Shortcut(keyCode: key("z", fallback: kVK_ANSI_Z), modifiers: [.command]),
            .clear: Shortcut(keyCode: key("c", fallback: kVK_ANSI_C), modifiers: []),
            .stop: Shortcut(keyCode: UInt16(kVK_Escape), modifiers: []),
            // Top row number keys, by position, so they also work where digits need Shift.
            .color1: Shortcut(keyCode: UInt16(kVK_ANSI_1), modifiers: []),
            .color2: Shortcut(keyCode: UInt16(kVK_ANSI_2), modifiers: []),
            .color3: Shortcut(keyCode: UInt16(kVK_ANSI_3), modifiers: []),
            .color4: Shortcut(keyCode: UInt16(kVK_ANSI_4), modifiers: []),
        ]
    }
}

enum KeyNames {
    private static let special: [Int: String] = [
        kVK_Escape: "Esc", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// Number row keys show their digit, even on layouts where the digit needs Shift (AZERTY).
    private static let numberRow: [Int: String] = [
        kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4", kVK_ANSI_5: "5",
        kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9", kVK_ANSI_0: "0",
    ]

    static func name(for keyCode: UInt16) -> String {
        if Int(keyCode) == kVK_Space { return String(localized: "Space") }
        if let digit = numberRow[Int(keyCode)] { return digit }
        if let s = special[Int(keyCode)] { return s }
        return character(for: keyCode)?.uppercased() ?? "#\(keyCode)"
    }

    /// The character this key types on the current keyboard layout, without modifiers.
    static func character(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let s = String(utf16CodeUnits: chars, count: length)
        return s.trimmingCharacters(in: .controlCharacters).isEmpty ? nil : s
    }

    static func keyCode(for character: String) -> UInt16? {
        (0..<128).map(UInt16.init).first { self.character(for: $0)?.lowercased() == character }
    }

    /// Menu items need a character to show a shortcut.
    static func menuEquivalent(for keyCode: UInt16) -> String? {
        switch Int(keyCode) {
        case kVK_Escape: return "\u{1b}"
        case kVK_Return: return "\r"
        case kVK_Space: return " "
        case kVK_Delete: return "\u{8}"
        default: return character(for: keyCode)?.lowercased()
        }
    }
}
