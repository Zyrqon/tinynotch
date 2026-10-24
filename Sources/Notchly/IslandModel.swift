import AppKit
import SwiftUI
import Combine

enum IslandTab: String, CaseIterable, Identifiable, Codable {
    case home, music, timer, notes, clipboard, shelf, controls, notifications, agents, fo, temp, apps, tools
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "square.grid.2x2.fill"
        case .music: return "music.note"
        case .timer: return "timer"
        case .shelf: return "folder.fill"
        case .notes: return "note.text"
        case .clipboard: return "doc.on.clipboard.fill"
        case .controls: return "slider.horizontal.3"
        case .notifications: return "bell.fill"
        case .agents: return "cpu"
        case .fo: return "bubble.left.fill"
        case .temp: return "thermometer.medium"
        case .apps: return "clock.arrow.circlepath"
        case .tools: return "wrench.and.screwdriver.fill"
        }
    }

    var title: String {
        switch self {
        case .home: return L("Главная")
        case .music: return L("Музыка")
        case .timer: return L("Таймер")
        case .shelf: return L("Файлы")
        case .notes: return L("Заметки и задачи")
        case .clipboard: return L("Буфер обмена")
        case .controls: return L("Управление")
        case .notifications: return L("Уведомления")
        case .agents: return L("Агенты")
        case .fo: return "Fo"
        case .temp: return L("Система")
        case .apps: return L("Программы")
        case .tools: return L("Инструменты")
        }
    }
}

/// Всплывающие события в стиле iPhone: подключили зарядку или наушники.
enum IslandEvent: Equatable {
    case charging(BatteryInfo)
    /// Подключение/отключение блютуз-устройства — карточка в стиле зарядки.
    case device(DeviceBattery)
    /// Подробное окно наушников (по нажатию на компактное).
    case deviceSheet(DeviceBattery)
    case notification(AppNotification)
    case reminder(Reminder)
    case focus(FocusTimer.Transition)
    case timerDone(TimeInterval)
    case alarm(Alarm)
    /// Статус печати с принтера (Bambu Lab).
    case printer(PrinterStatus)
    /// Разблокировка Mac — приветственная карточка в стиле зарядки.
    case wake
    /// Одноразовый код (OTP), выловленный из буфера обмена.
    case otp(String)
    /// Завершённая загрузка из браузера.
    case download(path: String, bytes: Int64)

    /// Имя наушников, если это карточка подключения.
    var deviceName: String? {
        switch self {
        case .device(let d), .deviceSheet(let d): return d.name
        default: return nil
        }
    }

    /// Окно, которое не закрывается по нажатию (в нём свои кнопки).
    var isDevice: Bool { if case .deviceSheet = self { return true } else { return false } }
    /// Компактное событие по бокам выреза — без «капли».
    var isCompact: Bool { false }

    var size: CGSize {
        switch self {
        case .charging: return IslandMetrics.eventSize
        case .device: return IslandMetrics.eventSize
        case .deviceSheet: return IslandMetrics.deviceSheetSize
        case .notification: return IslandMetrics.notificationSize
        case .printer: return IslandMetrics.eventSize
        case .wake: return IslandMetrics.eventSize
        case .otp, .download: return IslandMetrics.eventSize
        case .reminder, .focus, .timerDone, .alarm: return IslandMetrics.reminderSize
        }
    }

    /// Уведомления и напоминания ждут в очереди, пока показана другая карточка.
    var isQueued: Bool {
        switch self {
        case .notification, .reminder, .focus, .timerDone, .alarm, .otp, .download: return true
        default: return false
        }
    }

    var bottomRadius: CGFloat {
        switch self {
        case .charging: return 32
        case .device: return 32
        case .deviceSheet: return 42
        case .printer: return 32
        case .wake: return 32
        case .notification, .reminder, .focus, .timerDone, .alarm: return 28
        case .otp, .download: return 32
        }
    }

    var duration: TimeInterval {
        switch self {
        case .charging: return 4.5
        case .device: return 4.5
        case .deviceSheet: return 10
        case .notification: return 4
        case .reminder, .focus: return 8
        case .timerDone: return 10
        case .alarm: return 30
        case .printer: return 12
        case .wake: return 3.5
        case .otp: return 8
        case .download: return 4.5
        }
    }
}

