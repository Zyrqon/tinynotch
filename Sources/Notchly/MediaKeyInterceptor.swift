import AppKit
import ApplicationServices

/// Перехватывает клавиши громкости и яркости, чтобы вместо системного индикатора
/// показывался только остров. Нужен доступ «Универсальный доступ» (Accessibility).
final class MediaKeyInterceptor {
    enum Key { case volumeUp, volumeDown, mute, brightnessUp, brightnessDown }

    /// Вызывается на главном потоке; второй аргумент — мелкий шаг (⌥⇧).
    var handler: ((Key, Bool) -> Void)?
    private(set) var isActive = false
    /// Выключено в настройках — клавиши идут системе, и она показывает свой индикатор.
    var isEnabled = true

    private var tap: CFMachPort?
    private var retryTimer: Timer?

    func start() {
        // Системное окно «Разрешить Универсальный доступ» показываем один раз за всё время,
        // а не при каждом запуске; дальше тихо ждём, пока доступ выдадут в Настройках.
        let askedKey = "accessibility.prompted"
        let shouldPrompt = !UserDefaults.standard.bool(forKey: askedKey)
        UserDefaults.standard.set(true, forKey: askedKey)
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: shouldPrompt] as CFDictionary
        if AXIsProcessTrustedWithOptions(prompt) {
            install()
            return
        }
        // Ждём, пока пользователь выдаст доступ в Системных настройках.
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.install()
        }
    }

    private func install() {
        let systemDefined = CGEventMask(1 << 14) // NX_SYSDEFINED — мультимедийные клавиши
        let keys = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: systemDefined | keys,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                return Unmanaged<MediaKeyInterceptor>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
            },
            userInfo: refcon)
        else { return }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isActive = true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        guard isEnabled else { return pass }

        // На части клавиатур яркость приходит обычными кодами клавиш.
        if type == .keyDown || type == .keyUp {
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let key: Key
            switch code {
            case 144: key = .brightnessUp
            case 145: key = .brightnessDown
            default: return pass
            }
            if type == .keyDown { handler?(key, event.flags.contains([.maskAlternate, .maskShift])) }
            return nil
        }

        guard type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return pass }
        let code = (ns.data1 & 0xFFFF0000) >> 16
        let isDown = ((ns.data1 & 0xFF00) >> 8) == 0xA
        let key: Key
        switch code {
        case 0: key = .volumeUp
        case 1: key = .volumeDown
        case 7: key = .mute
        case 2: key = .brightnessUp
        case 3: key = .brightnessDown
        default: return pass
        }
        let mods = ns.modifierFlags
        // ⌥ + клавиша громкости открывает системные настройки — не мешаем.
        if mods.contains(.option) && !mods.contains(.shift) { return pass }
        if isDown { handler?(key, mods.contains([.option, .shift])) }
        return nil
    }
}
