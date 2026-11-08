import Carbon

/// A global hotkey description (modifiers + virtual keycode).
public struct HotKeyCombo: Equatable {
    // Cases are named after the letter they type, so single-letter names are
    // the clearest option here.
    // swiftlint:disable identifier_name
    public enum Key: UInt32 {
        case a = 0x00, s = 0x01, d = 0x02, f = 0x03, h = 0x04, g = 0x05, z = 0x06, x = 0x07
        case c = 0x08, v = 0x09, b = 0x0B, q = 0x0C, w = 0x0D, e = 0x0E, r = 0x0F, y = 0x10
        case t = 0x11, o = 0x1F, u = 0x20, i = 0x22, p = 0x23, l = 0x25, j = 0x26, k = 0x28
        case n = 0x2D, m = 0x2E
    }
    // swiftlint:enable identifier_name
    public struct Modifiers: OptionSet, Equatable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: UInt32(cmdKey))
        public static let option  = Modifiers(rawValue: UInt32(optionKey))
        public static let control = Modifiers(rawValue: UInt32(controlKey))
        public static let shift   = Modifiers(rawValue: UInt32(shiftKey))
    }
    public let key: Key
    public let modifiers: Modifiers

    public init(key: Key, modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Parses "cmd+shift+u" style strings. Returns nil on unknown tokens.
    public static func parse(_ raw: String) -> HotKeyCombo? {
        var mods: Modifiers = []
        var keyTok: String?
        for tok in raw.lowercased().split(whereSeparator: { $0 == "+" || $0 == " " }) {
            switch tok {
            case "cmd", "command", "meta":  mods.insert(.command)
            case "shift":                   mods.insert(.shift)
            case "alt", "opt", "option":    mods.insert(.option)
            case "ctrl", "control":         mods.insert(.control)
            default:                        keyTok = String(tok)
            }
        }
        guard let letter = keyTok, letter.count == 1,
              let key = Key.allByLetter[letter] else { return nil }
        return HotKeyCombo(key: key, modifiers: mods)
    }

    public var human: String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        symbols += String(describing: key).uppercased()
        return symbols
    }
}

private extension HotKeyCombo.Key {
    static let allByLetter: [String: HotKeyCombo.Key] = [
        "a": .a, "s": .s, "d": .d, "f": .f, "h": .h, "g": .g, "z": .z, "x": .x,
        "c": .c, "v": .v, "b": .b, "q": .q, "w": .w, "e": .e, "r": .r, "y": .y,
        "t": .t, "o": .o, "u": .u, "i": .i, "p": .p, "l": .l, "j": .j, "k": .k,
        "n": .n, "m": .m
    ]
}
