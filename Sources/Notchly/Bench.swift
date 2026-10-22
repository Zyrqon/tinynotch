import SwiftUI

/// `Notchly --bench [сценарий…] [--seconds N]` — замер нагрузки на процессор в типичных состояниях острова.
///
/// Поднимает настоящую панель на месте выреза с тестовыми данными (как снапшоты: ничего не пишет на диск
/// и не трогает мышь), приводит остров в нужное состояние, даёт ему устояться и меряет процессорное время
/// за N секунд: всего процесса и отдельно главного потока. Перед запуском закройте Notchly.
enum Bench {
    struct Scenario {
        var name: String
        var note: String
        var setup: (IslandModel, NSView) -> Void
        /// Вызывается 10 раз в секунду во время замера (для «печати» и открытия/закрытия).
        var tick: ((IslandModel, NSView, Int) -> Void)?
    }

    static let scenarios: [Scenario] = [
        Scenario(name: "collapsed", note: "свёрнут, ничего не играет", setup: { _, _ in }),
        Scenario(name: "music-compact", note: "свёрнут, играет музыка (эквалайзер)", setup: { m, _ in playTrack(m) }),
        Scenario(name: "focus-compact", note: "свёрнут, идёт фокус", setup: { m, _ in m.focus.start(taskID: nil, title: nil) }),
        Scenario(name: "home", note: "главная, музыки нет", setup: { m, _ in m.expand(to: .home) }),
        Scenario(name: "home-charging", note: "главная, MacBook заряжается", setup: { m, _ in
            m.batteries.debugSet(devices: [], phone: nil, mac: BatteryInfo(percent: 64, charging: true, onAC: true))
            m.expand(to: .home)
        }),
        Scenario(name: "home-music", note: "главная, играет музыка", setup: { m, _ in playTrack(m); m.expand(to: .home) }),
        Scenario(name: "music", note: "вкладка музыки, играет", setup: { m, _ in playTrack(m); m.expand(to: .music) }),
        Scenario(name: "controls", note: "вкладка управления", setup: { m, _ in m.expand(to: .controls) }),
        Scenario(name: "notes-typing", note: "заметка, печать 10 символов/с", setup: { m, _ in
            SnapshotFlags.notesMode = .notes
            m.expand(to: .notes)
        }, tick: { _, root, i in
            guard let tv = firstView(of: NSTextView.self, in: root) else { return }
            if tv.window?.firstResponder !== tv {
                tv.window?.makeKey()
                tv.window?.makeFirstResponder(tv)
                // Обычная заметка: заголовок и несколько абзацев, печатаем в конце.
                let paragraph = String(repeating: "Обычный абзац заметки для замера нагрузки. ", count: 8)
                tv.insertText("Список дел на неделю\n" + Array(repeating: paragraph, count: 6).joined(separator: "\n") + "\n",
                              replacementRange: tv.selectedRange())
            }
            tv.insertText(i % 12 == 11 ? " " : "а", replacementRange: tv.selectedRange())
        }),
        Scenario(name: "tasks-typing", note: "новая задача, печать 10 символов/с", setup: { m, _ in
            SnapshotFlags.notesMode = .tasks
            m.tasks.debugSet((0..<8).map { TaskItem(text: "Задача \($0)", time: $0 % 2 == 0 ? "1\($0):00" : nil) })
            m.expand(to: .notes)
        }, tick: { _, root, i in
            guard let field = firstView(of: NSTextField.self, in: root, where: { $0.isEditable }) else { return }
            let window = field.window
            if !(window?.firstResponder is NSTextView) {
                window?.makeKey()
                window?.makeFirstResponder(field)
            }
            (window?.firstResponder as? NSTextView)?.insertText(i % 12 == 11 ? " " : "а", replacementRange: NSRange(location: NSNotFound, length: 0))
        }),
        Scenario(name: "open-close", note: "открыть/закрыть каждые 2 с", setup: { _, _ in }, tick: { m, _, i in
            switch i % 20 {
            case 0: m.expand(to: .home)
            case 10: m.collapse()
            default: break
            }
        }),
        Scenario(name: "open-close-rich", note: "открыть/закрыть: музыка, зарядка, погода", setup: { m, _ in
            playTrack(m)
            m.batteries.debugSet(devices: [], phone: nil, mac: BatteryInfo(percent: 64, charging: true, onAC: true))
        }, tick: { m, _, i in
            switch i % 20 {
            case 0: m.expand(to: .home)
            case 10: m.collapse()
            default: break
            }
        }),
    ]

    static func playTrack(_ model: IslandModel) {
        let art = NSImage(size: NSSize(width: 300, height: 300), flipped: false) { rect in
            NSGradient(colors: [.systemPink, .systemOrange, .systemPurple])?.draw(in: rect, angle: 45)
            return true
        }
        model.media.debugSet(title: "Blinding Lights", artist: "The Weeknd", album: "After Hours",
                             duration: 200, elapsed: 74, playing: true, artwork: art, bundleID: "com.apple.Music")
    }

    static func firstView<T: NSView>(of type: T.Type, in root: NSView, where match: (T) -> Bool = { _ in true }) -> T? {
        if let view = root as? T, match(view) { return view }
        for sub in root.subviews {
            if let found = firstView(of: type, in: sub, where: match) { return found }
        }
        return nil
    }