struct HUDState: Equatable {
    enum Kind { case volume, brightness }
    var kind: Kind
    var value: Float
    var muted: Bool = false
}

enum IslandMetrics {
    static let expandedWidth: CGFloat = 640
    static let expandedContentHeight: CGFloat = 180
    static let compactWing: CGFloat = 40
    static let hudWing: CGFloat = 72
    static let peekWing: CGFloat = 56
    static let peekExtraHeight: CGFloat = 34
    static let eventSize = CGSize(width: 440, height: 118)
    static let deviceSheetSize = CGSize(width: 380, height: 236)
    static let notificationSize = CGSize(width: 430, height: 90)
    static let reminderSize = CGSize(width: 520, height: 118)
    static let focusWing: CGFloat = 56
    static let deviceWing: CGFloat = 84
    /// Запас окна вокруг острова, чтобы тень и пружинная анимация не обрезались.
    static let windowSize = CGSize(width: 760, height: 320)
    static let spring = Animation.spring(response: 0.46, dampingFraction: 0.84)
    static let softSpring = Animation.spring(response: 0.55, dampingFraction: 0.9)
    /// Сворачивание: без отскока, неспешно, но и не затянуто.
    static let collapse = Animation.spring(response: 0.6, dampingFraction: 1)
    /// Раскрытие: шторка плавно, но шустро опускается из выреза, без отскока.
    static let open = Animation.spring(response: 0.44, dampingFraction: 0.9)
    /// Виджеты выходят снизу, когда шторка уже почти опустилась.
    static let contentIn = Animation.easeOut(duration: 0.3)
    static let contentInDelay: TimeInterval = 0.12
    /// Закрытие: сначала гаснет содержимое, затем форма мягко, без рывков, уходит в вырез.
    static let contentOut = Animation.easeOut(duration: 0.14)
    static let closeDelay: TimeInterval = 0.1
    static let close = Animation.spring(response: 0.5, dampingFraction: 1)
}

final class IslandModel: ObservableObject {
    /// Паки инструментов (аддоны).
    let toolPacks = ToolPackManager.shared
    @Published var isExpanded = false
    /// Видно ли содержимое раскрытого острова. Отдельно от isExpanded: при закрытии оно гаснет раньше формы.
    @Published var expandedContentVisible = false
    private var phaseWork: DispatchWorkItem?
    /// Идёт закрытие: содержимое уже гаснет, форма вот-вот свернётся.
    private var closing = false
    @Published var tab: IslandTab {
        didSet {
            if tab == .notifications || oldValue == .notifications { markNotificationsSeen() }
            if tab != .notifications { UserDefaults.standard.set(tab.rawValue, forKey: "island.tab") }
        }
    }
    /// Всё, что пришло раньше этого момента, считается просмотренным (для счётчика на колокольчике).
    @Published private(set) var notificationsSeenAt =
        UserDefaults.standard.object(forKey: "notifications.seen") as? Date ?? .distantPast
    @Published var hud: HUDState?
    @Published var peek = false
    @Published var isDropTargeted = false
    /// Короткое уведомление «скопировано из …» по бокам выреза.
    @Published var clipPeek: ClipGroup?
    @Published var event: IslandEvent?
    /// Карточка события раскрыта. Сначала из выреза опускается «капля», потом она растекается в карточку.
    @Published var eventExpanded = false
    private var eventQueue: [IslandEvent] = []
    /// Пока курсор над карточкой события, она не закрывается сама.
    var eventHovered = false
    @Published var notchSize = CGSize(width: 200, height: 32)
    @Published var hasPhysicalNotch = true
    /// Насколько окно «Инструментов» вытянуто вниз за ручку, в пунктах. 0 = стандартная высота.
    @Published var toolsExtra: CGFloat = {
        let raw = UserDefaults.standard.double(forKey: "island.toolsExtra")
        return raw <= 0 ? 0 : min(420, CGFloat(raw))
    }() {
        didSet { UserDefaults.standard.set(Double(toolsExtra), forKey: "island.toolsExtra") }
    }
    /// Размер холста окна: в раскрытых инструментах — вытянутый вниз, иначе стандартный.
    /// Максимальная высота окна при раскрытом острове: с запасом на полную тягу полоски.
    /// Окно при раскрытом острове всегда такого размера и никогда не анимируется: оно прозрачное,
    /// а его пустой низ не перехватывает мышь (панель игнорирует события вне острова).
    /// Анимируется только сам остров — поэтому все вкладки открываются одинаково плавно.
    var maxWindowHeight: CGFloat { IslandMetrics.windowSize.height + 420 }

