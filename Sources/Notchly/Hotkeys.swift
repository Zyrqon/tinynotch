import Carbon.HIToolbox
import AppKit

/// Глобальное сочетание клавиш (Carbon RegisterEventHotKey — работает без разрешения «Универсальный доступ»).
final class HotkeyCenter {
    static let shared = HotkeyCenter()
    var handler: (() -> Void)?
    private var hotkeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            HotkeyCenter.shared.handler?()
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }

    func install(keyCode: UInt32, modsRaw: Int) {
        remove()
        guard keyCode != 0 else { return }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x4E54484B), id: 1)
        let status = RegisterEventHotKey(keyCode, Self.carbonMods(from: modsRaw), id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr { hotkeyRef = ref }
    }

    func remove() {
        if let ref = hotkeyRef { UnregisterEventHotKey(ref) }
        hotkeyRef = nil
    }

    /// rawValue NSEvent.ModifierFlags → маска Carbon.
    static func carbonMods(from nsRaw: Int) -> UInt32 {
        var m: UInt32 = 0
        if nsRaw & 0x100000 != 0 { m |= UInt32(cmdKey) }      // ⌘
        if nsRaw & 0x80000 != 0 { m |= UInt32(optionKey) }    // ⌥
        if nsRaw & 0x40000 != 0 { m |= UInt32(controlKey) }   // ⌃
        if nsRaw & 0x20000 != 0 { m |= UInt32(shiftKey) }     // ⇧
        return m
    }
}
