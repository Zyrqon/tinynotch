import AppKit
import SwiftUI
import Combine
import ServiceManagement

/// Место вкладки в шапке: сторона от выреза и видимость.
struct TabSlot: Codable, Equatable, Identifiable {
    enum Side: String, Codable { case leading, trailing }
    var tab: IslandTab
    var side: Side
    var visible = true
    var id: IslandTab { tab }
}

/// Все настройки, которые пользователь меняет в окне «Настройки». Хранятся в UserDefaults.
/// persistent = false — для снапшотов: значения по умолчанию, ничего не читаем и не пишем.
final class AppSettings: ObservableObject {
    /// Версия раскладки: при смене дефолтных сторон вкладок сохранённая раскладка сбрасывается.
    static let tabLayoutVersion = 5
    /// Раскладка шапки по умолчанию: слева то, чем пользуются постоянно, справа — «инструменты».
    static let defaultTabs: [TabSlot] = [
        TabSlot(tab: .home, side: .leading), TabSlot(tab: .music, side: .leading),
        TabSlot(tab: .notes, side: .leading), TabSlot(tab: .timer, side: .leading),
        TabSlot(tab: .fo, side: .leading), TabSlot(tab: .temp, side: .leading),
        TabSlot(tab: .clipboard, side: .trailing), TabSlot(tab: .shelf, side: .trailing),
        TabSlot(tab: .controls, side: .trailing), TabSlot(tab: .agents, side: .trailing),
        TabSlot(tab: .apps, side: .trailing), TabSlot(tab: .tools, side: .trailing),
    ]
    static let closeDelayRange: ClosedRange<Double> = 0.3...5

    @Published var tabs: [TabSlot] { didSet { save(tabs, "settings.tabs") } }
    /// Через сколько секунд остров закрывается, если курсор ушёл с него (клик мимо закрывает сразу).
    @Published var closeDelay: Double { didSet { store(closeDelay, "settings.closeDelay") } }
    /// Открывать остров на главной (иначе — на последней вкладке).
    @Published var openOnHome: Bool { didSet { store(openOnHome, "settings.openOnHome") } }

    @Published var musicActivity: Bool { didSet { store(musicActivity, "settings.musicActivity") } }
    @Published var trackPeek: Bool { didSet { store(trackPeek, "settings.trackPeek") } }
    @Published var hud: Bool { didSet { store(hud, "settings.hud") } }
    /// Приветственная анимация при разблокировке Mac.
    @Published var wakeAnimation: Bool { didSet { store(wakeAnimation, "settings.wakeAnimation") } }
    /// Пружинное появление уведомлений-карточек.
    @Published var notificationPop: Bool { didSet { store(notificationPop, "settings.notificationPop") } }
    @Published var copiedPeek: Bool { didSet { store(copiedPeek, "settings.copiedPeek") } }
    @Published var otpTrap: Bool { didSet { store(otpTrap, "settings.otpTrap") } }
    @Published var downloadAlerts: Bool { didSet { store(downloadAlerts, "settings.downloadAlerts") } }
    @Published var chargingCard: Bool { didSet { store(chargingCard, "settings.chargingCard") } }
    @Published var headphonesCard: Bool { didSet { store(headphonesCard, "settings.headphonesCard") } }

    // MARK: Хоткей

    /// Глобальное сочетание клавиш для вызова островка: keyCode NSEvent, 0 = выключено.
    @Published var hotkeyKeyCode: Int { didSet { store(hotkeyKeyCode, "settings.hotkeyKeyCode") } }
    /// Модификаторы в rawValue NSEvent.ModifierFlags.
    @Published var hotkeyMods: Int { didSet { store(hotkeyMods, "settings.hotkeyMods") } }
    /// Человекочитаемая подпись сочетания, например «⌥⌘Space».
    @Published var hotkeyLabel: String { didSet { store(hotkeyLabel, "settings.hotkeyLabel") } }

    // MARK: Память и конвертер