    var windowSize: CGSize {
        tab == .tools && isExpanded
            ? CGSize(width: IslandMetrics.windowSize.width,
                     height: IslandMetrics.windowSize.height + toolsExtra)
            : IslandMetrics.windowSize
    }

    let media = MediaController()
    let volume = VolumeController()
    let brightness = BrightnessController()
    let mixer = AppAudioMixer()
    let shelf: ShelfStore
    let notes: NotesStore
    let clipboard: ClipboardMonitor
    let tasks: TasksStore
    let gemini = GeminiAssistant()
    let batteries = DeviceBatteryMonitor()
    let keys = MediaKeyInterceptor()
    let weather: WeatherService
    let vault = KeyVault()
    let gmail = GmailClient()
    let systemNotifications = SystemNotificationsReader()
    let reminders: ReminderCenter
    let focus = FocusTimer()
    let countdown = CountdownTimer()
    let alarms: AlarmStore
    let settings: AppSettings
    /// Конвертер файлов: дроп на остров открывает кольцо форматов, всё конвертируется локально.
    let converter = FileConverterModel()
    /// Уборщик памяти: закрывает простаивающие браузеры, пока работают агенты.
    let janitor = MemoryJanitor()
    /// Ловушка одноразовых кодов: следит за буфером обмена.
    let otpWatcher = OtpWatcher()
    /// Завершённые загрузки в «Загрузках».
    let downloadWatcher = DownloadWatcher()
    /// Недавно запущенные приложения.
    let recentApps = RecentApps()

    lazy var sysMonitor = SysMonitor()
    /// Quake-терминал: один общий zsh на всё время работы острова.
    /// Слежение за запущенными codex/opencode: ждёт ли кто-то подтверждения.
    let agents = AgentsStore()
    /// Пульс: статусы от плагинов (opencode) и принтера (Bambu Lab).
    let bambu = BambuMonitor()
    var hub: StatusHub!
    let foChat = FoChatModel()
    /// Командная строка агентов: запуск opencode прямо с острова.
    let runner = AgentRunner()
    private let screenshotWatcher = ScreenshotFileWatcher()
    /// Только для GIF в README: форма и видимость содержимого в промежуточном кадре анимации.
    struct DebugFrame: Equatable { var size: CGSize; var top: CGFloat; var bottom: CGFloat; var content: Double }
    @Published var debugFrame: DebugFrame?
    /// Открыто окно настроек: остров стоит раскрытым, чтобы изменения было видно сразу.
    @Published var settingsOpen = false

    private var hudTask: DispatchWorkItem?
    private var peekTask: DispatchWorkItem?
    private var clipTask: DispatchWorkItem?
    private var eventTask: DispatchWorkItem?
    private var bag = Set<AnyCancellable>()

