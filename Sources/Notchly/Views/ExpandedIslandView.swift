import SwiftUI
import IOKit.ps

struct ExpandedIslandView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var media: MediaController
    @Namespace private var tabNS
    @ViewState private var tabDirection: Edge = .trailing

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: model.notchSize.height)
                .staggered(0)
            // Страницы не обрезаем отдельным контейнером — иначе при смене вкладки
            // содержимое срезается по линии отступа. Края обрезает сама форма острова.
            ZStack {
                page(for: model.tab)
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 18)
                    .id(model.tab)
                    .transition(.pageSlide(tabDirection))
                // Конвертер файлов: перекрывает вкладку, пока открыт дропнутый файл.
                if model.converter.isOpen {
                    ConverterPanelView(model: model.converter, settings: model.settings)
                        .zIndex(2)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .staggered(1)
            .animation(IslandMetrics.softSpring, value: model.converter.isOpen)
        }
        .background(alignment: .bottom) {
            // Мягкое свечение цвета обложки на вкладке музыки.
            if model.tab == .music && media.hasTrack {
                RadialGradient(colors: [media.accent.opacity(0.14), .clear],
                               center: .bottomLeading, startRadius: 10, endRadius: 360)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    private var header: some View {
        let settings = model.settings
        // Ширина каждой стороны жёстко посчитана от ширины выреза: плейсхолдер выреза
        // (notchSize.width + 16) стоит точно по центру острова, группы вкладок прижаты
        // к его краям. Никакой гибкой раздачи места - вкладки физически не могут
        // заехать под настоящий вырез Mac.
        let side = (IslandMetrics.expandedWidth - model.notchSize.width - 16) / 2
        return HStack(spacing: 0) {
            HStack(spacing: 3) {
                ForEach(settings.tabs(on: .leading)) { tab in
                    TabButton(tab: tab, selected: model.tab == tab, badge: badge(for: tab), ns: tabNS) {
                        select(model.tab == tab && tab != .home ? .home : tab)
                    }
                }
            }
            .frame(width: side, alignment: .trailing)
            Color.clear
                .frame(width: model.notchSize.width + 16)
                .allowsHitTesting(false)
            HStack(spacing: 5) {
                ForEach(settings.tabs(on: .trailing)) { tab in
                    TabButton(tab: tab, selected: model.tab == tab, badge: badge(for: tab), ns: tabNS) {
                        select(model.tab == tab ? .home : tab)
                    }
                }
            }
            .frame(width: side, alignment: .leading)
        }
    }

    private func badge(for tab: IslandTab) -> Int {
        switch tab {
        case .shelf: return model.shelf.items.count
        case .agents: return model.agents.waitingCount
        case .fo: return 0
        default: return 0
        }
    }

    private func select(_ tab: IslandTab) {
        let all = model.settings.visibleOrder
        let from = all.firstIndex(of: model.tab) ?? 0
        let to = all.firstIndex(of: tab) ?? 0
        tabDirection = to >= from ? .trailing : .leading
        withAnimation(.spring(response: 0.46, dampingFraction: 0.9)) { model.tab = tab }
    }

    @ViewBuilder
    private func page(for tab: IslandTab) -> some View {
        switch tab {
        case .home: HomeView(model: model, media: media, batteries: model.batteries) { select(.music) }
        case .music: MusicPlayerView(media: media)
        case .timer: TimerView(model: model, focus: model.focus, countdown: model.countdown,
                               alarms: model.alarms, tasks: model.tasks)
        case .shelf: ShelfView(store: model.shelf, isTargeted: model.isDropTargeted)
        case .notes: NotesView(store: model.notes, tasks: model.tasks, gemini: model.gemini, focus: model.focus,
                               calendar: model.reminders.calendar, openFo: { select(.fo) })
        case .clipboard: ClipboardTab(clipboard: model.clipboard, shots: model.clipboard.shots, vault: model.vault,
                                      settings: model.settings)
        case .notifications: NotificationsView(gmail: model.gmail, system: model.systemNotifications)
        case .controls: ControlsView(volume: model.volume, brightness: model.brightness, mixer: model.mixer,
                                     openSettings: { SettingsWindowController.shared.show(model: model) })
        case .agents: AgentsTab(store: model.agents, runner: model.runner)
        case .fo: FoChatView(model: model.foChat)
        case .apps: AppsTab(model: model)
        case .temp: SystemTab(sys: model.sysMonitor)
        case .tools: ToolsTabView(model: model, packs: model.toolPacks)
        }
    }
}

private struct PageSlide: ViewModifier {
    var offset: CGFloat
    var opacity: Double
    func body(content: Content) -> some View {
        content.offset(x: offset).opacity(opacity)
    }
}

extension AnyTransition {
    /// Короткий сдвиг с растворением: новая страница въезжает на 40 pt, старая уходит в другую сторону.
    static func pageSlide(_ edge: Edge) -> AnyTransition {
        let shift: CGFloat = edge == .trailing ? 40 : -40
        return .asymmetric(
            insertion: .modifier(active: PageSlide(offset: shift, opacity: 0), identity: PageSlide(offset: 0, opacity: 1)),
            removal: .modifier(active: PageSlide(offset: -shift, opacity: 0), identity: PageSlide(offset: 0, opacity: 1))
                .animation(.easeOut(duration: 0.18)))
    }
}

private struct TabButton: View {
    var tab: IslandTab
    var selected: Bool
    var badge: Int
    var ns: Namespace.ID
    var action: () -> Void

    @ViewState private var hovering = false

    /// Снимок окна (снапшоты и GIF для README) красит системные символы в кнопках белым,
    /// и чёрная иконка выбранной вкладки пропадала на белой капсуле. Там берём уже окрашенную картинку.
    private var icon: Image {
        guard SnapshotFlags.isRendering, selected,
              let symbol = NSImage(systemSymbolName: tab.icon, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 12.5, weight: .semibold)
                    .applying(.init(paletteColors: [.black]))) else { return Image(systemName: tab.icon) }
        return Image(nsImage: symbol)
    }

    var body: some View {
        Button(action: action) {
            icon
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(selected ? .black : .white.opacity(hovering ? 1 : 0.65))
                .symbolEffect(.bounce, value: selected)
                .frame(width: 28, height: 22)
                .background {
                    if selected {
                        Capsule().fill(Color.accentColor).matchedGeometryEffect(id: "tab", in: ns)
                    } else if hovering {
                        Capsule().fill(.white.opacity(0.1))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if badge > 0 && !selected {
                        Text("\(badge)")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 3.5)
                            .frame(minWidth: 13, minHeight: 13)
                            .background(Capsule().fill(Color.orange))
                            .offset(x: 4, y: -3)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .help(tab.title)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }
}

/// Колокольчик центра уведомлений со счётчиком новых.
private struct NotificationBell: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var gmail: GmailClient
    @ObservedObject var system: SystemNotificationsReader
    var action: () -> Void
    @ViewState private var hovering = false

    private var unseen: Int {
        let seen = model.notificationsSeenAt
        return gmail.mails.filter { $0.date > seen }.count + system.notifications.filter { $0.date > seen }.count
    }

    var body: some View {
        let selected = model.tab == .notifications
        Button(action: action) {
            Image(systemName: selected ? "bell.fill" : "bell")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? .black : .white.opacity(hovering ? 1 : 0.75))
                .symbolEffect(.bounce, value: unseen)
                .frame(width: 26, height: 22)
                .background(Capsule().fill(selected ? Color.accentColor : .white.opacity(hovering ? 0.12 : 0)))
                .overlay(alignment: .topTrailing) {
                    if unseen > 0 && !selected {
                        Text("\(min(unseen, 99))")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3.5)
                            .frame(minWidth: 13, minHeight: 13)
                            .background(Capsule().fill(Color.red))
                            .offset(x: 5, y: -3)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .help(L("Центр уведомлений"))
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }
}

struct BatteryInfo: Equatable {
    var percent: Int
    var charging: Bool
    var onAC = false

    var symbol: String {
        if charging { return "battery.100percent.bolt" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    static func read() -> BatteryInfo? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let onAC = desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let charging = (desc[kIOPSIsChargingKey] as? Bool ?? false) || onAC
            return BatteryInfo(percent: current * 100 / max, charging: charging, onAC: onAC)
        }
        return nil
    }
}
