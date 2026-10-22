import Foundation
import IOBluetooth
import IOKit
import IOKit.ps

struct DeviceBattery: Identifiable, Equatable {
    struct Level: Identifiable, Equatable {
        var id: String { label + symbol }
        var label: String
        var symbol: String
        var percent: Int
        var charging = false
    }

    var id: String { name }
    var name: String
    var symbol: String
    var levels: [Level]
    var isConnected = true

    var isHeadphones: Bool {
        let n = name.lowercased()
        return n.contains("airpods") || n.contains("beats") || symbol.contains("headphones") || symbol.contains("airpods")
    }

    /// Для наушников с кейсом показываем заряд кейса, иначе — минимальный из имеющихся.
    var primaryLevel: Level? {
        levels.first { $0.label == "Кейс" } ?? levels.min { $0.percent < $1.percent }
    }
}

/// Заряд Mac и подключённых Bluetooth-устройств (AirPods, наушники, мышь, клавиатура),
/// а также события «подключили зарядку» и «подключили наушники».
final class DeviceBatteryMonitor: NSObject, ObservableObject {
    @Published private(set) var mac: BatteryInfo?
    @Published private(set) var devices: [DeviceBattery] = []

    /// Подключённые наушники — по карточке на каждые (AirPods Pro и AirPods Max отдельно).
    /// Неподключённые не показываем: их заряд уже неправда.
    var headphones: [DeviceBattery] {
        devices.filter { $0.isHeadphones && $0.isConnected }
    }

    /// Мышь, клавиатура, трекпад и прочие подключённые Bluetooth-устройства с зарядом.
    var accessories: [DeviceBattery] {
        devices.filter { !$0.isHeadphones && $0.isConnected }
    }

    /// Заряд iPhone из файла, который пишет автоматизация «Команд» (см. PhoneBattery).
    @Published private(set) var phone: PhoneBattery?

    var onChargerConnected: ((BatteryInfo) -> Void)?
    var onChargerDisconnected: ((BatteryInfo) -> Void)?
    var onAudioDeviceConnected: ((DeviceBattery) -> Void)?
    var onDeviceDisconnected: ((DeviceBattery) -> Void)?
    /// Заряд подключённых наушников стал известен уже после показа карточки.
    var onAudioDeviceUpdated: ((DeviceBattery) -> Void)?

    private var timer: Timer?
    /// Главная открыта — заряд устройств обновляется раз в 30 секунд.
    var keepsFresh = false
    private var loading = false
    private var debugMac: BatteryInfo?
    /// Кто ждёт окончания текущего обновления (например, окно подключения наушников).
    private var pendingCompletions: [() -> Void] = []
    private var wasOnAC: Bool?
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var lastDisconnect: [String: Date] = [:]
    private var lastConnectionState: [String: Bool] = [:]
    private var stateTimer: Timer?
    /// Разрыв уже показан быстрым опросом — системное уведомление о том же событии пропускаем.
    private var watcherReportedDisconnect: Set<String> = []
    /// Когда какие наушники последний раз сообщали о подключении — повторы подряд пропускаем.
    private var lastConnect: [String: Date] = [:]
    private let startedAt = Date()