    /// Уборщик памяти: закрывать простаивающие браузеры, пока работают агенты.
    @Published var janitorEnabled: Bool { didSet { store(janitorEnabled, "settings.janitorEnabled") } }
    /// Закрывать только когда работает хотя бы один агент (opencode/codex).
    @Published var janitorOnlyWithAgents: Bool { didSet { store(janitorOnlyWithAgents, "settings.janitorOnlyWithAgents") } }
    /// Сколько минут браузер должен простаивать, прежде чем его закрыть.
    @Published var janitorIdleMinutes: Int { didSet { store(janitorIdleMinutes, "settings.janitorIdleMinutes") } }

    // MARK: Принтер

    /// Живой статус печати с Bambu Lab по локальной сети (MQTT на самом принтере).
    @Published var bambuEnabled: Bool { didSet { store(bambuEnabled, "settings.bambuEnabled") } }
    @Published var bambuIP: String { didSet { store(bambuIP, "settings.bambuIP") } }
    @Published var bambuAccessCode: String { didSet { store(bambuAccessCode, "settings.bambuAccessCode") } }

    @Published var appNotifications: Bool { didSet { store(appNotifications, "settings.appNotifications") } }
    @Published var gmailNotifications: Bool { didSet { store(gmailNotifications, "settings.gmailNotifications") } }
    @Published var reminders: Bool { didSet { store(reminders, "settings.reminders") } }
    @Published var sounds: Bool { didSet { store(sounds, "settings.sounds") } }

    @Published var clipboardHistory: Bool { didSet { store(clipboardHistory, "settings.clipboardHistory") } }
    @Published var screenshots: Bool { didSet { store(screenshots, "settings.screenshots") } }
    /// Брать и снимки, которые macOS сохраняет файлами (на рабочий стол). Спросит доступ к папке.
    @Published var screenshotFiles: Bool { didSet { store(screenshotFiles, "settings.screenshotFiles") } }
    @Published var menuBarIcon: Bool { didSet { store(menuBarIcon, "settings.menuBarIcon") } }
    /// Язык интерфейса. Строки берутся через L(...), поэтому смена видна сразу.
    @Published var language: AppLanguage {
        didSet {
            Loc.language = language
            store(language.rawValue, "settings.language")
        }
    }

    // MARK: - Вид

    /// Акцентный цвет: выбранная вкладка, пузыри Fo, кнопки.
    @Published var accent: Color { didSet { store(accent.hex, "settings.accentHex") } }
    /// Цвет фона самого острова.
    @Published var islandBackground: Color { didSet { store(islandBackground.hex, "settings.backgroundHex") } }
    /// Масштаб скругления нижних углов: 1.0 — как сейчас, 0.7 — острее, 1.6 — круглее.
    @Published var radiusScale: Double { didSet { store(radiusScale, "settings.radiusScale") } }

    private let persistent: Bool

