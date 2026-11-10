import AppKit
import Carbon
import MoxCore

/// Carbon-backed global hotkeys, each with its own id. Handlers run on the
/// main queue.
final class HotKeyManager {
    private static let signature: OSType = 0x4D4F5821 // 'MOX!'
    private static var shared: HotKeyManager?
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var handlerInstalled = false

    /// Returns the OSStatus from RegisterEventHotKey: noErr (0) on success,
    /// eventHotKeyExistsErr (-9878) if another app already owns the combo.
    @discardableResult
    func register(_ combo: HotKeyCombo, id: UInt32 = 1, action: @escaping () -> Void) -> OSStatus {
        unregister(id: id)
        handlers[id] = action
        HotKeyManager.shared = self
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.key.rawValue, combo.modifiers.rawValue,
                                         EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs[id] = ref }
        return status
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
    }

    /// One handler for every hotkey: it reads which id was pressed.
    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            let id = pressed.id
            DispatchQueue.main.async { HotKeyManager.shared?.handlers[id]?() }
            return noErr
        }, 1, &eventType, nil, nil)
    }
}
