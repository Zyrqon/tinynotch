import AppKit
import SwiftUI
import Combine

/// Прозрачная панель поверх строки меню. Не активирует приложение,
/// но может стать key-окном, чтобы в заметках работал ввод текста.
final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .mainMenu + 3
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        // Иначе движения мыши над самой панелью не доходят до локального монитора.
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// У приложения без Dock нет меню «Правка», поэтому ⌘C / ⌘V и прочие сочетания сами никуда не доходят.
    /// Отправляем стандартные команды текущему полю ввода (заметка, задача, поиск). Смотрим на физическую
    /// клавишу, а не на символ — так сочетания работают и в русской раскладке.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let action: Selector?
        switch (event.keyCode, flags) {
        case (7, [.command]): action = #selector(NSText.cut(_:))                 // X
        case (8, [.command]): action = #selector(NSText.copy(_:))                // C
        case (9, [.command]): action = #selector(NSText.paste(_:))               // V
        case (9, [.command, .shift, .option]): action = #selector(NSTextView.pasteAsPlainText(_:))
        case (0, [.command]): action = #selector(NSText.selectAll(_:))           // A
        case (6, [.command]): action = Selector(("undo:"))                       // Z
        case (6, [.command, .shift]): action = Selector(("redo:"))
        default: action = nil
        }
        if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

final class NotchWindowController {
    let model = IslandModel()
    private let panel = NotchPanel()
    private var monitors: [Any] = []
    private var screen: NSScreen = NSScreen.main ?? NSScreen.screens[0]
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private let menuBarGuard = MenuBarGuard()
    private var hoverTimer: Timer?
    private var lastPolledLocation = NSPoint.zero
    private var cancellables = Set<AnyCancellable>()

