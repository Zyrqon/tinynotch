import AppKit
import CoreAudio
import AudioToolbox

// MARK: - Громкость

/// Громкость устройства вывода по умолчанию через CoreAudio.
final class VolumeController: ObservableObject {
    @Published private(set) var volume: Float = 0.5
    @Published private(set) var isMuted = false
    @Published private(set) var isAvailable = true

    var onExternalChange: ((Float, Bool) -> Void)?

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var lastLocalChange = Date.distantPast
    private var listenedDevice = AudioObjectID(kAudioObjectUnknown)

    private var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    private var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    private lazy var listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        DispatchQueue.main.async { self?.refresh(external: true) }
    }

    init() {
        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddr, .main) { [weak self] _, _ in
            self?.attachToDefaultDevice()
        }
        attachToDefaultDevice()
    }

    func set(_ value: Float) {
        let clamped = min(max(value, 0), 1)
        lastLocalChange = Date()
        var v = Float32(clamped)
        AudioObjectSetPropertyData(device, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        if isMuted && clamped > 0 { setMuted(false) }
        volume = clamped
    }

    func toggleMute() { setMuted(!isMuted) }

    /// Шаг как у системных клавиш: 1/16, с ⌥⇧ — 1/64.
    func step(up: Bool, fine: Bool) {
        let unit: Float = fine ? 1 / 64 : 1 / 16
        if up && isMuted { setMuted(false) }
        let target = ((volume / unit).rounded() + (up ? 1 : -1)) * unit
        set(target)
        if target <= 0 { setMuted(true) }
    }

    private func setMuted(_ muted: Bool) {
        lastLocalChange = Date()
        var m: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(device, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m)
        isMuted = muted
    }

    private func attachToDefaultDevice() {
        if listenedDevice != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(listenedDevice, &volumeAddress, .main, listener)
            AudioObjectRemovePropertyListenerBlock(listenedDevice, &muteAddress, .main, listener)
        }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        device = id
        isAvailable = AudioObjectHasProperty(id, &volumeAddress)
        AudioObjectAddPropertyListenerBlock(id, &volumeAddress, .main, listener)
        AudioObjectAddPropertyListenerBlock(id, &muteAddress, .main, listener)
        listenedDevice = id
        refresh(external: false)
    }

    private func refresh(external: Bool) {
        var v = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &v) == noErr {
            volume = v
        }
        var m: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &m) == noErr {
            isMuted = m != 0
        }
        // Показываем HUD только на изменения извне (клавиши, Пункт управления).
        if external && Date().timeIntervalSince(lastLocalChange) > 0.4 {
            onExternalChange?(volume, isMuted)
        }
    }
}

// MARK: - Яркость

/// Яркость встроенного дисплея через приватный DisplayServices.framework.
final class BrightnessController: ObservableObject {
    @Published private(set) var brightness: Float = 0.5
    @Published private(set) var isAvailable = false

    var onExternalChange: ((Float) -> Void)?

    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias RegisterFn = @convention(c) (CGDirectDisplayID, UnsafeMutableRawPointer?, CFNotificationCallback) -> Int32
    /// Для колбэка уведомлений DisplayServices (C-функция без контекста).
    private static weak var current: BrightnessController?

    private var getFn: GetFn?
    private var setFn: SetFn?
    private var display: CGDirectDisplayID = CGMainDisplayID()
    private var lastLocalChange = Date.distantPast
    private var timer: Timer?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
        if let handle {
            if let g = dlsym(handle, "DisplayServicesGetBrightness") { getFn = unsafeBitCast(g, to: GetFn.self) }
            if let s = dlsym(handle, "DisplayServicesSetBrightness") { setFn = unsafeBitCast(s, to: SetFn.self) }
        }
        display = Self.builtInDisplay() ?? CGMainDisplayID()
        if let value = read() {
            brightness = value
            isAvailable = setFn != nil
        }
        // DisplayServices сам сообщает об изменении яркости (клавиши, Пункт управления, автояркость) —
        // так не нужно опрашивать её трижды в секунду. Если подписаться не вышло, остаётся опрос.
        Self.current = self
        if let handle, let sym = dlsym(handle, "DisplayServicesRegisterForBrightnessChangeNotifications"),
           unsafeBitCast(sym, to: RegisterFn.self)(display, nil, { _, _, _, _, info in
               let value = (info as? [String: Any])?["value"] as? Float
               DispatchQueue.main.async { BrightnessController.current?.externalChange(value) }
           }) == 0 {
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func externalChange(_ value: Float?) {
        guard isAvailable, let value = value ?? read(), abs(value - brightness) > 0.004 else { return }
        brightness = value
        if Date().timeIntervalSince(lastLocalChange) > 0.6 {
            onExternalChange?(value)
        }
    }

    func set(_ value: Float) {
        let clamped = min(max(value, 0), 1)
        lastLocalChange = Date()
        _ = setFn?(display, clamped)
        brightness = clamped
    }

    func step(up: Bool, fine: Bool) {
        let unit: Float = fine ? 1 / 64 : 1 / 16
        set(((brightness / unit).rounded() + (up ? 1 : -1)) * unit)
    }

    private func read() -> Float? {
        guard let getFn else { return nil }
        var value: Float = 0
        return getFn(display, &value) == 0 ? value : nil
    }

    private func poll() { externalChange(nil) }

    private static func builtInDisplay() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.first { CGDisplayIsBuiltin($0) != 0 }
    }
}
