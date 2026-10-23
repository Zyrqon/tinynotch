import SwiftUI
import UniformTypeIdentifiers

/// Форма выреза: плавные «уши» у верхней кромки и скруглённый низ.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = topRadius
        let b = min(bottomRadius, (rect.height - t) , (rect.width - 2 * t) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                       control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
                       control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
                       control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

struct IslandRootView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var media: MediaController
    @ObservedObject var settings: AppSettings

    var body: some View {
        let shape = NotchShape(topRadius: model.topRadius, bottomRadius: model.bottomRadius)
        let size = model.shapeSize
        // Высоту меняет только вкладка «Инструменты». Раньше окно и чёрная фигура анимировались
        // разными кривыми и рассинхронизировались: остров дёргался. Теперь фигура и окно едут
        // одним прямым easing 0.3 с, а во время тяги полоски анимации выключены вовсе.
        let toolsEase: Animation? = model.isResizingTools ? nil : .easeInOut(duration: 0.3)
        // Содержимое лежит на неподвижном холсте размером с окно, по центру, и никогда не меняет раскладку.
        // Анимируется только чёрная форма, которая его обрезает. Поэтому при сворачивании и при исчезновении
        // HUD ничто не «уезжает» вбок: удаляемые виды SwiftUI привязывает к краю родителя, а родитель неподвижен.
        ZStack(alignment: .top) {
            // Тень рисуем только у фона. Если повесить её на весь остров,
            // SwiftUI отбрасывает тень от каждой надписи, и текст выглядит размытым.
            shape
                .fill(settings.islandBackground)
                .frame(width: size.width, height: size.height)
                .shadow(color: .black.opacity(model.isExpanded || model.event != nil ? 0.5 : 0), radius: 16, y: 6)
                .animation(toolsEase, value: model.tab)
            content
                // Смена языка пересобирает содержимое целиком — все строки берутся заново.
                .id(model.settings.language)
                .frame(width: model.windowSize.width,
                       height: max(model.windowSize.height, model.notchSize.height + model.expandedContentHeightLive),
                       alignment: .top)
                .mask(alignment: .top) {
                    shape.frame(width: size.width, height: size.height)
                        .animation(toolsEase, value: model.tab)
                }
            // Подсветка краёв при перетаскивании файла.
            shape
                .stroke(Color.white.opacity(model.isDropTargeted ? 0.35 : 0), lineWidth: 1.5)
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)
                .animation(toolsEase, value: model.tab)
            // attn LED: пульсирующая точка у края выреза, пока агент ждёт подтверждения.
            if model.agents.waitingCount > 0 {
                AttentionLED(inset: model.windowSize.width / 2 - model.notchSize.width / 2 - 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDrop(of: [.fileURL], isTargeted: $model.isDropTargeted, perform: handleDrop)
        .animation(IslandMetrics.softSpring, value: media.showsLiveActivity)
        .animation(IslandMetrics.softSpring, value: model.expandedContentHeightLive)
        .animation(IslandMetrics.softSpring, value: model.focus.isActive)
        .animation(IslandMetrics.softSpring, value: model.countdown.isActive)
        .animation(IslandMetrics.softSpring, value: model.peek)
        .animation(IslandMetrics.spring, value: model.hud)
        .animation(IslandMetrics.spring, value: model.clipPeek)
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: model.event)
        .animation(.spring(response: 0.55, dampingFraction: 0.84), value: model.eventExpanded)
        .preferredColorScheme(.dark)
        .tint(settings.accent)
        .onChange(of: model.isDropTargeted) { _, targeted in
            if targeted { model.expand(to: .shelf) }
        }
    }

    /// Быстрое исчезновение свёрнутых состояний: гаснут сразу и на месте, пока форма сжимается.
    private static let compactTransition = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.22).delay(0.06)),
        removal: .opacity.animation(.easeOut(duration: 0.12)))

    @ViewBuilder
    private var content: some View {
        let body = model.bodySize
        if model.isExpanded {
            ExpandedIslandView(model: model, media: media)
                // Фиксированный размер: при сворачивании форма обрезает содержимое, а не сжимает его.
                .frame(width: IslandMetrics.expandedWidth,
                       height: model.notchSize.height + model.expandedContentHeightLive)
                // Открытие: виджеты выходят снизу, когда шторка уже опускается.
                // Закрытие: сначала всё гаснет, потом сворачивается форма.
                .opacity(model.debugFrame?.content ?? (model.expandedContentVisible ? 1 : 0))
                .offset(y: 12 * (1 - (model.debugFrame?.content ?? (model.expandedContentVisible ? 1 : 0))))
                .allowsHitTesting(model.expandedContentVisible)
                .transition(.identity)
        } else if let event = model.event, model.eventExpanded {
            EventView(event: event, model: model) { model.dismissEvent() }
                .frame(width: body.width, height: body.height)
                .contentShape(Rectangle())
                .onTapGesture {
                    switch event {
                    case .device(let device) where device.isConnected: model.showDeviceSheet(device)
                    case .notification(let item): openApp(item.bundleID); model.dismissEvent()
                    case .deviceSheet, .reminder, .focus, .timerDone, .alarm: break
                    default: model.dismissEvent()
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.animation(.easeOut(duration: 0.3).delay(0.12)),
                    removal: .opacity.animation(.easeOut(duration: 0.12))))
        } else if model.event != nil {
            Color.clear.frame(width: 0, height: 0)
        } else if let hud = model.hud {
            HUDView(state: hud, notchWidth: model.notchSize.width)
                .frame(width: body.width, height: body.height)
                .transition(Self.compactTransition)
        } else if let group = model.clipPeek {
            ClipPeekView(group: group, icon: model.clipboard.icon(for: group.bundleID),
                         notchWidth: model.notchSize.width)
                .frame(width: body.width, height: body.height)
                .id(group.items.first?.id)
                .transition(Self.compactTransition)
        } else if model.focus.isActive && !model.peek {
            FocusCompactView(focus: model.focus, notchWidth: model.notchSize.width)
                .frame(width: body.width, height: body.height)
                .transition(Self.compactTransition)
        } else if model.countdown.isActive && !model.peek {
            CountdownCompactView(countdown: model.countdown, notchWidth: model.notchSize.width)
                .frame(width: body.width, height: body.height)
                .transition(Self.compactTransition)
        } else if model.showsMusicActivity || (model.peek && media.hasTrack) {
            CompactMusicView(media: media, model: model)
                .frame(width: body.width, height: body.height)
                .transition(Self.compactTransition)
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
    }

    private func openApp(_ bundleID: String) {
        if bundleID == AppNotification.gmailID { return model.gmail.openInbox() }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            accepted = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else { return }
                DispatchQueue.main.async {
                    // Папки идут на Полку, файлы — в конвертер (кольцо форматов).
                    if url.hasDirectoryPath {
                        model.shelf.add([url])
                        model.tab = .shelf
                    } else {
                        model.converter.receive([url])
                    }
                }
            }
        }
        return accepted
    }
}

/// attn LED (по мотивам attn LED): пульсирующая точка внимания у выреза.
struct AttentionLED: View {
    var inset: CGFloat
    @ViewState private var pulse = false

    var body: some View {
        Circle()
            .fill(Color.orange)
            .frame(width: 6, height: 6)
            .scaleEffect(pulse ? 1.2 : 0.85)
            .opacity(pulse ? 1.0 : 0.4)
            .shadow(color: .orange.opacity(0.9), radius: pulse ? 5 : 2)
            .padding(.top, 15)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, inset)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { pulse = true }
            }
            .allowsHitTesting(false)
    }
}
