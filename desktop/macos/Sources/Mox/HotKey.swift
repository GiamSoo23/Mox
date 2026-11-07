import AppKit
import Carbon

/// A global hotkey description (modifiers + virtual keycode).
struct HotKeyCombo {
    enum Key: UInt32 {
        case a = 0x00, s = 0x01, d = 0x02, f = 0x03, h = 0x04, g = 0x05, z = 0x06, x = 0x07
        case c = 0x08, v = 0x09, b = 0x0B, q = 0x0C, w = 0x0D, e = 0x0E, r = 0x0F, y = 0x10
        case t = 0x11, o = 0x1F, u = 0x20, i = 0x22, p = 0x23, l = 0x25, j = 0x26, k = 0x28
        case n = 0x2D, m = 0x2E
    }
    struct Modifiers: OptionSet {
        let rawValue: UInt32
        static let command = Modifiers(rawValue: UInt32(cmdKey))
        static let option  = Modifiers(rawValue: UInt32(optionKey))
        static let control = Modifiers(rawValue: UInt32(controlKey))
        static let shift   = Modifiers(rawValue: UInt32(shiftKey))
    }
    let key: Key
    let modifiers: Modifiers

    /// Parses "cmd+shift+u" style strings. Returns nil on unknown tokens.
    static func parse(_ raw: String) -> HotKeyCombo? {
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
        guard let t = keyTok, t.count == 1,
              let key = Key.allByLetter[t] else { return nil }
        return HotKeyCombo(key: key, modifiers: mods)
    }

    var human: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option)  { s += "⌥" }
        if modifiers.contains(.shift)   { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        s += String(describing: key).uppercased()
        return s
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

/// Carbon-backed global hotkey. The handler is invoked on the main queue.
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handler: (() -> Void)?
    private static var shared: HotKeyManager?

    /// Returns the OSStatus from RegisterEventHotKey: noErr (0) on success,
    /// eventHotKeyExistsErr (-9878) if another app already owns the combo.
    @discardableResult
    func register(_ combo: HotKeyCombo, action: @escaping () -> Void) -> OSStatus {
        unregister()
        self.handler = action
        HotKeyManager.shared = self

        let signature: OSType = 0x4D4F5821 // 'MOX!'
        let id = EventHotKeyID(signature: signature, id: 1)

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                       eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, _ -> OSStatus in
            DispatchQueue.main.async { HotKeyManager.shared?.handler?() }
            _ = eventRef
            return noErr
        }, 1, &eventType, nil, nil)

        return RegisterEventHotKey(combo.key.rawValue, combo.modifiers.rawValue, id,
                                   GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        hotKeyRef = nil
    }
}