    init() {
        let root = IslandRootView(model: model, media: model.media, settings: model.settings)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting

        layout()
        // Остров может стать выше окна (вкладка «Агенты» растёт вниз) — тянем панель за ним.
        model.objectWillChange
            .sink { [weak self] _ in DispatchQueue.main.async { self?.syncPanelFrame() } }
            .store(in: &cancellables)
        panel.orderFrontRegardless()
        installMonitors()
        // Без этого после программного перемещения курсора он «замирает» на четверть секунды.
        CGEventSource(stateID: .combinedSessionState)?.localEventsSuppressionInterval = 0
        model.keys.start()
        startHoverPolling()
        menuBarGuard.zone = { [weak self] in
            guard let self else { return nil }
            let rect = self.islandRect().insetBy(dx: -14, dy: 0)
            let primaryTop = NSScreen.screens.first?.frame.maxY ?? self.screen.frame.maxY
            return (rect.minX...rect.maxX, primaryTop - self.screen.frame.maxY)
        }
        menuBarGuard.start()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.layout()
        }
    }

    // MARK: - Размещение

    private func layout() {
        screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]

        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            model.notchSize = CGSize(width: width, height: screen.safeAreaInsets.top)
            model.hasPhysicalNotch = true
        } else {
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            model.notchSize = CGSize(width: 190, height: max(26, menuBar))
            model.hasPhysicalNotch = false
        }

        let size = model.windowSize
        let frame = NSRect(x: screen.frame.midX - size.width / 2,
                           y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        panel.setFrame(frame, display: true)
    }

    /// Окно не меньше острова: высоту тянем вниз, верхняя кромка неподвижна.
    private func syncPanelFrame() {
        let needed = max(model.windowSize.height, model.shapeSize.height + 24)
        guard abs(needed - panel.frame.height) > 0.5 else { return }
        let frame = NSRect(x: screen.frame.midX - model.windowSize.width / 2,
                           y: screen.frame.maxY - needed,
                           width: model.windowSize.width, height: needed)
        panel.setFrame(frame, display: true)
    }

    /// Текущая область острова в экранных координатах.
    private func islandRect() -> NSRect {
        let size = model.shapeSize
        return NSRect(x: screen.frame.midX - size.width / 2,
                      y: screen.frame.maxY - size.height,
                      width: size.width, height: size.height)
    }

    // MARK: - Мышь

    private func installMonitors() {
        let moveMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: moveMask) { [weak self] event in
            self?.handleMouse(dragging: event.type == .leftMouseDragged)
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: moveMask) { [weak self] event in
            self?.handleMouse(dragging: false)
            return event
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            self.dragChangeCount = NSPasteboard(name: .drag).changeCount
            if self.model.isExpanded && !self.islandRect().contains(NSEvent.mouseLocation) {
                self.collapseNow()
            }
        } as Any)
        // Клик по прозрачной части нашей же панели (вокруг острова) — это событие приложения, а не
        // глобальное, поэтому его ловит отдельный локальный монитор. Без него остров закрывался
        // только через пару секунд по таймеру ухода курсора.
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.window === self.panel, self.model.isExpanded,
               !self.islandRect().contains(NSEvent.mouseLocation) {
                self.collapseNow()
            }
            return event
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.handleMouse(dragging: false)
        } as Any)
    }

    /// Страховка к мониторам событий: иногда первое движение над панелью не приходит ни в один из них
    /// (например, когда она только что перестала пропускать мышь), и остров раскрывался только со второго раза.
    /// Проверяем курсор 20 раз в секунду, но только у верхней кромки экрана — это почти ничего не стоит.
    private func startHoverPolling() {
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            let location = NSEvent.mouseLocation
            guard location != self.lastPolledLocation else { return }
            self.lastPolledLocation = location
            let nearTop = location.y >= self.screen.frame.maxY - self.model.shapeSize.height - 40
            if nearTop || self.model.isExpanded { self.handleMouse(dragging: NSEvent.pressedMouseButtons != 0) }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func handleMouse(dragging: Bool) {
        preventMenuBarReveal()
        let location = NSEvent.mouseLocation
        guard screen.frame.contains(location) || islandRect().contains(location) else {
            scheduleCollapseIfNeeded()
            return
        }

        // Пока показана карточка события, наведение не раскрывает остров — по ней можно кликать.
        if model.event != nil {
            let inside = islandRect().insetBy(dx: -6, dy: -6).contains(location)
            model.eventHovered = inside
            syncMouseEvents(inHotZone: inside)
            expandWork?.cancel()
            expandWork = nil
            return
        }

        if model.isExpanded {
            let inside = islandRect().insetBy(dx: -12, dy: -12).contains(location)
            if inside {
                collapseWork?.cancel()
                collapseWork = nil
            } else {
                scheduleCollapseIfNeeded()
            }
            // Панель больше самого острова. Вне острова она пропускает клики насквозь: иначе прозрачная
            // часть перекрывала окна под ней (например, заголовок окна настроек), а клик мимо острова
            // не доходил до глобального монитора и не закрывал его сразу.
            syncMouseEvents(inHotZone: inside)
            return
        }

        // В свёрнутом состоянии зона срабатывания чуть шире самого выреза.
        let hot = islandRect().insetBy(dx: -10, dy: -4)
        let inHot = hot.contains(location)
        syncMouseEvents(inHotZone: inHot)

        guard inHot else {
            expandWork?.cancel()
            expandWork = nil
            return
        }

        if dragging {
            let drag = NSPasteboard(name: .drag)
            let isFileDrag = drag.changeCount != dragChangeCount &&
                (drag.types?.contains(.fileURL) ?? false)
            if isFileDrag { model.expand(to: .shelf) }
            return
        }

        guard expandWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.expandWork = nil
            if self.islandRect().insetBy(dx: -10, dy: -4).contains(NSEvent.mouseLocation) {
                self.model.expand()
                self.syncMouseEvents(inHotZone: true)
            }
        }
        expandWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09, execute: work)
    }

    /// Строка меню (при автоскрытии или в полноэкранном режиме) выезжает, когда курсор касается
    /// самого верхнего ряда пикселей. Над островом не даём курсору туда дойти — чуть опускаем его.
    private func preventMenuBarReveal() {
        // Если есть доступ к событиям, это уже сделал MenuBarGuard — раньше и надёжнее.
        guard !menuBarGuard.isActive, NSEvent.pressedMouseButtons == 0 else { return }
        let location = NSEvent.mouseLocation
        let zone = islandRect().insetBy(dx: -12, dy: 0)
        guard location.x >= zone.minX, location.x <= zone.maxX,
              location.y >= screen.frame.maxY - 2, location.y <= screen.frame.maxY + 1 else { return }
        // Координаты CoreGraphics отсчитываются от левого верхнего угла основного экрана.
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        CGWarpMouseCursorPosition(CGPoint(x: location.x, y: primaryTop - (screen.frame.maxY - 4)))
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    /// Клик мимо острова: закрываем сразу, без ожидания таймера.
    private func collapseNow() {
        collapseWork?.cancel()
        collapseWork = nil
        guard !model.settingsOpen else { return }
        model.collapse()
        syncMouseEvents(inHotZone: false)
    }

    private func scheduleCollapseIfNeeded() {
        guard model.isExpanded, collapseWork == nil, !model.settingsOpen else { return }
        // Не сворачиваем, пока пользователь тянет слайдер или файл.
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseWork = nil
            let inside = self.islandRect().insetBy(dx: -12, dy: -12).contains(NSEvent.mouseLocation)
            if !inside && NSEvent.pressedMouseButtons == 0 {
                self.model.collapse()
                self.syncMouseEvents(inHotZone: false)
            }
        }
        collapseWork = work
        // Остров не закрывается сразу, если курсор случайно соскользнул: ждём, сколько задано в настройках.
        DispatchQueue.main.asyncAfter(deadline: .now() + model.settings.closeDelay, execute: work)
    }

    private func syncMouseEvents(inHotZone: Bool) {
        let shouldIgnore = !inHotZone
        if panel.ignoresMouseEvents != shouldIgnore {
            panel.ignoresMouseEvents = shouldIgnore
        }
    }
}
