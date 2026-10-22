import AppKit
import CoreAudio
import AudioToolbox

/// Приложение, которое сейчас выводит звук (все его процессы и хелперы вместе).
struct AudioApp: Identifiable, Equatable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let icon: NSImage?
    var processes: [AudioObjectID]
    var isPlaying: Bool
}

/// Микшер громкости по приложениям на Core Audio process taps (macOS 14.2+).
///
/// Пока у приложения 100% и нет mute, мы ничего не трогаем. Иначе создаём private tap,
/// который забирает звук приложения (`.muted` — в динамики он больше не идёт),
/// и aggregate device «tap → текущий выход», где IOProc проигрывает звук с нужным усилением.
final class AppAudioMixer: ObservableObject {
    enum Access: Equatable { case unknown, granted, denied, unsupported }

    @Published private(set) var apps: [AudioApp] = []
    @Published private(set) var levels: [String: Float] = [:]
    @Published private(set) var muted: Set<String> = []
    @Published private(set) var access: Access = .unknown

    private var taps: [String: ProcessTap] = [:]
    private var lastSeen: [String: Date] = [:]
    private var requestingAccess = false
    /// Слушатели Core Audio вместо опроса: список аудиопроцессов и запуск/остановка звука у каждого из них.
    private var listening = false
    private var processListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var refreshWork: DispatchWorkItem?
    private let defaults = UserDefaults.standard
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    /// Taps требуют описания в Info.plist, иначе процесс вне .app падает на TCC.
    static var isSupported: Bool {
        if #available(macOS 14.2, *) {
            return Bundle.main.object(forInfoDictionaryKey: "NSAudioCaptureUsageDescription") != nil
        }
        return false
    }

    init(live: Bool = true) {
        levels = defaults.dictionary(forKey: "mixer.levels") as? [String: Float] ?? [:]
        muted = Set(defaults.stringArray(forKey: "mixer.muted") ?? [])
        guard live else { return }
        access = Self.isSupported ? AudioCaptureAccess.status : .unsupported

        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { [weak self] _, _ in
            self?.rebuildAllTaps()
        }
        listening = true
        var listAddr = Self.address(kAudioHardwarePropertyProcessObjectList)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &listAddr, .main,
                                            processListChanged)
        refresh()
    }

    deinit {
        taps.values.forEach { $0.stop() }
        stopListening()
    }

    private lazy var processListChanged: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.scheduleRefresh(after: 0.1)
    }

    private func stopListening() {
        guard listening else { return }
        listening = false
        var listAddr = Self.address(kAudioHardwarePropertyProcessObjectList)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &listAddr, .main,
                                               processListChanged)
        for (obj, block) in processListeners {
            for selector in Self.processSelectors {
                var addr = Self.address(selector)
                AudioObjectRemovePropertyListenerBlock(obj, &addr, .main, block)
            }
        }
        processListeners.removeAll()
    }

    /// Подписываемся на новые процессы. Исчезнувшие просто забываем: их объектов уже нет,
    /// и отписка от них только сыпала бы ошибками в лог.
    private func syncProcessListeners(with objects: [AudioObjectID]) {
        let current = Set(objects)
        for obj in processListeners.keys where !current.contains(obj) { processListeners[obj] = nil }
        for obj in objects where processListeners[obj] == nil {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleRefresh(after: 0.05) }
            for selector in Self.processSelectors {
                var addr = Self.address(selector)
                AudioObjectAddPropertyListenerBlock(obj, &addr, .main, block)
            }
            processListeners[obj] = block
        }
    }

    /// На macOS 27 уведомление приходит только для IsRunning (процесс запустил или остановил звук);
    /// IsRunningOutput подписку принимает, но молчит. Слушаем оба — само значение читаем в refresh().
    private static let processSelectors = [kAudioProcessPropertyIsRunning, kAudioProcessPropertyIsRunningOutput]

    /// События приходят пачками (браузер заводит несколько хелперов разом) — обновляемся один раз.
    private func scheduleRefresh(after delay: TimeInterval) {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func level(for app: AudioApp) -> Float { levels[app.bundleID] ?? 1 }
    func isMuted(_ app: AudioApp) -> Bool { muted.contains(app.bundleID) }

    func setLevel(_ value: Float, for app: AudioApp) {
        let v = min(max(value, 0), 1)
        levels[app.bundleID] = v >= 0.995 ? nil : v
        if v > 0.001 { muted.remove(app.bundleID) }
        persist()
        apply(app)
    }

    func toggleMute(_ app: AudioApp) {
        if muted.contains(app.bundleID) { muted.remove(app.bundleID) } else { muted.insert(app.bundleID) }
        persist()
        apply(app)
    }

    func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!
        NSWorkspace.shared.open(url)
    }

    /// Для снапшотов.
    func debugSet(apps: [AudioApp], levels: [String: Float], muted: Set<String>, access: Access) {
        refreshWork?.cancel()
        stopListening()
        self.apps = apps
        self.levels = levels
        self.muted = muted
        self.access = access
    }

    // MARK: - Список приложений

    /// Кому принадлежит аудиопроцесс (или никому). Поиск через LaunchServices дорогой —
    /// запоминаем ответ, пока процесс есть в списке Core Audio (ниже кэш чистится по этому списку).
    private var owners: [pid_t: NSRunningApplication?] = [:]

    private func owner(pid: pid_t, obj: AudioObjectID) -> NSRunningApplication? {
        if let cached = owners[pid] { return cached }
        let app = Self.owningApp(pid: pid, obj: obj)
        owners[pid] = .some(app)
        return app
    }

    private func refresh() {
        var byApp: [String: (app: NSRunningApplication, procs: [AudioObjectID], playing: Bool)] = [:]
        var alive = Set<pid_t>()
        let objects = Self.processObjects()
        if listening { syncProcessListeners(with: objects) }
        for obj in objects {
            let pid: pid_t = Self.read(obj, kAudioProcessPropertyPID, pid_t(0))
            alive.insert(pid)
            guard pid > 0, pid != ownPID, let app = owner(pid: pid, obj: obj),
                  let bundleID = app.bundleIdentifier, app.processIdentifier != ownPID else { continue }
            let playing = Self.read(obj, kAudioProcessPropertyIsRunningOutput, UInt32(0)) != 0
            var entry = byApp[bundleID] ?? (app, [], false)
            entry.procs.append(obj)
            entry.playing = entry.playing || playing
            byApp[bundleID] = entry
        }

        owners = owners.filter { alive.contains($0.key) }

        let now = Date()
        var nextExpiry: TimeInterval?
        var result: [AudioApp] = []
        for (bundleID, entry) in byApp {
            if entry.playing { lastSeen[bundleID] = now }
            // Держим приложение в списке ещё немного после паузы, чтобы строки не мигали,
            // и всегда — пока к нему применена своя громкость.
            let recent = lastSeen[bundleID].map { now.timeIntervalSince($0) < Self.keepAfterPause } ?? false
            if recent && !entry.playing, let seen = lastSeen[bundleID] {
                let expires = seen.addingTimeInterval(Self.keepAfterPause).timeIntervalSince(now)
                nextExpiry = min(nextExpiry ?? expires, expires)
            }
            guard entry.playing || recent || taps[bundleID] != nil else { continue }
            result.append(AudioApp(bundleID: bundleID,
                                   name: entry.app.localizedName ?? bundleID,
                                   icon: entry.app.icon,
                                   processes: entry.procs.sorted(),
                                   isPlaying: entry.playing))
        }
        result.sort { ($0.name.localizedCaseInsensitiveCompare($1.name)) == .orderedAscending }

        // Приложение закрылось — снимаем tap.
        for bundleID in taps.keys where byApp[bundleID] == nil {
            taps.removeValue(forKey: bundleID)?.stop()
        }
        if result != apps { apps = result }
        result.forEach(apply)
        // Приложение на паузе пропадёт из списка, когда истечёт его время, — событий тогда не будет.
        if listening, let nextExpiry { scheduleRefresh(after: nextExpiry + 0.1) }
    }

    private static let keepAfterPause: TimeInterval = 12

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    // MARK: - Taps

    private func apply(_ app: AudioApp) {
        let gain: Float = muted.contains(app.bundleID) ? 0 : (levels[app.bundleID] ?? 1)
        guard gain < 0.995 else {
            taps.removeValue(forKey: app.bundleID)?.stop()
            return
        }
        guard Self.isSupported else { return }
        if let tap = taps[app.bundleID], tap.isRunning {
            tap.gain.target = gain
            // Браузеры постоянно заводят и закрывают хелперы. Пересоздавать tap из-за этого нельзя —
            // будет слышен обрыв, поэтому меняем список процессов у работающего tap.
            if tap.processes != app.processes && !tap.update(processes: app.processes) {
                taps.removeValue(forKey: app.bundleID)?.stop()
            } else {
                return
            }
        }
        switch AudioCaptureAccess.status {
        case .granted:
            access = .granted
        case .unknown:
            access = .unknown
            guard !requestingAccess else { return }
            requestingAccess = true
            AudioCaptureAccess.request { [weak self] granted in
                self?.requestingAccess = false
                self?.access = granted ? .granted : .denied
                if granted { self?.refresh() }
            }
            return
        case .denied, .unsupported:
            // Без разрешения tap отдаёт тишину — лучше оставить звук как есть.
            access = .denied
            return
        }
        taps.removeValue(forKey: app.bundleID)?.stop()
        if #available(macOS 14.2, *), let tap = ProcessTap(processes: app.processes, gain: gain) {
            taps[app.bundleID] = tap
        }
    }

    private func rebuildAllTaps() {
        taps.values.forEach { $0.stop() }
        taps.removeAll()
        apps.forEach(apply)
    }

    private func persist() {
        defaults.set(levels, forKey: "mixer.levels")
        defaults.set(Array(muted), forKey: "mixer.muted")
    }

    // MARK: - Core Audio

    private static func processObjects() -> [AudioObjectID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func read<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, _ fallback: T,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> T {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var value = fallback
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0)
        }
        return status == noErr ? value : fallback
    }

    static func readString(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0)
        }
        guard status == noErr, let s = value?.takeRetainedValue() as String?, !s.isEmpty else { return nil }
        return s
    }

    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    private static let responsibleFn: ResponsibleFn? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        return unsafeBitCast(sym, to: ResponsibleFn.self)
    }()

    /// Хелперы (Chrome Helper, WebKit.GPU у Safari) сводим к приложению, которое за них отвечает.
    private static func owningApp(pid: pid_t, obj: AudioObjectID) -> NSRunningApplication? {
        var candidates = [pid]
        if let responsible = responsibleFn?(pid), responsible > 0, responsible != pid {
            candidates.insert(responsible, at: 0)
        }
        for p in candidates {
            if let app = NSRunningApplication(processIdentifier: p), app.activationPolicy != .prohibited,
               app.bundleIdentifier != nil {
                return app
            }
        }
        // Последний шанс: com.google.Chrome.helper → com.google.Chrome.
        guard var bundleID = readString(obj, kAudioProcessPropertyBundleID) else { return nil }
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        while let dot = bundleID.lastIndex(of: ".") {
            bundleID = String(bundleID[..<dot])
            if let app = running.first(where: { $0.bundleIdentifier == bundleID }) { return app }
        }
        return nil
    }
}