    init(persistent: Bool = true) {
        self.persistent = persistent
        let d = UserDefaults.standard
        func bool(_ key: String, _ fallback: Bool) -> Bool { persistent ? (d.object(forKey: key) as? Bool ?? fallback) : fallback }
        let savedTabs = persistent ? d.data(forKey: "settings.tabs").flatMap { try? JSONDecoder().decode([TabSlot].self, from: $0) } : nil
        let layoutVersion = d.integer(forKey: "settings.tabLayoutVersion")
        // Раскладка из другой версии сбрасывается на дефолтную (настраивается заново в «Виде»).
        tabs = Self.normalized(layoutVersion == Self.tabLayoutVersion && savedTabs != nil ? savedTabs! : Self.defaultTabs)
        if layoutVersion != Self.tabLayoutVersion { d.set(Self.tabLayoutVersion, forKey: "settings.tabLayoutVersion") }
        closeDelay = persistent ? (d.object(forKey: "settings.closeDelay") as? Double ?? 1.2) : 1.2
        openOnHome = bool("settings.openOnHome", true)
        musicActivity = bool("settings.musicActivity", true)
        trackPeek = bool("settings.trackPeek", true)
        hud = bool("settings.hud", true)
        wakeAnimation = bool("settings.wakeAnimation", true)
        notificationPop = bool("settings.notificationPop", true)
        copiedPeek = bool("settings.copiedPeek", true)
        otpTrap = bool("settings.otpTrap", true)
        downloadAlerts = bool("settings.downloadAlerts", true)
        chargingCard = bool("settings.chargingCard", true)
        headphonesCard = bool("settings.headphonesCard", true)
        hotkeyKeyCode = persistent ? (d.object(forKey: "settings.hotkeyKeyCode") as? Int ?? 0) : 0
        hotkeyMods = persistent ? (d.object(forKey: "settings.hotkeyMods") as? Int ?? 0) : 0
        hotkeyLabel = persistent ? (d.string(forKey: "settings.hotkeyLabel") ?? "") : ""
        janitorEnabled = bool("settings.janitorEnabled", false)
        janitorOnlyWithAgents = bool("settings.janitorOnlyWithAgents", true)
        janitorIdleMinutes = persistent ? (d.object(forKey: "settings.janitorIdleMinutes") as? Int ?? 10) : 10
        bambuEnabled = bool("settings.bambuEnabled", false)
        bambuIP = persistent ? (d.string(forKey: "settings.bambuIP") ?? "") : ""
        bambuAccessCode = persistent ? (d.string(forKey: "settings.bambuAccessCode") ?? "") : ""
        appNotifications = bool("settings.appNotifications", true)
        gmailNotifications = bool("settings.gmailNotifications", true)
        reminders = bool("settings.reminders", true)
        sounds = bool("settings.sounds", true)
        clipboardHistory = bool("settings.clipboardHistory", true)
        screenshots = bool("settings.screenshots", true)
        screenshotFiles = bool("settings.screenshotFiles", false)
        menuBarIcon = bool("settings.menuBarIcon", true)
        // Снапшоты рендерятся на языке, заданном до создания модели (--lang).
        language = persistent
            ? (d.string(forKey: "settings.language").flatMap(AppLanguage.init(rawValue:)) ?? .system)
            : Loc.language
        accent = persistent ? (d.string(forKey: "settings.accentHex").flatMap(Color.init(hex:)) ?? .white) : .white
        islandBackground = persistent ? (d.string(forKey: "settings.backgroundHex").flatMap(Color.init(hex:)) ?? .black) : .black
        radiusScale = persistent ? (d.object(forKey: "settings.radiusScale") as? Double ?? 1.0) : 1.0
        Loc.language = language
    }

    /// Сохранённая раскладка могла появиться до новой вкладки — дописываем недостающие, убираем лишние.
    static func normalized(_ slots: [TabSlot]) -> [TabSlot] {
        var result = slots.filter { $0.tab != .notifications }
        var seen = Set<IslandTab>()
        result = result.filter { seen.insert($0.tab).inserted }
        for slot in defaultTabs where !seen.contains(slot.tab) { result.append(slot) }
        // Главная всегда видна: на неё остров возвращается при повторном нажатии на вкладку.
        if let i = result.firstIndex(where: { $0.tab == .home }) { result[i].visible = true }
        return result
    }

    func tabs(on side: TabSlot.Side) -> [IslandTab] {
        tabs.filter { $0.side == side && $0.visible }.map(\.tab)
    }

    /// Порядок видимых вкладок слева направо — от него зависит направление перелистывания.
    var visibleOrder: [IslandTab] { tabs(on: .leading) + tabs(on: .trailing) + [.notifications] }

    func isVisible(_ tab: IslandTab) -> Bool {
        tab == .notifications || tabs.first { $0.tab == tab }?.visible == true
    }

    func resetTabs() { tabs = Self.defaultTabs }

    // MARK: - Запуск при входе

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Launch at login: \(error)")
            }
        }
    }

    // MARK: - Хранение

    private func store(_ value: Any, _ key: String) {
        guard persistent else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        guard persistent, let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

extension Color {
    /// «#RRGGBB» → Color. nil, если строка не разбирается.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }

    var hex: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#000000" }
        return String(format: "#%02X%02X%02X",
                      Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)),
                      Int(round(c.blueComponent * 255)))
    }
}