    /// `--bench open-cost`: сколько миллисекунд процессора главного потока уходит на одно открытие
    /// и одно закрытие острова на каждой вкладке (среднее по 6 циклам, по 1,5 с на фазу).
    @MainActor
    static func openCost(tabs: [IslandTab]) async {
        let model = IslandModel(persistent: false)
        model.weather.debugSet(Weather(temperature: 18, high: 21, low: 12, code: 1, isDay: true, city: "Berlin",
                                       latitude: 52.52, longitude: 13.40))
        playTrack(model)
        model.batteries.debugSet(devices: [], phone: nil, mac: BatteryInfo(percent: 64, charging: true, onAC: true))
        let panel = makePanel(model)
        await sleep(2)
        for tab in tabs {
            var open = 0.0, close = 0.0
            let rounds = 6
            for _ in 0..<rounds {
                let a = cpuTimes().main
                model.expand(to: tab)
                await sleep(1.5)
                let b = cpuTimes().main
                model.collapse()
                await sleep(1.5)
                let c = cpuTimes().main
                open += b - a
                close += c - b
            }
            print(String(format: "%-14@ открытие %5.0f мс   закрытие %5.0f мс", tab.rawValue as NSString,
                         open / Double(rounds) * 1000, close / Double(rounds) * 1000))
            for h in CountingHosting.all {
                print(String(format: "   кадров SwiftUI на цикл: %d, из них %.0f мс в layout()", h.frames / rounds, h.time / Double(rounds) * 1000))
                h.frames = 0; h.time = 0
            }
            fflush(stdout)
        }
        panel.orderOut(nil)
    }

    @MainActor
    private static func makePanel(_ model: IslandModel) -> NotchPanel {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        if screen.safeAreaInsets.top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            model.notchSize = CGSize(width: screen.frame.width - l.width - r.width, height: screen.safeAreaInsets.top)
        } else {
            model.notchSize = CGSize(width: 190, height: 32)
            model.hasPhysicalNotch = false
        }
        let panel = NotchPanel()
        let hosting = CountingHosting(rootView: IslandRootView(model: model, media: model.media, settings: model.settings))
        hosting.sizingOptions = []
        panel.contentView = hosting
        CountingHosting.all = [hosting]
        let size = IslandMetrics.windowSize
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
        return panel
    }

    /// Запускается внутри NSApplication.run(), как живое приложение: вложенный RunLoop меняет частоту кадров.
    @MainActor
    static func run(names: [String], seconds: Double) async {
        SnapshotFlags.isRendering = false
        if names.first == "open-cost" {
            let tabs = names.dropFirst().compactMap(IslandTab.init(rawValue:))
            return await openCost(tabs: tabs.isEmpty ? [.home, .music, .notes, .timer, .controls, .clipboard] : tabs)
        }
        let selected = names.isEmpty ? scenarios : scenarios.filter { names.contains($0.name) }
        for scenario in selected {
            let (total, main) = await measure(scenario, seconds: seconds)
            print(String(format: "%-15@ %6.1f%% %6.1f%%   %@", scenario.name as NSString, total, main, scenario.note as NSString))
            fflush(stdout)
        }
    }

    private static func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    @MainActor
    private static func measure(_ scenario: Scenario, seconds: Double) async -> (Double, Double) {
        let model = IslandModel(persistent: false)
        model.weather.debugSet(Weather(temperature: 18, high: 21, low: 12, code: 1, isDay: true, city: "Berlin",
                                       latitude: 52.52, longitude: 13.40))
        let panel = makePanel(model)
        let hosting = panel.contentView!
        scenario.setup(model, hosting)
        await sleep(2.5)

        let ticker = scenario.tick.map { body in
            Task { @MainActor in
                var tick = 0
                while !Task.isCancelled {
                    body(model, hosting, tick)
                    tick += 1
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }
        let start = cpuTimes()
        let startDate = Date()
        await sleep(seconds)
        let end = cpuTimes()
        let wall = Date().timeIntervalSince(startDate)
        ticker?.cancel()
        panel.orderOut(nil)
        model.media.debugSet(title: "", artist: "", album: "", duration: 0, elapsed: 0, playing: false, artwork: nil, bundleID: nil)
        model.focus.stop()
        await sleep(0.3)
        return ((end.total - start.total) / wall * 100, (end.main - start.main) / wall * 100)
    }

    /// Процессорное время всего процесса и главного потока, в секундах.
    private static func cpuTimes() -> (total: Double, main: Double) {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let total = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
        let thread = pthread_mach_thread_np(pthread_self())
        _ = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        let main = Double(info.user_time.seconds + info.system_time.seconds)
            + Double(info.user_time.microseconds + info.system_time.microseconds) / 1_000_000
        return (total, main)
    }
}

/// Считает кадры SwiftUI (вызовы layout()) и время на них.
final class CountingHosting: NSHostingView<IslandRootView> {
    static var all: [CountingHosting] = []
    var frames = 0
    var time = 0.0
    override func layout() {
        let t = CACurrentMediaTime()
        super.layout()
        time += CACurrentMediaTime() - t
        frames += 1
    }
}
