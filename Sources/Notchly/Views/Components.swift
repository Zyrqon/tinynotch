import SwiftUI

/// Обложка с плавной сменой картинки. При смене трека старая обложка растворяется
/// с размытием, новая проявляется поверх — без вспышек заглушки.
struct ArtworkView: View {
    var image: NSImage?
    var accent: Color
    var cornerRadius: CGFloat

    var body: some View {
        ZStack {
            Color(white: 0.08)
            if image == nil {
                LinearGradient(colors: [accent.opacity(0.45), accent.opacity(0.12)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 200, weight: .semibold))
                            .minimumScaleFactor(0.01)
                            .padding(cornerRadius * 1.2)
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .transition(.opacity)
            }
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .id(ObjectIdentifier(image))
                    .transition(.blurFade)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct BlurFadeModifier: ViewModifier {
    var active: Bool
    func body(content: Content) -> some View {
        content
            .opacity(active ? 0 : 1)
            .scaleEffect(active ? 1.03 : 1)
    }
}

extension AnyTransition {
    /// Мягкое появление/исчезновение (без размытия — текст остаётся чётким).
    static var blurFade: AnyTransition {
        .modifier(active: BlurFadeModifier(active: true), identity: BlurFadeModifier(active: false))
    }
}

/// Появление с задержкой: элементы раскрытого острова выплывают друг за другом.
struct StaggeredAppear: ViewModifier {
    var index: Int
    @ViewState private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 4)
            .onAppear {
                withAnimation(.easeOut(duration: 0.38).delay(0.05 + Double(index) * 0.05)) {
                    visible = true
                }
            }
    }
}

extension View {
    func staggered(_ index: Int) -> some View { modifier(StaggeredAppear(index: index)) }
}

/// Кнопка-иконка: при наведении слегка увеличивается, при нажатии «проседает» и подпрыгивает.
struct IconButton: View {
    var systemName: String
    var size: CGFloat = 16
    var weight: Font.Weight = .semibold
    var padding: CGFloat = 8
    var action: () -> Void

    @ViewState private var hovering = false
    @ViewState private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: size, weight: weight))
                .contentTransition(.symbolEffect(.replace.downUp))
                .symbolEffect(.bounce.down, value: taps)
                .opacity(hovering ? 1 : 0.88)
                .scaleEffect(hovering ? 1.1 : 1)
                .frame(width: size + padding * 2, height: size + padding * 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { hovering = h } }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

/// Горизонтальный слайдер в стиле Пункта управления. Заливка растёт непрерывно от нуля,
/// иконка темнеет только когда её накрывает заливка — поэтому не пропадает на малых значениях.
struct CapsuleSlider: View {
    var value: Double
    var icon: String
    var tint: Color = .white
    var height: CGFloat = 34
    var iconAction: (() -> Void)?
    var onChange: (Double) -> Void

    @ViewState private var dragValue: Double?
    @ViewState private var hovering = false

    var body: some View {
        GeometryReader { geo in
            let shown = dragValue ?? value
            let fillWidth = geo.size.width * shown
            let iconCovered = fillWidth > height * 0.62
            ZStack(alignment: .leading) {
                Rectangle().fill(.white.opacity(hovering ? 0.15 : 0.11))
                Rectangle()
                    .fill(tint.opacity(0.88))
                    .frame(width: fillWidth)
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(iconCovered ? Color.black.opacity(0.75) : Color.white.opacity(0.85))
                        .frame(width: height, height: height)
                        .contentShape(Rectangle())
                        .onTapGesture { iconAction?() }
                    Spacer()
                    Text("\(Int((shown * 100).rounded()))%")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(fillWidth > geo.size.width - 44 ? .black.opacity(0.6) : .white.opacity(0.6))
                        .padding(.trailing, 13)
                }
            }
            .clipShape(Capsule())
            .animation(.easeOut(duration: 0.15), value: iconCovered)
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let v = min(max(g.location.x / geo.size.width, 0), 1)
                    dragValue = v
                    onChange(v)
                }
                .onEnded { _ in dragValue = nil })
            .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        }
        .frame(height: height)
    }
}

/// Маленький крестик «удалить»: едва заметный, ярче при наведении.
struct DismissButton: View {
    var help: String
    var action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(hovering ? 0.9 : 0.35))
                .frame(width: 22, height: 22)
                .background(Circle().fill(.white.opacity(hovering ? 0.12 : 0.04)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help(help)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }
}

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let s = Int(seconds)
    return s >= 3600
        ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        : String(format: "%d:%02d", s / 60, s % 60)
}

/// Аналог `@State`. В macOS 27 SDK `@State` стал макросом, а его плагин есть только
/// в полном Xcode, поэтому с Command Line Tools используем обычную обёртку над `State`.
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    private let storage: State<Value>

    init(wrappedValue: Value) { storage = State(initialValue: wrappedValue) }

    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> { storage.projectedValue }
}
