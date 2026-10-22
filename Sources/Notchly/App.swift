import AppKit
import Combine
import UserNotifications

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchWindowController?
    private var statusItem: NSStatusItem?
    private var menuBarObserver: AnyCancellable?
    private var languageObserver: AnyCancellable?

    static func main() {
        // --lang en: снапшоты на английском (для README).
        if let i = CommandLine.arguments.firstIndex(of: "--lang"), i + 1 < CommandLine.arguments.count,
           let language = AppLanguage(rawValue: CommandLine.arguments[i + 1]) {
            Loc.language = language
        }
        if let i = CommandLine.arguments.firstIndex(of: "--gif"), i + 1 < CommandLine.arguments.count {
            MainActor.assumeIsolated {
                ReadmeGIF.render(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            }
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--bench") {
            let rest = CommandLine.arguments[(i + 1)...]
            var seconds = 8.0
            if let j = rest.firstIndex(of: "--seconds"), j + 1 < CommandLine.arguments.count {
                seconds = Double(CommandLine.arguments[j + 1]) ?? seconds
            }
            let names = rest.filter { !$0.hasPrefix("--") && Double($0) == nil }
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            Task { @MainActor in
                await Bench.run(names: Array(names), seconds: seconds)
                exit(0)
            }
            app.run()
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshots"), i + 1 < CommandLine.arguments.count {
            MainActor.assumeIsolated {
                Snapshots.render(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            }
            exit(0)
        }
        if CommandLine.arguments.contains("--chime") {
            print("Сигнал напоминания: \(SoftChime.isAvailable ? "OK" : "не собрался")")
            SoftChime.play()
            RunLoop.main.run(until: Date().addingTimeInterval(1.2))
            exit(0)
        }
        if CommandLine.arguments.contains("--reminders-selftest") {
            let tasks = TasksStore(persistent: false)
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            tasks.add("Через 10 минут", time: f.string(from: Date().addingTimeInterval(10 * 60)))
            tasks.add("Через 5 минут", time: f.string(from: Date().addingTimeInterval(5 * 60)))
            tasks.add("Через 30 минут", time: f.string(from: Date().addingTimeInterval(30 * 60)))
            tasks.add("Прямо сейчас", time: f.string(from: Date()))
            let center = ReminderCenter(tasks: tasks)
            var fired: [String] = []
            center.onFire = { fired.append("\($0.title) — за \($0.minutesBefore) мин") }
            center.start()
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            print(fired.isEmpty ? "Ничего не сработало" : fired.joined(separator: "\n"))
            // Переход через полночь: задача на завтра в 00:05 должна напомнить сегодня в 23:55.
            fired = []
            tasks.add("Завтра в 00:05", time: "00:05", dayOffset: 1)
            let lateEvening = Calendar.current.date(bySettingHour: 23, minute: 55, second: 30, of: Date())!
            center.check(now: lateEvening)
            print("Через полночь: " + (fired.contains("Завтра в 00:05 — за 10 мин") ? "OK" : "ОШИБКА \(fired)"))
            exit(0)
        }
        if CommandLine.arguments.contains("--imap-selftest") {
            GmailSelfTest.run()
            exit(0)
        }
        if CommandLine.arguments.contains("--notifications-selftest") {
            let report = SystemNotificationsReader().selfTestReport()
            let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Notchly/notifications-selftest.txt")
            try? report.write(to: url, atomically: true, encoding: .utf8)
            print(report)
            exit(0)
        }
        if CommandLine.arguments.contains("--services-selftest") {
            var lines: [String] = []
            let group = DispatchGroup()
            group.enter()
            GeminiAssistant.selfTest { lines.append("Gemini: " + $0); group.leave() }
            group.enter()
            GmailClient.selfTest { lines.append("Gmail: " + $0); group.leave() }
            while group.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
            let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Notchly/services-selftest.txt")
            try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            exit(0)
        }
        if CommandLine.arguments.contains("--batteries-selftest") {
            let monitor = DeviceBatteryMonitor()
            RunLoop.main.run(until: Date().addingTimeInterval(4))
            for d in monitor.devices {
                print(d.name, d.isConnected ? "подключено" : "не подключено", d.levels.map { "\($0.label) \($0.percent)%" })
            }
            print("Аксессуары на главной:", monitor.accessories.map(\.name))
            var report = monitor.devices.map { d in
                "\(d.name) \(d.isConnected ? "подключено" : "не подключено") " + d.levels.map { "\($0.label) \($0.percent)%" }.joined(separator: ", ")
            }
            report.append("IOBluetooth: " + DeviceBatteryMonitor.bluetoothLevels()
                .map { "\($0.key): " + $0.value.map { "\($0.label) \($0.percent)%" }.joined(separator: ", ") }
                .joined(separator: " | "))
            report.append("Источники питания: " + DeviceBatteryMonitor.accessoryLevels()
                .map { "\($0.key) \($0.value.percent)%" }.sorted().joined(separator: ", "))
            let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Notchly/batteries-selftest.txt")
            try? report.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            exit(0)
        }
        if CommandLine.arguments.contains("--mixer-selftest") {
            let mixer = AppAudioMixer()
            RunLoop.main.run(until: Date().addingTimeInterval(1.5))
            print("Доступ к записи аудио: \(mixer.access)")
            for app in mixer.apps {
                print("\(app.name) [\(app.bundleID)] процессы: \(app.processes) играет: \(app.isPlaying)")
            }
            if mixer.apps.isEmpty { print("Звук сейчас никто не выводит") }
            exit(0)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Регистрируем обработчик ссылок как можно раньше: событие может прийти во время запуска.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        // При холодном запуске по ссылке URL может прийти аргументом командной строки.
        for arg in CommandLine.arguments where arg.hasPrefix("tinynotch://") {
            processURLString(arg)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LegacyMigration.run()
        controller = NotchWindowController()
        setupStatusItem()
    }

    /// tinynotch://install?pack=pack-code — установка пака прямо из браузера.
    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else { return }
        processURLString(raw)
    }

    private func processURLString(_ raw: String) {
        let marker = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TinyNotch/url-debug.txt")
        try? "event: \(raw)".write(to: marker, atomically: true, encoding: .utf8)
        guard let url = URL(string: raw), url.scheme == "tinynotch" else { return }
        var packID: String?
        for pair in url.query?.split(separator: "&") ?? [] {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2, parts[0] == "pack" { packID = String(parts[1]) }
        }
        guard let packID, !packID.isEmpty else { return }
        ToolPackManager.shared.installFromWeb(id: packID) { ok in
            try? "event: \(packID) ok: \(ok)".write(to: marker, atomically: true, encoding: .utf8)
            if ok, let pack = ToolPackManager.shared.packs.first(where: { $0.id == packID }) {
                self.notifyInstalled("Пак «\(pack.name)» установлен")
            } else {
                self.notifyInstalled("Не удалось скачать пак \(packID)")
            }
        }
    }

    private func notifyInstalled(_ text: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "TinyNotch"
            content.body = text
            let request = UNNotificationRequest(identifier: "pack-install", content: content, trigger: nil)
            center.add(request)
        }
    }

    /// Повторный запуск (например, из Finder), когда значок в строке меню спрятан, — открывает настройки.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    @objc private func openSettings() {
        guard let model = controller?.model else { return }
        SettingsWindowController.shared.show(model: model)
    }

    /// Все настройки живут в отдельном окне; в строке меню — только вход в него и выход.
    private func setupStatusItem() {
        guard let model = controller?.model else { return }
        updateStatusItem(visible: model.settings.menuBarIcon)
        menuBarObserver = model.settings.$menuBarIcon
            .removeDuplicates()
            .sink { [weak self] visible in DispatchQueue.main.async { self?.updateStatusItem(visible: visible) } }
        // Пункты меню пересоздаём на новом языке.
        languageObserver = model.settings.$language
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, let model = self.controller?.model else { return }
                    self.updateStatusItem(visible: false)
                    self.updateStatusItem(visible: model.settings.menuBarIcon)
                }
            }
    }

    private func updateStatusItem(visible: Bool) {
        guard visible else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Notchly")
        let menu = NSMenu()
        let settings = NSMenuItem(title: L("Настройки…"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("Выйти из Notchly"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.model.media.stop()
    }
}
