import SwiftUI

/// Единый стиль анимаций островка. Эталон — карточка зарядки: плавные
/// появления каскадом, числа с переливом, мягкие пружины. Всё остальное
/// (тулы, агенты, уведомления) анимируется теми же кривыми и таймингами.
enum NotchStyle {
    /// Появление элемента: плавно, как иконка на карточке зарядки.
    static let appear = Animation.smooth(duration: 0.45)
    /// Заливка/счётчик, идущий следом за появлением.
    static let fill = Animation.smooth(duration: 0.9)
    /// Быстрые переключения: нажатия, смены табов, чипсы.
    static let tap = Animation.smooth(duration: 0.2)
    /// Живой пульс (работающий агент, ждущая точка).
    static let pulse = Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true)
    /// Пружина для расхлопов карточек.
    static let pop = Animation.spring(response: 0.55, dampingFraction: 0.84)

    /// Появление «как в зарядке»: масштаб 0.9 → 1, сдвиг 10 → 0, прозрачность 0 → 1.
    static func entrance(_ shown: Bool, delay: Double = 0.1) -> Animation {
        .smooth(duration: 0.45).delay(delay)
    }

    /// Градиент для акцентов и иконок: белый металл сверху вниз, как у зарядки.
    static let metal = LinearGradient(colors: [.white, Color(white: 0.78)],
                                      startPoint: .top, endPoint: .bottom)

    /// Трек под заливкой (полоса прогресса, фон чипса).
    static let track = Color.white.opacity(0.14)
}

/// Модификатор появления в стиле зарядки: масштаб, сдвиг и прозрачность.
struct NotchEntrance: ViewModifier {
    var shown: Bool
    var delay: Double
    var offset: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.9)
            .offset(x: shown ? 0 : offset)
            .animation(NotchStyle.entrance(shown, delay: delay), value: shown)
    }
}

extension View {
    /// Появление в стиле карточки зарядки. `shown` обычно взводится в onAppear.
    func notchAppear(_ shown: Bool, delay: Double = 0.1, offset: CGFloat = 10) -> some View {
        modifier(NotchEntrance(shown: shown, delay: delay, offset: offset))
    }

    /// Число с переливом, как проценты на карточке зарядки.
    func notchNumber(_ value: some BinaryInteger) -> some View {
        contentTransition(.numericText(value: Double(value)))
            .animation(NotchStyle.fill, value: value)
    }
}

/// Цвета живых состояний агентов: codex — бирюзовый, opencode — янтарный.
enum AgentPalette {
    case codex, opencode, waiting, done

    var main: Color {
        switch self {
        case .codex: Color(red: 0.30, green: 0.85, blue: 0.78)
        case .opencode: Color(red: 1.00, green: 0.62, blue: 0.26)
        case .waiting: Color(red: 1.00, green: 0.36, blue: 0.36)
        case .done: Color(red: 0.42, green: 0.88, blue: 0.47)
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [main.opacity(0.95), main.opacity(0.65)],
                       startPoint: .top, endPoint: .bottom)
    }

    var glow: Color { main.opacity(0.28) }
}
