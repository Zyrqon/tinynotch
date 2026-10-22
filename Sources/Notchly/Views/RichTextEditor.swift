import AppKit
import SwiftUI

/// Управляет форматированием в редакторе заметки: панель над текстом вызывает эти методы.
final class RichTextController: ObservableObject {
    weak var textView: NSTextView?

    /// Что включено под курсором (или в начале выделения) — кнопки панели подсвечиваются белым.
    @Published private(set) var isBold = false
    @Published private(set) var isItalic = false
    @Published private(set) var isStrikethrough = false

    /// Пересчитывает состояние кнопок. Отложено на следующий такт: вызывается из колбэков NSTextView,
    /// которые могут прийти посреди обновления SwiftUI.
    func refreshState() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let tv = self.textView else { return }
            let range = tv.selectedRange()
            let attrs: [NSAttributedString.Key: Any]
            if range.length > 0, let storage = tv.textStorage, range.location < storage.length {
                attrs = storage.attributes(at: range.location, effectiveRange: nil)
            } else {
                attrs = tv.typingAttributes
            }
            let traits = (attrs[.font] as? NSFont).map { NSFontManager.shared.traits(of: $0) } ?? []
            let bold = traits.contains(.boldFontMask)
            let italic = traits.contains(.italicFontMask)
            let strike = (attrs[.strikethroughStyle] as? Int ?? 0) != 0
            if bold != self.isBold { self.isBold = bold }
            if italic != self.isItalic { self.isItalic = italic }
            if strike != self.isStrikethrough { self.isStrikethrough = strike }
        }
    }

    static let baseSize: CGFloat = 13
    static let sizes: [(title: String, size: CGFloat)] = [(L("Мелкий"), 11), (L("Обычный"), 13), (L("Крупный"), 17), (L("Заголовок"), 22)]

    func toggleBold() { toggle(.boldFontMask) }
    func toggleItalic() { toggle(.italicFontMask) }

    func toggleStrikethrough() {
        apply { attrs in
            let on = (attrs[.strikethroughStyle] as? Int ?? 0) != 0
            return [.strikethroughStyle: on ? 0 : NSUnderlineStyle.single.rawValue]
        }
    }

    func setSize(_ size: CGFloat) {
        apply { attrs in
            let font = attrs[.font] as? NSFont ?? .systemFont(ofSize: Self.baseSize)
            return [.font: NSFontManager.shared.convert(font, toSize: size)]
        }
    }

    private func toggle(_ trait: NSFontTraitMask) {
        guard let tv = textView else { return }
        let manager = NSFontManager.shared
        // Если у начала выделения признак уже есть — снимаем его со всего выделения, иначе добавляем.
        let probe = tv.selectedRange().length > 0
            ? tv.textStorage?.attribute(.font, at: tv.selectedRange().location, effectiveRange: nil) as? NSFont
            : tv.typingAttributes[.font] as? NSFont
        let has = probe.map { manager.traits(of: $0).contains(trait) } ?? false
        apply { attrs in
            let font = attrs[.font] as? NSFont ?? .systemFont(ofSize: Self.baseSize)
            let converted = has ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait)
            return [.font: converted]
        }
    }

    /// Применяет изменение к выделению, а без выделения — к тому, что будет напечатано дальше.
    private func apply(_ change: ([NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any]) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange()
        defer { refreshState() }
        if range.length == 0 {
            tv.typingAttributes.merge(change(tv.typingAttributes)) { $1 }
            return
        }
        guard tv.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttributes(in: range) { attrs, sub, _ in
            storage.addAttributes(change(attrs), range: sub)
        }
        storage.endEditing()
        tv.didChangeText()
        tv.window?.makeFirstResponder(tv)
    }
}

/// NSTextView с форматированием. Изменения отдаются наружу как RTF и простой текст.
struct RichTextEditor: NSViewRepresentable {
    /// Текст при создании редактора. Замыкание, а не значение: иначе RTF разбирался бы при каждой перерисовке.
    var initial: () -> NSAttributedString
    var controller: RichTextController
    var onChange: (NSAttributedString) -> Void

    static var defaultAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: RichTextController.baseSize), .foregroundColor: NSColor.white]
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.isRichText = true
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.insertionPointColor = .white
        tv.textContainerInset = NSSize(width: 4, height: 6)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.typingAttributes = Self.defaultAttributes
        tv.textStorage?.setAttributedString(initial())
        tv.delegate = context.coordinator
        controller.textView = tv
        context.coordinator.controller = controller
        controller.refreshState()
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
    }

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: (NSAttributedString) -> Void
        weak var controller: RichTextController?
        init(onChange: @escaping (NSAttributedString) -> Void) { self.onChange = onChange }

        func textViewDidChangeSelection(_ notification: Notification) {
            controller?.refreshState()
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView, let storage = tv.textStorage else { return }
            // После удаления всего текста возвращаем обычный шрифт, а не последний использованный.
            if storage.length == 0 { tv.typingAttributes = RichTextEditor.defaultAttributes }
            onChange(NSAttributedString(attributedString: storage))
            controller?.refreshState()
        }
    }
}

/// Панель форматирования над заметкой.
struct FormatBar: View {
    @ObservedObject var controller: RichTextController

    var body: some View {
        HStack(spacing: 2) {
            button("bold", L("Жирный"), active: controller.isBold) { controller.toggleBold() }
            button("italic", L("Курсив"), active: controller.isItalic) { controller.toggleItalic() }
            button("strikethrough", L("Зачёркнутый"), active: controller.isStrikethrough) { controller.toggleStrikethrough() }
            Menu {
                ForEach(RichTextController.sizes, id: \.size) { item in
                    Button(item.title) { controller.setSize(item.size) }
                }
            } label: {
                Image(systemName: "textformat.size")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 24, height: 20)
            .help(L("Размер шрифта"))
        }
        .padding(.horizontal, 3)
        .frame(height: 24)
        .background(Capsule().fill(.white.opacity(0.07)))
    }

    private func button(_ symbol: String, _ help: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                // Включено — белая капсула с чёрным значком, как у выбранной вкладки.
                .foregroundStyle(active ? .black : .white.opacity(0.75))
                .frame(width: 24, height: 20)
                .background(Capsule().fill(active ? Color.white : Color.clear))
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.15), value: active)
        }
        .buttonStyle(PressableStyle())
        .help(help)
    }
}
