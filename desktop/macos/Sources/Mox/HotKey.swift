import AppKit
import Carbon
import MoxCore

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
