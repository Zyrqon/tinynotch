import SwiftUI
import UniformTypeIdentifiers

/// Вкладка «Буфер обмена»: история текста, снимки экрана и API-ключи за Touch ID.
struct ClipboardTab: View {
    enum Mode: String, CaseIterable {
        case history = "История", shots = "Снимки", vault = "API-ключи"
        var order: Int { Mode.allCases.firstIndex(of: self) ?? 0 }
    }

    @ObservedObject var clipboard: ClipboardMonitor
    @ObservedObject var shots: ScreenshotStore
    @ObservedObject var vault: KeyVault
    @ObservedObject var settings: AppSettings
    @ViewState private var mode: Mode = SnapshotFlags.clipboardMode
    @ViewState private var direction: Edge = .trailing
    @Namespace private var segmentNS

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach([Mode.history, .shots], id: \.self) { item in
                    Button { switchTo(item) } label: {
                        HStack(spacing: 5) {
                            Text(L(item.rawValue))
                            if item == .shots && !shots.items.isEmpty {
                                Text("\(shots.items.count)")
                                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                    .opacity(0.6)
                            }
                        }
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(mode == item ? .black : .white.opacity(0.6))
                        .padding(.horizontal, 11)
                        .frame(height: 24)
                        .background(Capsule().fill(.white.opacity(0.08)))
                        .background {
                            if mode == item {
                                Capsule().fill(.white).matchedGeometryEffect(id: "clip-segment", in: segmentNS)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
                Button { switchTo(mode == .vault ? .history : .vault) } label: {
                    Label(L("API-ключи"), systemImage: vault.isUnlocked ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(mode == .vault ? .black : .yellow.opacity(0.9))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(mode == .vault ? Color.yellow : Color.yellow.opacity(0.14)))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())

                Spacer()

                switch mode {
                case .history where !clipboard.groups.isEmpty:
                    ConfirmClearButton { clipboard.clear() }.transition(.blurFade)
                case .shots where !shots.items.isEmpty:
                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(shots.totalBytes), countStyle: .file)) · \(Self.daysText(shots.retentionDays))")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .help(L("Снимки удаляются сами через этот срок. Изменить — в настройках Notchly."))
                    ConfirmClearButton { shots.clear() }.transition(.blurFade)
                default:
                    EmptyView()
                }
            }

            ZStack {
                switch mode {
                case .history:
                    if settings.clipboardHistory || !clipboard.groups.isEmpty {
                        ClipboardView(clipboard: clipboard).transition(.pageSlide(direction))
                    } else {
                        DisabledNote(text: L("История буфера выключена в настройках")).transition(.pageSlide(direction))
                    }
                case .shots:
                    ScreenshotGrid(clipboard: clipboard, shots: shots, settings: settings).transition(.pageSlide(direction))
                case .vault:
                    KeyVaultView(vault: vault).transition(.pageSlide(direction))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onDisappear { vault.lock() }
    }

    static func daysText(_ days: Int) -> String {
        Loc.pick("хранятся", "kept") + " \(days) " + ScreenshotGrid.days(days)
    }

    private func switchTo(_ item: Mode) {
        guard item != mode else { return }
        direction = item.order > mode.order ? .trailing : .leading
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) { mode = item }
    }
}

/// «Очистить» с подтверждением: первое нажатие только спрашивает, второе — очищает.
/// Историю так легко стереть случайным кликом, а вернуть уже нельзя.
struct ConfirmClearButton: View {
    var action: () -> Void
    @ViewState private var armed = false