    /// persistent = false — для снапшотов: ничего не читаем и не пишем на диск.
    init(persistent: Bool = true) {
        settings = AppSettings(persistent: persistent)
        clipboard = ClipboardMonitor(persistent: persistent)
        shelf = ShelfStore(persistent: persistent)
        notes = NotesStore(persistent: persistent)
        tasks = TasksStore(persistent: persistent)
        reminders = ReminderCenter(tasks: tasks)
        weather = WeatherService(live: persistent)
        alarms = AlarmStore(persistent: persistent)
        tab = IslandTab(rawValue: UserDefaults.standard.string(forKey: "island.tab") ?? "") ?? .home
        if tab == .notifications { tab = .home }  // раздел уведомлений пока убран
        agents.onApproval = { [weak self] title in self?.showAgentApproval(title) }
        agents.onFinish = { [weak self] title in self?.showAgentFinished(title) }
        agents.start()
        bambu.onStatus = { [weak self] p in self?.pushPrinter(p) }
        bambu.reader = { [weak self] in
            (self?.settings.bambuEnabled ?? false, self?.settings.bambuIP ?? "", self?.settings.bambuAccessCode ?? "")
        }
        bambu.start()
        // Ловушка одноразовых кодов из буфера обмена.
        otpWatcher.onCode = { [weak self] code in
            guard self?.settings.otpTrap == true else { return }
            self?.showEvent(.otp(code))
        }
        // Завершённые загрузки из «Загрузок».
        downloadWatcher.onDone = { [weak self] path, bytes in
            guard self?.settings.downloadAlerts == true else { return }
            self?.showEvent(.download(path: path, bytes: bytes))
        }
        if persistent {
            otpWatcher.start()
            downloadWatcher.start()
            recentApps.start()
        }
        hub = StatusHub(model: self)
        hub.start()

        // Приветственная анимация при разблокировке Mac.
        UnlockWatcher.shared.onUnlock = { [weak self] in self?.playWake() }

        // Хоткей вызова островка (настраивается в настройках).
        HotkeyCenter.shared.handler = { [weak self] in self?.toggleByHotkey() }
        HotkeyCenter.shared.install(keyCode: UInt32(settings.hotkeyKeyCode), modsRaw: settings.hotkeyMods)
        Publishers.CombineLatest(settings.$hotkeyKeyCode, settings.$hotkeyMods)
            .dropFirst()
            .sink { key, mods in HotkeyCenter.shared.install(keyCode: UInt32(key), modsRaw: mods) }
            .store(in: &bag)

        keys.handler = { [weak self] key, fine in self?.handleKey(key, fine: fine) }
        clipboard.onCopy = { [weak self] group in self?.showClipPeek(group) }
        batteries.onChargerConnected = { [weak self] info in
            guard let self, self.settings.chargingCard else { return }
            self.showEvent(.charging(info))
        }
        batteries.onChargerDisconnected = { [weak self] info in
            guard let self, self.settings.chargingCard else { return }
            self.showEvent(.charging(info))
        }
        batteries.onAudioDeviceConnected = { [weak self] device in
            guard let self, self.settings.headphonesCard else { return }
            self.showEvent(.device(device))
        }
        batteries.onAudioDeviceUpdated = { [weak self] device in self?.updateDevice(device) }
        batteries.onDeviceDisconnected = { [weak self] device in
            guard let self, self.settings.headphonesCard else { return }
            self.showEvent(.device(device))
        }
        systemNotifications.onNew = { [weak self] item in self?.showNotification(item) }
        reminders.onFire = { [weak self] reminder in self?.presentReminder(reminder) }
        focus.onTransition = { [weak self] transition in
            self?.chime()
            self?.presentWhenCollapsed(.focus(transition))
        }
        countdown.onFinish = { [weak self] duration in
            self?.chime(times: 2)
            self?.presentWhenCollapsed(.timerDone(duration))
        }
        alarms.onFire = { [weak self] alarm in
            self?.chime(times: 4)
            self?.presentWhenCollapsed(.alarm(alarm))
        }
        if persistent { alarms.start() }
        converter.onDone = { [weak self] summary in
            self?.showEvent(.notification(AppNotification(
                id: "convert-\(UUID().uuidString)", bundleID: "dev.notchly.app",
                title: L("Конвертер"), subtitle: "", body: summary, date: Date())))
        }
        converter.onSendToShelf = { [weak self] urls in
            guard let self else { return }
            self.shelf.add(urls)
            self.tab = .shelf
        }
        janitor.isEnabled = { [weak self] in self?.settings.janitorEnabled ?? false }
        janitor.idleMinutes = { [weak self] in self?.settings.janitorIdleMinutes ?? 10 }
        janitor.onlyWithAgents = { [weak self] in self?.settings.janitorOnlyWithAgents ?? true }
        janitor.isAgentActive = { [weak self] in self?.agents.sessions.contains { $0.state != .idle } ?? false }
        janitor.onFreed = { [weak self] title, body in
            guard let self, self.settings.janitorEnabled else { return }
            self.showEvent(.notification(AppNotification(
                id: "janitor-\(UUID().uuidString)", bundleID: "dev.notchly.app",
                title: title, subtitle: "", body: body, date: Date())))
        }
        if persistent { janitor.start() }
        countdown.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { withAnimation(IslandMetrics.softSpring) { self?.objectWillChange.send() } }
            }
            .store(in: &bag)
        // Таймер фокуса меняет форму свёрнутого острова.
        focus.$phase
            .removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { withAnimation(IslandMetrics.softSpring) { self?.objectWillChange.send() } } }
            .store(in: &bag)
        if persistent { reminders.start() }
        gmail.onNew = { [weak self] mail in
            guard self?.settings.gmailNotifications == true else { return }
            self?.showNotification(AppNotification(
                id: "gmail-\(mail.id)", bundleID: AppNotification.gmailID, title: mail.senderName,
                subtitle: "", body: mail.subject, date: mail.date))
        }

        volume.onExternalChange = { [weak self] value, muted in
            self?.showHUD(HUDState(kind: .volume, value: value, muted: muted))
        }
        brightness.onExternalChange = { [weak self] value in
            self?.showHUD(HUDState(kind: .brightness, value: value))
        }
        media.onTrackChange = { [weak self] in self?.trackChanged() }

        applySettings()
        settings.objectWillChange
            .sink { [weak self] _ in
                // objectWillChange приходит до изменения — применяем уже новые значения.
                DispatchQueue.main.async {
                    self?.applySettings()
                    withAnimation(IslandMetrics.softSpring) { self?.objectWillChange.send() }
                }
            }
            .store(in: &bag)
        if persistent {
            screenshotWatcher.onNew = { [weak self] url in self?.clipboard.shots.add(fileURL: url) }
        }

        // Пересчитываем форму острова, когда меняется состояние плеера.
        media.$showsLiveActivity
            .removeDuplicates()
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
    }

    // MARK: - Геометрия

    var topRadius: CGFloat { debugFrame?.top ?? (isExpanded ? 14 : 7) }

    var bottomRadius: CGFloat {
        let base: CGFloat
        if let debugFrame { base = debugFrame.bottom }
        else if isExpanded { base = 34 }
        else if let event {
            if event.isCompact { base = hasPhysicalNotch ? 11 : 14 }
            else { base = eventExpanded ? event.bottomRadius : 22 }
        }
        else if peek && media.hasTrack { base = 20 }
        else { base = hasPhysicalNotch ? 11 : 14 }
        return base * CGFloat(settings.radiusScale)
    }

    /// Высота контента в раскрытом состоянии. На вкладке «Агенты» остров растёт вниз
    /// под число активных сессий (как у vibe-island), на остальных вкладках — константа.
    var expandedContentHeightLive: CGFloat {
        // Конвертер: компактная высота под шапку и ряд кнопок форматов,
        // чтобы над панелью не оставалась пустая полоса.
        if converter.isOpen { return 104 }
        if tab == .apps { return 280 }
        // Инструменты: страница рассчитана на полную высоту окна (320 + тяга за полоску),
        // поэтому остров в этой вкладке обязан быть выше стандартных 180.
        if tab == .tools { return IslandMetrics.windowSize.height - notchSize.height }
        guard tab == .agents else { return IslandMetrics.expandedContentHeight }
        let rows = CGFloat(max(agents.sessions.filter { $0.state != .idle }.count, 1))
        // Шапка 16 + отступ 12 + карточка ~50 (паддинги 18 + две строки) + 6 между карточками + 6 снизу.
        let needed = 16 + 12 + 66 + rows * 50 + max(rows - 1, 0) * 6 + 6
        return max(IslandMetrics.expandedContentHeight, min(needed, 420))
    }

    /// Размер «тела» острова без боковых изгибов у верхней кромки.
    var bodySize: CGSize {
        let n = notchSize
        if isExpanded {
            return CGSize(width: IslandMetrics.expandedWidth, height: n.height + expandedContentHeightLive)
        }
        if let event {
            if event.isCompact {
                return CGSize(width: n.width + IslandMetrics.deviceWing * 2, height: n.height)
            }
            if !eventExpanded {
                return CGSize(width: n.width + 18, height: n.height + 24)
            }
            let size = event.size
            return CGSize(width: size.width, height: n.height + size.height)
        }
        if hud != nil || clipPeek != nil {
            return CGSize(width: n.width + IslandMetrics.hudWing * 2, height: n.height)
        }
        if peek && media.hasTrack {
            return CGSize(width: n.width + IslandMetrics.peekWing * 2, height: n.height + IslandMetrics.peekExtraHeight)
        }
        if focus.isActive || countdown.isActive {
            return CGSize(width: n.width + IslandMetrics.focusWing * 2, height: n.height)
        }
        if showsMusicActivity {
            return CGSize(width: n.width + IslandMetrics.compactWing * 2, height: n.height)
        }
        return n
    }

    /// Полный размер фигуры с учётом изгибов у верхней кромки.
    var shapeSize: CGSize {
        if let debugFrame { return debugFrame.size }
        let base = CGSize(width: bodySize.width + topRadius * 2, height: bodySize.height)
        return base
    }

    /// Живая активность музыки в свёрнутом острове (можно выключить в настройках).
    var showsMusicActivity: Bool { media.showsLiveActivity && settings.musicActivity }

    // MARK: - Настройки

    /// Переносит настройки в службы, которые о них знать не должны.
    private func applySettings() {
        clipboard.recordsText = settings.clipboardHistory
        clipboard.recordsImages = settings.screenshots
        keys.isEnabled = settings.hud
        if settings.screenshots && settings.screenshotFiles && clipboard.shots.isPersistent {
            screenshotWatcher.start()
        } else {
            screenshotWatcher.stop()
        }
        // Спрятанная вкладка не может оставаться открытой.
        if !settings.isVisible(tab) { tab = .home }
    }

    private func chime(times: Int = 1) {
        if settings.sounds { SoftChime.play(times: times) }
    }

    // MARK: - Состояния

    private func markNotificationsSeen() {
        notificationsSeenAt = Date()
        UserDefaults.standard.set(notificationsSeenAt, forKey: "notifications.seen")
    }

    func expand(to tab: IslandTab? = nil) {
        if let tab {
            self.tab = tab
        } else if !isExpanded && settings.openOnHome {
            // Каждое открытие начинается с главной (если так выбрано в настройках).
            self.tab = .home
        }
        guard !isExpanded || closing else { return }
        phaseWork?.cancel()
        if closing {
            closing = false
            // Остров как раз закрывался (содержимое гасло) — просто возвращаем содержимое.
            withAnimation(IslandMetrics.contentIn) { expandedContentVisible = true }
            return
        }
        hud = nil
        peek = false
        clipPeek = nil
        event = nil
        eventExpanded = false
        eventQueue.removeAll()
        if self.tab == .home {
            batteries.refresh()
            weather.refresh()
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        // Шторка опускается…
        withAnimation(IslandMetrics.open) { isExpanded = true }
        // …и следом снизу выходят виджеты.
        let work = DispatchWorkItem { [weak self] in
            withAnimation(IslandMetrics.contentIn) { self?.expandedContentVisible = true }
        }
        phaseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + IslandMetrics.contentInDelay, execute: work)
    }

    func collapse() {
        guard isExpanded, !settingsOpen else { return }
        vault.lock()
        guard !closing else { return }
        phaseWork?.cancel()
        closing = true
        // Сначала гаснет содержимое…
        withAnimation(IslandMetrics.contentOut) { expandedContentVisible = false }
        // …потом форма плавно уходит в вырез.
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.closing = false
            withAnimation(IslandMetrics.close) { self.isExpanded = false }
        }
        phaseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + IslandMetrics.closeDelay, execute: work)
    }

    /// Вызов с клавиатуры: открыл/закрыл.
    func toggleByHotkey() {
        if isExpanded { collapse() } else { expand() }
    }

    func showEvent(_ event: IslandEvent) {
        if case .device(let d) = event { DeviceBatteryMonitor.btlog("showEvent \(d.name) connected=\(d.isConnected) островОткрыт=\(isExpanded)") }
        guard !isExpanded else { return }
        // Наушники сообщают о подключении по нескольку раз (разные профили Bluetooth). Повтор не должен
        // заменять уже показанную карточку с зарядом на пустую — обновляем её на месте.
        if case .device(let device) = event, let shown = self.event?.deviceName,
           DeviceBatteryMonitor.baseName(shown) == DeviceBatteryMonitor.baseName(device.name) {
            return updateDevice(device)
        }
        // Пока показана одна карточка, следующие уведомления ждут своей очереди.
        if self.event != nil, event.isQueued {
            eventQueue.append(event)
            return
        }
        eventTask?.cancel()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        if event.isCompact {
            // Компактное событие просто раздвигает остров в стороны, как HUD громкости.
            withAnimation(IslandMetrics.spring) {
                hud = nil
                peek = false
                clipPeek = nil
                self.event = event
                eventExpanded = true
            }
            scheduleEventDismiss(after: event.duration)
            return
        }
        // «Капля»: сначала узкая капля выпадает из выреза…
        eventExpanded = false
        withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
            hud = nil
            peek = false
            clipPeek = nil
            self.event = event
        }
        // …и почти сразу мягко растекается в карточку.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.event == event else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) { self.eventExpanded = true }
        }
        scheduleEventDismiss(after: event.duration + 0.2)
    }

    /// Напоминание звучит сразу; если остров сейчас открыт, карточка покажется, как только он закроется.
    private func presentReminder(_ reminder: Reminder) {
        guard settings.reminders else { return }
        chime()
        presentWhenCollapsed(.reminder(reminder))
    }

    private func presentWhenCollapsed(_ event: IslandEvent, attempt: Int = 0) {
        guard isExpanded else { return showEvent(event) }
        guard attempt < 150 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.presentWhenCollapsed(event, attempt: attempt + 1)
        }
    }

    /// Во время фокуса уведомления приложений не всплывают — их число покажем в конце подхода.
    /// Агент просит подтверждение: карточка из выреза, как у обычных уведомлений.
    private func showAgentApproval(_ title: String) {
        guard settings.appNotifications else { return }
        if focus.isFocusing { return }
        showEvent(.notification(AppNotification(id: "agents-\(UUID().uuidString)", bundleID: "ru.iabrik.agents",
                                               title: title, subtitle: "", body: L("Ждёт подтверждения"), date: Date())))
    }

    private func showAgentFinished(_ title: String) {
        guard settings.appNotifications else { return }
        showEvent(.notification(AppNotification(id: "agents-done-\(UUID().uuidString)", bundleID: "ru.iabrik.agents",
                                               title: title, subtitle: "", body: L("Задача выполнена"), date: Date())))
    }

    // MARK: Пульс — статусы от плагинов и принтера

    private var lastAgentCard: (kind: String, title: String, at: Date)?
    private var lastPrinterShown: PrinterStatus?

    /// POST /agent из плагина: approval / finished / working.
    func pushAgent(payload: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: String],
              let status = obj["status"] else { return }
        let title = obj["title"] ?? ""
        if let last = lastAgentCard, last.kind == status, last.title == title,
           Date().timeIntervalSince(last.at) < 8 { return }
        lastAgentCard = (status, title, Date())
        switch status {
        case "approval": showAgentApproval(title)
        case "finished": showAgentFinished(title)
        default: break
        }
    }

    func pushPrinter(payload: Data) {
        guard let p = try? JSONDecoder().decode(PrinterStatus.self, from: payload) else { return }
        pushPrinter(p)
    }

    /// Статус печати: пока карточка показана — обновляем на месте, иначе показываем
    /// на смене состояния или каждые 10% прогресса, а не на каждом тике.
    func pushPrinter(_ p: PrinterStatus) {
        if case .printer(let shown) = event {
            guard shown != p else { return }
            withAnimation(.smooth(duration: 0.3)) { event = .printer(p) }
            eventTask?.cancel()
            scheduleEventDismiss(after: 12)
            return
        }
        let previous = lastPrinterShown
        lastPrinterShown = p
        let stateChanged = p.state != previous?.state
        let milestone = p.isPrinting && p.percent > 0 && p.percent - (previous?.percent ?? 0) >= 10
        guard stateChanged || milestone else { return }
        showEvent(.printer(p))
    }

    private func showNotification(_ item: AppNotification) {
        guard item.bundleID == AppNotification.gmailID || settings.appNotifications else { return }
        if focus.isFocusing { return focus.holdNotification() }
        showEvent(.notification(item))
    }

    /// Заряд пришёл позже карточки — обновляем её на месте, не показывая заново.
    func updateDevice(_ device: DeviceBattery) {
        // Пустой заряд не затирает уже известный.
        guard !device.levels.isEmpty else { return }
        // Имя оставляем прежним, меняем только заряд.
        func same(_ shown: DeviceBattery) -> Bool {
            DeviceBatteryMonitor.baseName(shown.name) == DeviceBatteryMonitor.baseName(device.name)
        }
        switch event {
        case .device(var shown) where same(shown):
            shown.levels = device.levels
            withAnimation(.smooth(duration: 0.3)) { event = .device(shown) }
        case .deviceSheet(var shown) where same(shown):
            shown.levels = device.levels
            withAnimation(.smooth(duration: 0.3)) { event = .deviceSheet(shown) }
        default: break
        }
    }

    /// Нажали на компактное событие наушников — показываем подробное окно.
    func showDeviceSheet(_ device: DeviceBattery) {
        eventTask?.cancel()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { event = .deviceSheet(device) }
        scheduleEventDismiss(after: IslandEvent.deviceSheet(device).duration)
    }

    // MARK: - Кнопки в карточках

    func completeReminder(_ reminder: Reminder) {
        if let id = reminder.taskID, tasks.items.first(where: { $0.id == id })?.done == false { tasks.toggle(id) }
        dismissEvent()
    }

    func snoozeReminder(_ reminder: Reminder) {
        reminders.snooze(reminder)
        dismissEvent()
    }

    func startFocus(taskID: UUID? = nil, title: String? = nil) {
        focus.start(taskID: taskID, title: title)
        if event != nil { dismissEvent() }
    }

    private func scheduleEventDismiss(after delay: TimeInterval) {
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.eventHovered { return self.scheduleEventDismiss(after: 1) }
            self.hideEvent()
        }
        eventTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    func dismissEvent() {
        eventTask?.cancel()
        eventHovered = false
        hideEvent()
    }

    /// Сворачиваем карточку обратно в вырез и показываем следующую из очереди.
    private func hideEvent() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.95)) {
            eventExpanded = false
            event = nil
        }
        guard !eventQueue.isEmpty else { return }
        let next = eventQueue.removeFirst()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in self?.showEvent(next) }
    }

    /// Приветственная карточка при разблокировке Mac — в стиле карточек зарядки/подключения.
    func playWake() {
        guard !isExpanded, event == nil, settings.wakeAnimation else { return }
        showEvent(.wake)
    }

    func showHUD(_ state: HUDState) {
        guard !isExpanded, event == nil, settings.hud else { return }
        hudTask?.cancel()
        withAnimation(IslandMetrics.spring) {
            peek = false
            clipPeek = nil
            hud = state
        }
        let task = DispatchWorkItem { [weak self] in
            withAnimation(IslandMetrics.softSpring) { self?.hud = nil }
        }
        hudTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: task)
    }

    private func handleKey(_ key: MediaKeyInterceptor.Key, fine: Bool) {
        switch key {
        case .volumeUp, .volumeDown:
            volume.step(up: key == .volumeUp, fine: fine)
        case .mute:
            volume.toggleMute()
        case .brightnessUp, .brightnessDown:
            brightness.step(up: key == .brightnessUp, fine: fine)
        }
        switch key {
        case .volumeUp, .volumeDown, .mute:
            showHUD(HUDState(kind: .volume, value: volume.volume, muted: volume.isMuted))
        case .brightnessUp, .brightnessDown:
            showHUD(HUDState(kind: .brightness, value: brightness.brightness))
        }
    }

    func showClipPeek(_ group: ClipGroup) {
        guard !isExpanded, hud == nil, event == nil, settings.copiedPeek else { return }
        clipTask?.cancel()
        withAnimation(IslandMetrics.spring) {
            peek = false
            clipPeek = group
        }
        let task = DispatchWorkItem { [weak self] in
            withAnimation(IslandMetrics.softSpring) { self?.clipPeek = nil }
        }
        clipTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: task)
    }

    private var peekedID = ""
    private var trackChangeWork: DispatchWorkItem?

    /// Плееры присылают название, исполнителя и альбом не всегда одним сообщением.
    /// Ждём, пока данные устоятся, и показываем шторку один раз на трек.
    private func trackChanged() {
        trackChangeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.media.hasTrack, self.media.peekID != self.peekedID else { return }
            self.peekedID = self.media.peekID
            self.showPeek()
        }
        trackChangeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    func showPeek() {
        guard !isExpanded, hud == nil, event == nil, media.hasTrack, settings.trackPeek else { return }
        peekTask?.cancel()
        if !peek { withAnimation(IslandMetrics.softSpring) { peek = true } }
        let task = DispatchWorkItem { [weak self] in
            withAnimation(IslandMetrics.softSpring) { self?.peek = false }
        }
        peekTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2, execute: task)
    }
}