    override init() {
        super.init()
        refresh()
        // Список устройств виден только на главной, а она обновляет его при открытии. Остальное (зарядка,
        // подключение наушников, изменение их заряда) приходит уведомлениями. Поэтому system_profiler
        // раз в 30 секунд запускаем, только пока главная на экране.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self, self.keepsFresh else { return }
            self.refresh()
        }
        startPowerNotifications()
        // Без описания доступа в Info.plist (запуск вне .app) macOS аварийно завершит процесс.
        if Bundle.main.object(forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription") != nil {
            connectNotification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                             selector: #selector(deviceConnected(_:fromDevice:)))
            Self.btlog("register-connect ok=\(connectNotification != nil)")
            registerDisconnectNotifications()
            startConnectionStateWatcher()
        } else {
            Self.btlog("в Info.plist нет NSBluetoothAlwaysUsageDescription")
        }
    }

    /// Для снапшотов.
    func debugSet(devices: [DeviceBattery], phone: PhoneBattery?, mac: BatteryInfo? = nil) {
        timer?.invalidate()
        stateTimer?.invalidate()
        debugMac = mac
        if let mac { self.mac = mac }
        loading = true
        self.devices = devices
        self.phone = phone
    }

    func refresh(completion: (() -> Void)? = nil) {
        mac = debugMac ?? BatteryInfo.read()
        // Обновление уже идёт — не теряем колбэк, а вызываем его, когда оно закончится.
        guard !loading else {
            if let completion { pendingCompletions.append(completion) }
            return
        }
        loading = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let devices = Self.readBluetooth()
            let phone = PhoneBattery.read()
            DispatchQueue.main.async {
                self?.loading = false
                if self?.devices != devices { self?.devices = devices }
                if self?.phone != phone { self?.phone = phone }
                completion?()
                let pending = self?.pendingCompletions ?? []
                self?.pendingCompletions = []
                pending.forEach { $0() }
            }
        }
    }

    // MARK: - Зарядка

    private func startPowerNotifications() {
        wasOnAC = BatteryInfo.read()?.onAC
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<DeviceBatteryMonitor>.fromOpaque(context).takeUnretainedValue().powerChanged()
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    private var lastAccessories: [String: DeviceBattery.Level] = [:]

    private func powerChanged() {
        guard debugMac == nil else { return }
        if let info = BatteryInfo.read() {
            mac = info
            if info.onAC && wasOnAC == false { onChargerConnected?(info) }
            else if !info.onAC && wasOnAC == true { onChargerDisconnected?(info) }
            wasOnAC = info.onAC
        }
        // Наушники тоже публикуются как источники питания: когда их заряд появился или изменился,
        // сразу перечитываем устройства и обновляем открытую карточку.
        let accessories = Self.accessoryLevels()
        guard accessories != lastAccessories else { return }
        lastAccessories = accessories
        refresh { [weak self] in
            guard let self else { return }
            for device in self.headphones where !device.levels.isEmpty { self.onAudioDeviceUpdated?(device) }
        }
    }

    /// Заряд аксессуаров из IOKit Power Sources — там же его берёт Пункт управления macOS.
    /// Так приходит заряд AirPods Max, которого нет ни в system_profiler, ни в IOBluetooth.
    static func accessoryLevels() -> [String: DeviceBattery.Level] {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return [:] }
        var result: [String: DeviceBattery.Level] = [:]
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String != kIOPSInternalBatteryType,
                  let name = desc[kIOPSNameKey] as? String, !name.isEmpty,
                  let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let percent = min(100, current * 100 / max)
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            // У AirPods с кейсом несколько источников с одним именем — берём меньший заряд.
            if let known = result[name], known.percent <= percent { continue }
            result[name] = DeviceBattery.Level(label: "", symbol: "", percent: percent, charging: charging)
        }
        return result
    }

    // MARK: - Наушники

    /// Журнал блютуз-событий: видно, дошло ли уведомление до карточки.
    private static let logURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchly", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("bt.log")
    }()

    static func btlog(_ text: String) {
        let line = "\(Date().formatted(date: .omitted, time: .standard)) \(text)\n"
        if let h = try? FileHandle(forWritingTo: logURL) {
            defer { try? h.close() }
            _ = try? h.seekToEndOfFile()
            h.write(Data(line.utf8))
        } else {
            try? line.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

    /// Отключения ловим по каждому спаренному устройству: уведомление приходит, когда связь рвётся.
    private func registerDisconnectNotifications() {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            Self.btlog("pairedDevices недоступен")
            return
        }
        for device in paired {
            guard let addr = device.addressString else { continue }
            disconnectNotifications[addr] = device.register(forDisconnectNotification: self,
                                                            selector: #selector(deviceDisconnected(_:fromDevice:)))
        }
        Self.btlog("register-disconnect \(disconnectNotifications.count) устройств")
    }

    @objc private func deviceDisconnected(_ note: IOBluetoothUserNotification, fromDevice device: IOBluetoothDevice) {
        guard Date().timeIntervalSince(startedAt) > 5 else { return }
        guard let name = device.name, !name.isEmpty else { Self.btlog("disconnect: устройство без имени"); return }
        if let addr = device.addressString { lastConnectionState[addr] = false }
        // Быстрый опрос уже показал этот разрыв раньше системы — не дублируем карточку.
        let key = Self.baseName(name)
        if watcherReportedDisconnect.remove(key) != nil {
            Self.btlog("disconnect \(name): уже показано быстрым опросом")
            return
        }
        fireDisconnect(name)
    }

    private func fireDisconnect(_ name: String) {
        let key = Self.baseName(name)
        if let last = lastDisconnect[key], Date().timeIntervalSince(last) < 15 { Self.btlog("disconnect \(name): повтор в 15с"); return }
        lastDisconnect[key] = Date()
        let info = DeviceBattery(name: name, symbol: Self.symbol(for: name, info: [:]), levels: [], isConnected: false)
        Self.btlog("fired-disconnect \(name)")
        onDeviceDisconnected?(info)
    }

    // MARK: - Быстрый опрос связи

    /// macOS сообщает о разрыве с HID-устройством с задержкой (ждёт переподключения), поэтому раз в 3
    /// секунды сами проверяем isConnected спаренных устройств и показываем отключение сразу.
    private func startConnectionStateWatcher() {
        snapshotConnectionStates()
        stateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkConnectionStates()
        }
        Self.btlog("state-watcher started")
    }

    private func snapshotConnectionStates() {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
        for device in paired {
            guard let addr = device.addressString else { continue }
            lastConnectionState[addr] = device.isConnected()
        }
    }

    private func checkConnectionStates() {
        guard Date().timeIntervalSince(startedAt) > 5 else { return }
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
        for device in paired {
            guard let name = device.name, !name.isEmpty, let addr = device.addressString else { continue }
            let connected = device.isConnected()
            let previous = lastConnectionState[addr] ?? connected
            if previous, !connected {
                lastConnectionState[addr] = false
                Self.btlog("watcher-disconnect \(name)")
                watcherReportedDisconnect.insert(Self.baseName(name))
                fireDisconnect(name)
            } else {
                lastConnectionState[addr] = connected
            }
        }
    }

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification, fromDevice device: IOBluetoothDevice) {
        // При запуске система сообщает обо всех уже подключённых устройствах — их пропускаем.
        guard Date().timeIntervalSince(startedAt) > 5 else { Self.btlog("connect \(device.name ?? "nil"): меньше 5с от запуска"); return }
        // Одни и те же AirPods сообщают о подключении несколько раз: «AirPods Pro (Имя)», «AirPods Pro»
        // и ещё запись без имени. Безымянную пропускаем, остальные сводим к одному имени ниже.
        guard let name = device.name, !name.isEmpty else { Self.btlog("connect: устройство без имени"); return }
        // Наушники подключают несколько профилей подряд, и система сообщает о каждом.
        let key = Self.baseName(name)
        if let last = lastConnect[key], Date().timeIntervalSince(last) < 15 { Self.btlog("connect \(name): повтор в 15с"); return }
        Self.btlog("connect \(name)")
        lastConnect[key] = Date()
        if let addr = device.addressString { lastConnectionState[addr] = device.isConnected() }
        // Заряд появляется в системе не сразу после подключения: IOBluetooth обычно знает его раньше,
        // чем system_profiler. Если сразу не нашли — перечитываем ещё до трёх раз и обновляем карточку на месте.
        func readAgain(_ monitor: DeviceBatteryMonitor, attempt: Int) {
            monitor.refresh {
                let device = monitor.connectedDevice(named: name)
                Self.btlog("fired \(name), уровней заряда \(device.levels.count), попытка \(attempt)")
                monitor.onAudioDeviceConnected?(device)
                guard device.levels.isEmpty, attempt < 3 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 1 ? 3 : 6)) { [weak monitor] in
                    guard let monitor else { return }
                    readAgain(monitor, attempt: attempt + 1)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            readAgain(self, attempt: 1)
        }
    }

    private func connectedDevice(named name: String) -> DeviceBattery {
        if let known = devices.first(where: { Self.baseName($0.name) == Self.baseName(name) && $0.isConnected }),
           !known.levels.isEmpty { return known }
        var levels = Self.lookup(Self.bluetoothLevels(), name) ?? Self.lookup(Self.accessoryLevels(), name).map { [$0] } ?? []
        // Система сразу после подключения отдаёт 0% вместо реального заряда: это «данных ещё нет».
        if !levels.isEmpty, levels.allSatisfy({ $0.percent <= 0 }) { levels = [] }
        return DeviceBattery(name: name, symbol: Self.symbol(for: name, info: ["device_minorType": "Headphones"]),
                             levels: levels)
    }

    private static func readBluetooth() -> [DeviceBattery] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        proc.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        guard (try? proc.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = json["SPBluetoothDataType"] as? [[String: Any]] else { return [] }

        let hid = hidBatteries()
        let direct = bluetoothLevels()
        let powerSources = accessoryLevels()
        var result: [DeviceBattery] = []
        for controller in controllers {
            for (key, connected) in [("device_connected", true), ("device_not_connected", false)] {
                for entry in controller[key] as? [[String: Any]] ?? [] {
                    for (name, value) in entry {
                        guard let info = value as? [String: Any] else { continue }
                        var levels = parseLevels(info, name: name)
                        if levels.isEmpty, connected, let fromBluetooth = lookup(direct, name) { levels = fromBluetooth }
                        if levels.isEmpty, connected, let fromPower = lookup(powerSources, name) { levels = [fromPower] }
                        // Magic Mouse, клавиатура и трекпад: в новых macOS system_profiler не отдаёт их заряд,
                        // но он есть у HID-сервиса устройства.
                        if levels.isEmpty, connected, let percent = hidPercent(for: info, in: hid) {
                            levels = [DeviceBattery.Level(label: "", symbol: "", percent: percent)]
                        }
                        // Подключённые наушники показываем и без заряда (AirPods Max сообщают его не всегда).
                        let headphones = DeviceBattery(name: name, symbol: symbol(for: name, info: info), levels: []).isHeadphones
                        guard !levels.isEmpty || (connected && headphones) else { continue }
                        result.append(DeviceBattery(name: name, symbol: symbol(for: name, info: info),
                                                    levels: levels, isConnected: connected))
                    }
                }
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    /// Заряд прямо из IOBluetooth. У IOBluetoothDevice есть недокументированные свойства
    /// batteryPercentLeft / Right / Case / Single — их читает и сама macOS. Нужны там, где system_profiler
    /// молчит: AirPods Max на macOS 27 и первые секунды после подключения. Читаем только если объект
    /// действительно отвечает на селектор, иначе KVC бросил бы исключение.
    static func bluetoothLevels() -> [String: [DeviceBattery.Level]] {
        guard Bundle.main.object(forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription") != nil,
              let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [:] }
        var result: [String: [DeviceBattery.Level]] = [:]
        for device in paired where device.isConnected() {
            func percent(_ key: String) -> Int? {
                guard device.responds(to: NSSelectorFromString(key)),
                      let value = (device.value(forKey: key) as? NSNumber)?.intValue,
                      (1...100).contains(value) else { return nil }
                return value
            }
            let name = device.name ?? ""
            let isPro = name.localizedCaseInsensitiveContains("pro")
            var levels: [DeviceBattery.Level] = []
            if let left = percent("batteryPercentLeft") { levels.append(.init(label: "Левый", symbol: "airpod.left", percent: left)) }
            if let right = percent("batteryPercentRight") { levels.append(.init(label: "Правый", symbol: "airpod.right", percent: right)) }
            if let casing = percent("batteryPercentCase") {
                levels.append(.init(label: "Кейс", symbol: isPro ? "airpodspro.chargingcase.wireless.fill" : "airpods.chargingcase.fill",
                                    percent: casing))
            }
            if levels.isEmpty, let single = percent("batteryPercentSingle") ?? percent("batteryPercentCombined")
                ?? percent("headsetBattery") {
                levels.append(.init(label: "", symbol: "", percent: single))
            }
            if !levels.isEmpty, !name.isEmpty { result[name] = levels }
        }
        return result
    }

    /// «AirPods Max (Имя)» и «AirPods Max» — одно и то же устройство: разные службы macOS
    /// называют его то с именем владельца, то без.
    static func baseName(_ name: String) -> String {
        name.replacingOccurrences(of: #"\s*\(.*\)\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Сначала точное совпадение имени, потом без имени владельца.
    static func lookup<T>(_ table: [String: T], _ name: String) -> T? {
        if let exact = table[name] { return exact }
        let base = baseName(name)
        return table.first { baseName($0.key) == base }?.value
    }

    private struct HIDBattery { var address: String; var productID: Int; var percent: Int }

    /// Заряд Bluetooth-устройств Apple из IOKit (AppleDeviceManagementHIDEventService).
    private static func hidBatteries() -> [HIDBattery] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"),
                                           &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [HIDBattery] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            func prop(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            guard let percent = prop("BatteryPercent") as? Int else { continue }
            let address = (prop("DeviceAddress") as? String ?? "").replacingOccurrences(of: "-", with: ":").uppercased()
            result.append(HIDBattery(address: address, productID: prop("ProductID") as? Int ?? -1, percent: percent))
        }
        return result
    }

    private static func hidPercent(for info: [String: Any], in hid: [HIDBattery]) -> Int? {
        if let address = (info["device_address"] as? String)?.uppercased(),
           let match = hid.first(where: { $0.address == address }) {
            return match.percent
        }
        if let raw = info["device_productID"] as? String, let pid = Int(raw.dropFirst(2), radix: 16) {
            let matches = hid.filter { $0.productID == pid }
            if matches.count == 1 { return matches[0].percent }
        }
        return nil
    }

    private static func parseLevels(_ info: [String: Any], name: String) -> [DeviceBattery.Level] {
        let isPro = name.localizedCaseInsensitiveContains("pro")
        let order: [(key: String, label: String, symbol: String)] = [
            ("device_batteryLevelLeft", "Левый", "airpod.left"),
            ("device_batteryLevelRight", "Правый", "airpod.right"),
            ("device_batteryLevelCase", "Кейс", isPro ? "airpodspro.chargingcase.wireless.fill" : "airpods.chargingcase.fill"),
            ("device_batteryLevelMain", "", ""),
            ("device_batteryLevel", "", ""),
        ]
        return order.compactMap { item in
            guard let raw = info[item.key] as? String,
                  let percent = Int(raw.filter(\.isNumber)) else { return nil }
            return DeviceBattery.Level(label: item.label, symbol: item.symbol, percent: percent)
        }
    }

    static func symbol(for name: String, info: [String: Any]) -> String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpodsmax" }
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpods") { return "airpods" }
        if lower.contains("beats") { return "beats.headphones" }
        if lower.contains("magic mouse") { return "magicmouse.fill" }
        if lower.contains("magic keyboard") { return "keyboard.fill" }
        if lower.contains("magic trackpad") { return "rectangle.and.hand.point.up.left.fill" }
        switch info["device_minorType"] as? String {
        case "Headphones", "Headset": return "headphones"
        case "Keyboard": return "keyboard"
        case "Mouse": return "magicmouse.fill"
        case "Trackpad": return "rectangle.and.hand.point.up.left"
        case "Speaker": return "hifispeaker"
        case "Gamepad": return "gamecontroller"
        default: return "bluetooth"
        }
    }
}

/// Заряд iPhone. На Mac нет API, чтобы его узнать, поэтому автоматизация в «Командах» на iPhone
/// сохраняет файл «iphone-battery.txt» в iCloud Drive (папка «Shortcuts», «Notchly» или старая «DynamicIsland»),
/// например с текстом «85 Да» — процент и заряжается ли телефон.
struct PhoneBattery: Equatable {
    var percent: Int
    var charging: Bool
    var updated: Date

    static let fileName = "iphone-battery.txt"

    static var candidates: [URL] {
        let docs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents")
        return [docs.appendingPathComponent("iCloud~is~workflow~my~workflows/Documents"),
                docs.appendingPathComponent("com~apple~CloudDocs/Notchly"),
                docs.appendingPathComponent("com~apple~CloudDocs/DynamicIsland"),
                docs.appendingPathComponent("com~apple~CloudDocs/Shortcuts")]
            .map { $0.appendingPathComponent(fileName) }
    }

    static func read() -> PhoneBattery? {
        let fm = FileManager.default
        var best: PhoneBattery?
        for url in candidates {
            // Файл мог быть выгружен из iCloud — просим скачать, прочитаем в следующий раз.
            let placeholder = url.deletingLastPathComponent().appendingPathComponent(".\(fileName).icloud")
            if fm.fileExists(atPath: placeholder.path) { try? fm.startDownloadingUbiquitousItem(at: url) }
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let date = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
                  // Старше суток — уже неправда.
                  Date().timeIntervalSince(date) < 86_400 else { continue }
            let numbers = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            guard let value = numbers.first else { continue }
            // Команды отдают уровень либо 0…100, либо 0…1.
            let percent = value <= 1 && text.contains(".") ? Int((Double(text.filter { $0.isNumber || $0 == "." }) ?? 0) * 100) : value
            let lower = text.lowercased()
            let charging = ["да", "yes", "true", "заряж", "charging"].contains { lower.contains($0) }
            let item = PhoneBattery(percent: min(max(percent, 0), 100), charging: charging, updated: date)
            if best == nil || date > best!.updated { best = item }
        }
        return best
    }
}