    var body: some View {
        Button {
            if armed {
                armed = false
                action()
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { armed = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation(.easeOut(duration: 0.2)) { armed = false }
                }
            }
        } label: {
            Text(armed ? L("Точно очистить?") : L("Очистить"))
                .font(.system(size: 11.5, weight: armed ? .semibold : .medium))
                .foregroundStyle(armed ? .white : .white.opacity(0.55))
                .padding(.horizontal, armed ? 10 : 0)
                .frame(height: 22)
                .background(Capsule().fill(armed ? Color.red.opacity(0.75) : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

private struct DisabledNote: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Снимки

/// Лента снимков: нажатие копирует снимок, его можно перетащить в любое приложение или сохранить.
private struct ScreenshotGrid: View {
    var clipboard: ClipboardMonitor
    @ObservedObject var shots: ScreenshotStore
    @ObservedObject var settings: AppSettings
    @ViewState private var copiedID: UUID?

    var body: some View {
        if !settings.screenshots && shots.items.isEmpty {
            DisabledNote(text: L("Снимки выключены в настройках"))
        } else if shots.items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 22, weight: .medium))
                Text(L("Снимок в буфер (⌃⇧⌘4) или скопированная картинка появится здесь на %@ %@", "\(shots.retentionDays)", "\(Self.days(shots.retentionDays))"))
                    .font(.system(size: 11.5))
                    .multilineTextAlignment(.center)
                if !settings.screenshotFiles {
                    Button { settings.screenshotFiles = true } label: {
                        Text(L("Брать и снимки с рабочего стола"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .frame(height: 24)
                            .background(Capsule().fill(.white))
                    }
                    .buttonStyle(PressableStyle())
                    .help(L("macOS один раз спросит доступ к папке со снимками"))
                }
            }
            .foregroundStyle(.white.opacity(0.45))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(shots.items) { shot in
                        ShotCell(shot: shot, image: shots.thumbnail(for: shot), fileURL: shots.url(for: shot),
                                 copied: copiedID == shot.id,
                                 onCopy: { copy(shot) },
                                 onSave: { shots.saveCopy(shot) },
                                 onDelete: { shots.remove(shot) },
                                 onRename: { shots.rename(shot, to: $0) })
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    static func days(_ n: Int) -> String {
        Loc.plural(n, "день", "дня", "дней", en: "day", enPlural: "days")
    }

    private func copy(_ shot: Screenshot) {
        clipboard.copy(shot)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { copiedID = shot.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.25)) { if copiedID == shot.id { copiedID = nil } }
        }
    }
}

private struct ShotCell: View {
    var shot: Screenshot
    var image: NSImage?
    var fileURL: URL
    var copied: Bool
    var onCopy: () -> Void
    var onSave: () -> Void
    var onDelete: () -> Void
    var onRename: (String) -> Void
    @ViewState private var hovering = false
    @ViewState private var renaming = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.06))
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 128, height: 80)
                        .clipped()
                }
                if copied {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.55))
                    Label(L("Скопировано"), systemImage: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else if hovering {
                    VStack {
                        HStack(spacing: 4) {
                            Spacer()
                            chip("pencil", help: L("Переименовать")) { renaming = true }
                            chip("square.and.arrow.down", help: L("Сохранить копию…"), action: onSave)
                            chip("xmark", help: L("Удалить"), action: onDelete)
                        }
                        Spacer()
                    }
                    .padding(5)
                    .transition(.opacity)
                }
            }
            .frame(width: 128, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(hovering ? 0.35 : 0.1), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture(perform: onCopy)
            .onDrag { NSItemProvider(contentsOf: fileURL) ?? NSItemProvider() }

            Group {
                if renaming {
                    InlineRenameField(initial: shot.title ?? "", placeholder: L("Название")) { value in
                        guard renaming else { return }
                        renaming = false
                        onRename(value)
                    } onCancel: { renaming = false }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white.opacity(0.12)))
                } else if let title = shot.title {
                    Text(title)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .help(L("%@ · %@. Нажмите, чтобы переименовать", "\(title)", "\(shortTimestamp(shot.date))"))
                } else {
                    Text(shortTimestamp(shot.date))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.45))
                        .help(L("Нажмите, чтобы дать название"))
                }
            }
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .frame(width: 128, height: 16)
            .contentShape(Rectangle())
            .onTapGesture { if !renaming { renaming = true } }
        }
        .contextMenu {
            Button(L("Скопировать"), action: onCopy)
            Button(L("Переименовать…")) { renaming = true }
            Button(L("Сохранить копию…"), action: onSave)
            Divider()
            Button(L("Удалить"), role: .destructive, action: onDelete)
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        .help(L("Нажмите — скопировать, перетащите — вставить в другое приложение"))
    }

    private func chip(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(.black.opacity(0.6)))
        }
        .buttonStyle(PressableStyle())
        .help(help)
    }
}