// MARK: - Tap одного приложения

/// Плавное усиление: IOProc читает его на аудиопотоке, меняем с главного.
final class GainBox: @unchecked Sendable {
    var target: Float
    var current: Float
    init(_ value: Float) { target = value; current = value }
}

private final class ProcessTap {
    private(set) var processes: [AudioObjectID]
    private var description: AnyObject?
    let gain: GainBox
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private(set) var isRunning = false

    @available(macOS 14.2, *)
    init?(processes: [AudioObjectID], gain: Float) {
        self.processes = processes
        self.gain = GainBox(gain)

        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.name = "Notchly mixer"
        description.muteBehavior = .muted
        description.isPrivate = true
        description.isExclusive = false
        self.description = description
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr, tapID != kAudioObjectUnknown else {
            NSLog("Mixer: не удалось создать tap")
            return nil
        }

        guard let outputUID = Self.defaultOutputUID() else { stop(); return nil }
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Notchly mixer",
            kAudioAggregateDeviceUIDKey: "dev.notchly.app.mixer.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                               kAudioSubTapDriftCompensationKey: true]],
        ]
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr else {
            NSLog("Mixer: не удалось создать aggregate device")
            stop(); return nil
        }

        let box = self.gain
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, input, _, output, _ in
            ProcessTap.render(input: input, output: output, gain: box)
        }
        guard status == noErr, AudioDeviceStart(aggregateID, procID) == noErr else {
            NSLog("Mixer: не удалось запустить IOProc")
            stop(); return nil
        }
        isRunning = true
    }

    /// Меняет состав процессов без остановки звука. false — если система не приняла изменение.
    func update(processes: [AudioObjectID]) -> Bool {
        guard #available(macOS 14.2, *), let description = description as? CATapDescription,
              tapID != kAudioObjectUnknown else { return false }
        description.processes = processes
        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyDescription,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var ref: Unmanaged<CATapDescription> = .passUnretained(description)
        let status = AudioObjectSetPropertyData(tapID, &addr, 0, nil,
                                                UInt32(MemoryLayout<Unmanaged<CATapDescription>>.size), &ref)
        guard status == noErr else {
            NSLog("Mixer: не удалось обновить процессы tap (\(status))")
            return false
        }
        self.processes = processes
        return true
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        procID = nil
        if tapID != kAudioObjectUnknown {
            if #available(macOS 14.2, *) { AudioHardwareDestroyProcessTap(tapID) }
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        isRunning = false
    }

    /// Аудиопоток: копируем звук из tap во все выходные буферы с усилением.
    /// Tap — последний входной буфер aggregate (перед ним могут быть входы самого устройства).
    private static func render(input: UnsafePointer<AudioBufferList>,
                               output: UnsafeMutablePointer<AudioBufferList>, gain: GainBox) {
        let inList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outList = UnsafeMutableAudioBufferListPointer(output)
        for buf in outList { if let d = buf.mData { memset(d, 0, Int(buf.mDataByteSize)) } }
        guard let tapBuf = inList.last, let src = tapBuf.mData?.assumingMemoryBound(to: Float.self) else { return }
        let inCh = max(Int(tapBuf.mNumberChannels), 1)
        let inFrames = Int(tapBuf.mDataByteSize) / MemoryLayout<Float>.size / inCh
        guard inFrames > 0 else { return }

        let start = gain.current
        let end = gain.target
        gain.current = end
        let totalOut = outList.reduce(0) { $0 + max(Int($1.mNumberChannels), 1) }
        var channelBase = 0
        for buf in outList {
            let outCh = max(Int(buf.mNumberChannels), 1)
            defer { channelBase += outCh }
            guard let dst = buf.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let frames = min(inFrames, Int(buf.mDataByteSize) / MemoryLayout<Float>.size / outCh)
            let step = frames > 1 ? (end - start) / Float(frames) : 0
            for c in 0..<outCh {
                let global = channelBase + c
                // Лишние каналы (5.1 и т.п.) оставляем тихими, моно-выход получает сумму.
                if totalOut == 1 {
                    for f in 0..<frames {
                        var sum: Float = 0
                        for sc in 0..<inCh { sum += src[f * inCh + sc] }
                        dst[f] = sum / Float(inCh) * (start + step * Float(f))
                    }
                } else if global < inCh || inCh == 1 {
                    let sc = inCh == 1 ? 0 : global
                    for f in 0..<frames {
                        dst[f * outCh + c] = src[f * inCh + sc] * (start + step * Float(f))
                    }
                }
            }
        }
    }

    private static func defaultOutputUID() -> String? {
        let device: AudioObjectID = AppAudioMixer.read(AudioObjectID(kAudioObjectSystemObject),
                                                       kAudioHardwarePropertyDefaultOutputDevice,
                                                       AudioObjectID(kAudioObjectUnknown))
        guard device != kAudioObjectUnknown else { return nil }
        return AppAudioMixer.readString(device, kAudioDevicePropertyDeviceUID)
    }
}

// MARK: - Разрешение «Запись системного аудио»

/// Публичного API для проверки нет, используем приватный TCC (так же делает пример Apple AudioCap).
enum AudioCaptureAccess {
    private typealias PreflightFn = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias RequestFn = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void
    private static let service = "kTCCServiceAudioCapture" as CFString
    private static let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    static var status: AppAudioMixer.Access {
        guard AppAudioMixer.isSupported else { return .unsupported }
        guard let handle, let sym = dlsym(handle, "TCCAccessPreflight") else { return .granted }
        switch unsafeBitCast(sym, to: PreflightFn.self)(service, nil) {
        case 0: return .granted
        case 1: return .denied
        default: return .unknown
        }
    }

    static func request(_ completion: @escaping (Bool) -> Void) {
        guard let handle, let sym = dlsym(handle, "TCCAccessRequest") else { return completion(true) }
        unsafeBitCast(sym, to: RequestFn.self)(service, nil) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }
}
