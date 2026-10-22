import AppKit
import SwiftUI

/// Окно настроек открывается отдельно, прямо под островом. Пока оно открыто, остров стоит раскрытым,
/// и каждое изменение сразу видно на нём.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private weak var model: IslandModel?

    func show(model: IslandModel) {
        self.model = model
        model.settingsOpen = true
        model.expand(to: model.isExpanded ? nil : .controls)
        if window == nil {
            let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 470),
                                        styleMask: [.titled, .closable, .miniaturizable],
                                        backing: .buffered, defer: false)
            window.title = L("Настройки Notchly")
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
            window.setContentSize(NSSize(width: 660, height: 470))
            self.window = window
        }
        guard let window else { return }
        place(window, model: model)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Под раскрытым островом, по центру того же экрана.
    private func place(_ window: NSWindow, model: IslandModel) {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        // Ниже всей прозрачной панели острова, а не только его видимой формы.
        let panelBottom = screen.frame.maxY - IslandMetrics.windowSize.height
        let size = window.frame.size
        var origin = NSPoint(x: screen.frame.midX - size.width / 2, y: panelBottom - 12 - size.height)
        origin.y = max(origin.y, screen.visibleFrame.minY + 8)
        window.setFrameOrigin(origin)
    }

    func updateTitle() { window?.title = L("Настройки Notchly") }

    func windowWillClose(_ notification: Notification) {
        guard let model else { return }
        model.settingsOpen = false
        model.collapse()
    }
}

