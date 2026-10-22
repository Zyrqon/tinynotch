import SwiftUI
import QuickLookThumbnailing

struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    var isTargeted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(store.items.isEmpty ? L("Файлы") : L("Файлы · %@", "\(store.items.count)"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .contentTransition(.numericText())
                Spacer()
                if !store.items.isEmpty {
                    Button(L("Очистить")) { store.removeAll() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .transition(.opacity)
                }
            }

            ZStack {
                // Пунктирная рамка нужна, только когда полка пустая или над ней тянут файл.
                // С файлами фон остаётся чистым — без «плёнки» поверх иконок.
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(.white.opacity(isTargeted ? 0.6 : 0.16))
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(isTargeted ? 0.06 : 0.02)))
                    .opacity(store.items.isEmpty || isTargeted ? 1 : 0)
                    .animation(.easeOut(duration: 0.25), value: isTargeted)

                if store.items.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                            .font(.system(size: 24, weight: .medium))
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.bounce, value: isTargeted)
                        Text(L("Перетащите файлы сюда, чтобы подержать их под рукой"))
                            .font(.system(size: 11.5))
                    }
                    .foregroundStyle(.white.opacity(0.5))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(store.items) { item in
                                ShelfTile(item: item) { store.remove(item) }
                                    .transition(.opacity.combined(with: .offset(y: 6)))
                            }
                        }
                        .padding(.horizontal, 2)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
}

private struct ShelfTile: View {
    var item: ShelfItem
    var onRemove: () -> Void

    @ViewState private var thumbnail: NSImage?
    @ViewState private var hovering = false

    var body: some View {
        VStack(spacing: 5) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                        .resizable()
                        .interpolation(.high)
                }
            }
            .frame(width: 52, height: 52)

            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(width: 76, height: 26, alignment: .top)
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(hovering ? 0.08 : 0)))
        // Крестик внутри плитки, чтобы прокрутка его не обрезала. Без масштабирования и теней — всё чёткое.
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color(white: 0.28)))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .padding(4)
            .opacity(hovering ? 1 : 0)
            .help(L("Убрать из файлов"))
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.18)) { hovering = h } }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .contextMenu {
            Button(L("Открыть")) { NSWorkspace.shared.open(item.url) }
            Button(L("Показать в Finder")) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button(L("Отправить по AirDrop")) { NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [item.url]) }
            Button(L("Скопировать путь")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }
            Divider()
            Button(L("Убрать из файлов"), role: .destructive, action: onRemove)
        }
        .help(item.url.path)
        .task(id: item.url) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        let request = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: 96, height: 96),
                                                   scale: 2, representationTypes: .thumbnail)
        if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            withAnimation(.easeOut(duration: 0.25)) { thumbnail = rep.nsImage }
        }
    }
}