/// У приложения без меню ⌘W сам не работает — закрываем окно по физической клавише.
private final class SettingsWindow: NSWindow {
    /// Esc закрывает окно, как лист настроек.
    override func cancelOperation(_ sender: Any?) { performClose(nil) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if event.type == .keyDown, flags == [.command] {
            switch event.keyCode {
            case 13: performClose(nil); return true                                        // W
            case 8: if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) { return true }
            case 9: if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) { return true }
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Содержимое

struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general = "Основные", tabs = "Вкладки", island = "Остров", notifications = "Уведомления",
             clipboard = "Буфер обмена", about = "О Notchly"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .tabs: return "rectangle.3.group.fill"
            case .island: return "capsule.fill"
            case .notifications: return "bell.badge.fill"
            case .clipboard: return "doc.on.clipboard.fill"
            case .about: return "info.circle.fill"
            }
        }
        var tint: Color {
            switch self {
            case .general: return .gray
            case .tabs: return .blue
            case .island: return .indigo
            case .notifications: return .red
            case .clipboard: return .orange
            case .about: return .teal
            }
        }
    }

    var model: IslandModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var clipboard: ClipboardMonitor
    @ObservedObject var shots: ScreenshotStore
    @ViewState private var section: Pane? = SnapshotFlags.settingsPane

    init(model: IslandModel) {
        self.model = model
        settings = model.settings
        clipboard = model.clipboard
        shots = model.clipboard.shots
    }

    var body: some View {
        HStack(spacing: 0) {
            List(Pane.allCases, selection: $section) { item in
                Label {
                    Text(L(item.rawValue))
                } icon: {
                    Image(systemName: item.icon)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(item.tint.gradient))
                }
                .tag(item)
                .padding(.vertical, 2)
            }
            .listStyle(.sidebar)
            .frame(width: 190)

            Divider()

            Group {
                switch section ?? .general {
                case .general: general
                case .tabs: tabs
                case .island: island
                case .notifications: notifications
                case .clipboard: clipboardPane
                case .about: about
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 620, minHeight: 440)
        .id(settings.language)
        .onChange(of: settings.language) { _, _ in SettingsWindowController.shared.updateTitle() }
        .onChange(of: section) { _, value in
            // Остров показывает то, что сейчас настраивается.
            switch value {
            case .clipboard: showTab(.clipboard)
            case .tabs, .general: break
            default: showTab(.home)
            }
        }
    }

    private func showTab(_ tab: IslandTab) {
        guard settings.isVisible(tab) else { return }
        withAnimation(.spring(response: 0.46, dampingFraction: 0.9)) { model.tab = tab }
    }

    // MARK: Основные

    private var general: some View {
        Form {
            Section {
                Picker(L("Язык"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(L("Язык интерфейса меняется сразу, без перезапуска."))
                    .foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Toggle(L("Запускать при входе в систему"), isOn: Binding(
                    get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 }))
                Toggle(L("Значок в строке меню"), isOn: $settings.menuBarIcon)
            } footer: {
                if !settings.menuBarIcon {
                    Text(L("Без значка настройки открываются из вкладки «Управление» или повторным запуском Notchly."))
                        .foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Section {
                Picker(L("Открывать на вкладке"), selection: $settings.openOnHome) {
                    Text(L("Главная")).tag(true)
                    Text(L("Последняя открытая")).tag(false)
                }
                LabeledContent(L("Закрывать, когда курсор ушёл, через")) {
                    Text(L("%@ с", "\(settings.closeDelay.formatted(.number.precision(.fractionLength(1)).locale(Loc.locale)))"))
                        .monospacedDigit()
                }
                Slider(value: Binding(get: { settings.closeDelay },
                                      set: { settings.closeDelay = ($0 * 10).rounded() / 10 }),
                       in: AppSettings.closeDelayRange) {
                    Text(L("Задержка"))
                } minimumValueLabel: {
                    Image(systemName: "hare")
                } maximumValueLabel: {
                    Image(systemName: "tortoise")
                }
                .labelsHidden()
            } header: {
                Text(L("Раскрытый остров"))
            } footer: {
                Text(L("Клик мимо острова закрывает его сразу."))
                    .foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Вкладки

    private var tabs: some View {
        Form {
            ForEach([TabSlot.Side.leading, .trailing], id: \.self) { side in
                Section {
                    let slots = settings.tabs.filter { $0.side == side }
                    ForEach(slots) { slot in
                        TabSlotRow(slot: slot,
                                   isFirst: slot.tab == slots.first?.tab,
                                   isLast: slot.tab == slots.last?.tab,
                                   move: { moveTab(slot, by: $0) },
                                   switchSide: { switchSide(slot) },
                                   setVisible: { setVisible(slot, $0) })
                    }
                    if slots.isEmpty {
                        Text(L("Пусто")).foregroundStyle(.secondary)
                    }
                } header: {
                    Text(side == .leading ? L("Слева от выреза") : L("Справа от выреза"))
                } footer: {
                    if side == .trailing {
                        HStack(alignment: .top) {
                            Text(L("Колокольчик уведомлений всегда стоит справа, последним. Главная всегда видна."))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Spacer()
                            Button(L("Как было")) { animateTabs { settings.resetTabs() } }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func animateTabs(_ change: () -> Void) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { change() }
    }

    /// Сдвиг внутри своей стороны: меняемся местами с соседом по этой же стороне.
    private func moveTab(_ slot: TabSlot, by delta: Int) {
        var all = settings.tabs
        let sameSide = all.indices.filter { all[$0].side == slot.side }
        guard let pos = sameSide.firstIndex(where: { all[$0].tab == slot.tab }),
              sameSide.indices.contains(pos + delta) else { return }
        all.swapAt(sameSide[pos], sameSide[pos + delta])
        animateTabs { settings.tabs = all }
    }

    /// На другую сторону — в её конец.
    private func switchSide(_ slot: TabSlot) {
        var all = settings.tabs
        all.removeAll { $0.tab == slot.tab }
        var moved = slot
        moved.side = slot.side == .leading ? .trailing : .leading
        all.append(moved)
        animateTabs { settings.tabs = all }
    }

    private func setVisible(_ slot: TabSlot, _ visible: Bool) {
        var all = settings.tabs
        guard let i = all.firstIndex(where: { $0.tab == slot.tab }) else { return }
        all[i].visible = visible
        animateTabs { settings.tabs = all }
    }

    // MARK: Остров

    private var island: some View {
        Form {
            Section(L("Свёрнутый остров")) {
                Toggle(L("Музыка: обложка и эквалайзер по бокам выреза"), isOn: $settings.musicActivity)
                Toggle(L("Шторка с названием нового трека"), isOn: $settings.trackPeek)
                Toggle(L("Громкость и яркость вместо системного индикатора"), isOn: $settings.hud)
                Toggle(L("«Скопировано» при копировании"), isOn: $settings.copiedPeek)
                Toggle(L("Ловушка одноразовых кодов"), isOn: $settings.otpTrap)
                Toggle(L("Карточка завершённой загрузки"), isOn: $settings.downloadAlerts)
            }
            Section(L("Карточки")) {
                Toggle(L("Подключили зарядку"), isOn: $settings.chargingCard)
                Toggle(L("Подключили блютуз-устройство"), isOn: $settings.headphonesCard)
            }
            Section(L("Анимации")) {
                Toggle(L("Приветствие при разблокировке"), isOn: $settings.wakeAnimation)
                Toggle(L("Пружинка при появлении уведомлений"), isOn: $settings.notificationPop)
            }
            Section {
                HotkeyRecorder(keyCode: $settings.hotkeyKeyCode, mods: $settings.hotkeyMods, label: $settings.hotkeyLabel)
                    .frame(height: 28)
                if settings.hotkeyKeyCode != 0 {
                    Button(L("Сбросить")) {
                        settings.hotkeyKeyCode = 0
                        settings.hotkeyMods = 0
                        settings.hotkeyLabel = ""
                    }
                }
            } header: {
                Text(L("Вызов с клавиатуры"))
            } footer: {
                Text(L("Кликни поле и нажми сочетание клавиш, например ⌥⌘Space: островок откроется из любого места. Нужен хотя бы один модификатор (⌘, ⌃ или ⌥)."))
                    .foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Toggle(L("Закрывать простаивающие браузеры"), isOn: $settings.janitorEnabled)
                if settings.janitorEnabled {
                    Toggle(L("Только пока работает агент"), isOn: $settings.janitorOnlyWithAgents)
                    Picker(L("Простаивает дольше"), selection: $settings.janitorIdleMinutes) {
                        Text(L("5 минут")).tag(5)
                        Text(L("10 минут")).tag(10)
                        Text(L("15 минут")).tag(15)
                        Text(L("20 минут")).tag(20)
                    }
                }
            } header: {
                Text(L("Память"))
            } footer: {
                Text(L("Пока ты не трогаешь браузер, островок закрывает его и возвращает память. Закрытие аккуратное, вкладки восстановятся при следующем запуске."))
                    .foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Toggle(L("Статус печати Bambu Lab"), isOn: $settings.bambuEnabled)
                if settings.bambuEnabled {
                    TextField(L("IP принтера"), text: $settings.bambuIP)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    SecureField(L("Код доступа LAN"), text: $settings.bambuAccessCode)
                        .textFieldStyle(.roundedBorder)
                    Text(L("IP и код доступа есть в приложении Bambu Handy: Устройство → Настройки → «Код доступа LAN»."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text(L("Принтер"))
            } footer: {
                Text(L("Остров слушает принтер по локальной сети и показывает прогресс, остаток времени и температуры."))
                    .foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }
            Section(L("Вид")) {
                ColorPicker(L("Акцентный цвет"), selection: $settings.accent, supportsOpacity: false)
                ColorPicker(L("Фон острова"), selection: $settings.islandBackground, supportsOpacity: false)
                HStack {
                    Text(L("Скругление углов"))
                    Slider(value: $settings.radiusScale, in: 0.7...1.6, step: 0.05)
                    Text("\(Int(settings.radiusScale * 100))%")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Уведомления

    private var notifications: some View {
        Form {
            Section {
                Toggle(L("Уведомления приложений"), isOn: $settings.appNotifications)
                Toggle(L("Новые письма Gmail"), isOn: $settings.gmailNotifications)
                Toggle(L("Напоминания о задачах и встречах"), isOn: $settings.reminders)
            } header: {
                Text(L("Показывать на острове"))
            } footer: {
                Text(L("Всё пришедшее остаётся в центре уведомлений (колокольчик) — выключается только всплывающая карточка. Во время «Помидора» уведомления копятся молча."))
                    .foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Toggle(L("Тихий сигнал: напоминания, таймер, будильник"), isOn: $settings.sounds)
                Button(L("Прослушать")) { SoftChime.play() }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Буфер обмена

    @ViewState private var confirmHistory = false
    @ViewState private var confirmShots = false

    private var clipboardPane: some View {
        Form {
            Section(L("Текст")) {
                Toggle(L("Запоминать скопированный текст"), isOn: $settings.clipboardHistory)
                Picker(L("Хранить историю"), selection: Binding(
                    get: { clipboard.retentionDays }, set: { clipboard.retentionDays = $0 })) {
                    ForEach(ClipboardMonitor.retentionOptions, id: \.self) { days in
                        Text(Self.retentionTitle(days)).tag(days)
                    }
                }
                .disabled(!settings.clipboardHistory)
                Button(L("Очистить историю…"), role: .destructive) { confirmHistory = true }
                    .disabled(clipboard.groups.isEmpty)
                    .confirmationDialog(L("Очистить всю историю буфера обмена?"), isPresented: $confirmHistory) {
                        Button(L("Очистить"), role: .destructive) { clipboard.clear() }
                    }
            }
            Section {
                Toggle(L("Сохранять снимки экрана и скопированные картинки"), isOn: $settings.screenshots)
                Toggle(L("Брать и снимки, сохранённые на рабочий стол"), isOn: $settings.screenshotFiles)
                    .disabled(!settings.screenshots)
                Picker(L("Хранить снимки"), selection: Binding(
                    get: { shots.retentionDays }, set: { shots.retentionDays = $0 })) {
                    ForEach(ScreenshotStore.retentionOptions, id: \.self) { days in
                        Text(Self.retentionTitle(days)).tag(days)
                    }
                }
                .disabled(!settings.screenshots)
                LabeledContent(L("Занято")) {
                    Text(L("%@ шт. · %@", "\(shots.items.count)", "\(ByteCountFormatter.string(fromByteCount: Int64(shots.totalBytes), countStyle: .file))"))
                        .monospacedDigit()
                }
                Button(L("Удалить все снимки…"), role: .destructive) { confirmShots = true }
                    .disabled(shots.items.isEmpty)
                    .confirmationDialog(L("Удалить все сохранённые снимки?"), isPresented: $confirmShots) {
                        Button(L("Удалить"), role: .destructive) { shots.clear() }
                    }
            } header: {
                Text(L("Снимки"))
            } footer: {
                Text(L("Снимок весит 1–8 МБ, поэтому они хранятся недолго: не больше %@ штук, старые удаляются сами. Снимки с рабочего стола копируются — оригиналы остаются на месте. Для них macOS один раз спросит доступ к папке.", "\(ScreenshotStore.maxItems)"))
                    .foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }

    static func retentionTitle(_ days: Int) -> String {
        switch days {
        case 0: return L("Бесконечно")
        default: return "\(days) " + Loc.plural(days, "день", "дня", "дней", en: "day", enPlural: "days")
        }
    }

    // MARK: О программе

    private var about: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 88, height: 88)
                    Text("Notchly")
                        .font(.system(size: 22, weight: .bold))
                    Text(L("Версия %@", "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")"))
                        .foregroundStyle(.secondary)
                    Text(L("Остров в вырезе экрана: музыка, задачи, таймеры, напоминания и уведомления.\nВсе данные хранятся только на этом Mac."))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            Section {
                Button(L("Выйти из Notchly")) { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
    }
}

private struct TabSlotRow: View {
    var slot: TabSlot
    var isFirst: Bool
    var isLast: Bool
    var move: (Int) -> Void
    var switchSide: () -> Void
    var setVisible: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: slot.tab.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 22)
                .background(Capsule().fill(Color.black))
                .opacity(slot.visible ? 1 : 0.4)
            Text(slot.tab.title)
                .foregroundStyle(slot.visible ? .primary : .secondary)
            Spacer()
            HStack(spacing: 2) {
                small("chevron.up", help: L("Левее / выше"), disabled: isFirst) { move(-1) }
                small("chevron.down", help: L("Правее / ниже"), disabled: isLast) { move(1) }
                small(slot.side == .leading ? "arrow.right" : "arrow.left",
                      help: slot.side == .leading ? L("Перенести направо от выреза") : L("Перенести налево от выреза"),
                      disabled: false, action: switchSide)
            }
            Toggle("", isOn: Binding(get: { slot.visible }, set: setVisible))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(slot.tab == .home)
                .help(slot.tab == .home ? L("Главная всегда видна") : L("Показывать вкладку"))
        }
    }

    private func small(_ symbol: String, help: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: 22, height: 20)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .help(help)
    }
}


// MARK: - Записыватель сочетания клавиш

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var keyCode: Int
    @Binding var mods: Int
    @Binding var label: String

    func makeNSView(context: Context) -> HotkeyCaptureView {
        let v = HotkeyCaptureView()
        v.onCapture = { key, flags, text in
            keyCode = key
            mods = flags
            label = text
        }
        return v
    }

    func updateNSView(_ view: HotkeyCaptureView, context: Context) {
        view.current = label
        view.onCapture = { key, flags, text in
            keyCode = key
            mods = flags
            label = text
        }
    }
}

final class HotkeyCaptureView: NSView {
    var onCapture: ((Int, Int, String) -> Void)?
    var current: String = "" { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        let focused = window?.firstResponder === self
        (focused ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = focused ? 2 : 1
        path.stroke()
        let text = focused ? "Нажми сочетание…" : (current.isEmpty ? "Выключено" : current)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: focused ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        s.draw(at: NSPoint(x: 8, y: (bounds.height - s.size().height) / 2))
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasMod = flags.contains(.command) || flags.contains(.control) || flags.contains(.option)
        guard hasMod else { NSSound.beep(); return }
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        var key: String
        switch Int(event.keyCode) {
        case 49: key = "Space"
        case 36: key = "↩"
        case 53: key = "Esc"
        case 123: key = "←"
        case 124: key = "→"
        case 125: key = "↓"
        case 126: key = "↑"
        default:
            key = event.charactersIgnoringModifiers?.uppercased() ?? "?"
            if key.isEmpty { key = "F\(Int(event.keyCode))" }
        }
        onCapture?(Int(event.keyCode), Int(flags.rawValue), parts.joined() + key)
        window?.makeFirstResponder(nil)
    }
}
