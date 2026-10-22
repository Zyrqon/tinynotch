import SwiftUI
import AppKit

/// Вкладка «Агенты»: командная строка для opencode, живой список сессий
/// codex/opencode и подтверждения прямо с острова. Цвета и анимации — из
/// NotchStyle (эталон: карточка зарядки).
struct AgentsTab: View {
    @ObservedObject var store: AgentsStore
    @ObservedObject var runner: AgentRunner

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                AgentCommandBar(runner: runner)
                sessionHeader
                // Показываем только активных: работающих и ждущих подтверждения.
                let active = store.sessions.filter { $0.state != .idle }
                if active.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(active.enumerated()), id: \.element.id) { pair in
                            let s = pair.element
                            Button { openInTerminal(s) } label: {
                                AgentCard(session: s,
                                          onPermission: s.kind == .opencode && s.state == .waiting
                                              ? { allow in store.replyToPermission(s, allow: allow) } : nil)
                            }
                            .buttonStyle(PressableStyle())
                            .notchAppear(true, delay: 0.08 * Double(pair.offset))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Сессии

    private var sessionHeader: some View {
        let waiting = store.sessions.filter { $0.state == .waiting }.count
        let working = store.sessions.filter { $0.state == .working }.count
        var parts: [String] = []
        if working > 0 { parts.append(L("работают: %d", working)) }
        return HStack(spacing: 8) {
            Text(L("Сессии")).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
            if !parts.isEmpty {
                Text(parts.joined(separator: " · "))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
            if waiting > 0 {
                Text(L("ждут тебя: %d", waiting))
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 7)
                    .frame(height: 16)
                    .background(Capsule().fill(AgentPalette.waiting.main.opacity(0.22)))
                    .foregroundStyle(AgentPalette.waiting.main)
            }
            Spacer()
            if let note = store.actionNote {
                Text(note)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(NotchStyle.tap, value: note)
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13))
                .foregroundStyle(NotchStyle.metal)
            Text(L("Пока ни одного агента. Запусти codex или opencode в терминале — они появятся здесь сами."))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.04)))
        .notchAppear(true)
    }
}

/// Командная строка: чистая математика считается на месте, остальное уходит в opencode.
struct AgentCommandBar: View {
    @ObservedObject var runner: AgentRunner
    @ViewState private var text = ""
    @ViewState private var flash = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField(L("Команда или вопрос агенту"), text: $text, onCommit: run)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(runner.running ? AgentPalette.opencode.main.opacity(0.4) : .white.opacity(0.10), lineWidth: 1))
                if runner.running {
                    Button(L("Стоп")) { runner.stop() }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AgentPalette.waiting.main)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(AgentPalette.waiting.main.opacity(0.18)))
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    Button(L("Пуск")) { run() }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(NotchStyle.metal))
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(NotchStyle.tap, value: runner.running)
            if !flash.isEmpty {
                Text(flash)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NotchStyle.metal)
                    .transition(.opacity)
            } else if runner.running {
                Text(runner.output.components(separatedBy: "\n").suffix(3).joined(separator: "\n"))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .animation(NotchStyle.tap, value: flash)
    }

    private func run() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        text = ""
        if let value = Self.evaluate(t) {
            flash = "= " + value
            return
        }
        flash = ""
        runner.launch(t, continueLast: false)
    }

    /// «12*8+4» и подобные чистые выражения считаем локально, без агента.
    static func evaluate(_ s: String) -> String? {
        guard s.count <= 40,
              s.range(of: "^[0-9+\\-*/().\\s]+$", options: .regularExpression) != nil,
              s.contains("+") || s.contains("-") || s.contains("*") || s.contains("/") else { return nil }
        let cleaned = s.replacingOccurrences(of: ",", with: ".")
        guard let expr = try? NSExpression(format: cleaned),
              let value = expr.expressionValue(with: nil, context: nil) else { return nil }
        if let d = value as? Double {
            return d == d.rounded() ? String(Int(d)) : String(format: "%.4f", d)
        }
        return String(describing: value)
    }
}

private struct AgentCard: View {
    let session: AgentSession
    var onPermission: ((Bool) -> Void)? = nil

    private var palette: AgentPalette {
        switch session.state {
        case .waiting: return .waiting
        case .working: return session.kind == .codex ? .codex : .opencode
        case .idle: return .done
        }
    }
    private var stateText: String {
        session.state == .waiting ? L("Ожидает подтверждения") : (session.state == .working ? L("Работает") : L("Завершено"))
    }

    @ViewState private var pulse = false
    @ViewState private var shown = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            cardBody
        }
        .onAppear { shown = true }
    }

    private var cardBody: some View {
        HStack(spacing: 10) {
            // Иконка в цвет агента, как иконка на карточке зарядки.
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(palette.gradient)
                    .shadow(color: palette.glow, radius: session.state == .working ? 5 : 0)
                Image(systemName: session.kind == .codex ? "cpu.fill" : "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.displayName)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if session.state == .working || session.state == .waiting {
                        Circle().fill(palette.main)
                            .frame(width: 6, height: 6)
                            .scaleEffect(pulse ? 1.5 : 0.8)
                            .opacity(pulse ? 0.4 : 1)
                            .animation(NotchStyle.pulse, value: pulse)
                    } else {
                        Circle().fill(palette.main.opacity(0.6)).frame(width: 6, height: 6)
                    }
                    Text(stateText)
                        .font(.system(size: 10.5, weight: session.state == .waiting ? .semibold : .regular))
                        .foregroundStyle(session.state == .working || session.state == .waiting ? palette.main : Color.white.opacity(0.5))
                    if session.state == .working || session.state == .waiting {
                        Text(L("· %@", liveTime(since: session.lastActivity)))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }

            Spacer(minLength: 8)

            if let onPermission {
                VStack(spacing: 4) {
                    Button { onPermission(true) } label: {
                        Label(L("Разрешить"), systemImage: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AgentPalette.done.main)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(AgentPalette.done.main.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    Button { onPermission(false) } label: {
                        Label(L("Запретить"), systemImage: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AgentPalette.waiting.main)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(AgentPalette.waiting.main.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                Text(relTime(session.lastActivity))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(session.state == .waiting ? palette.main.opacity(0.10) : Color.white.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(palette.main.opacity(session.state == .waiting ? 0.35 : 0.0), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(NotchStyle.tap, value: session.state)
    }

    /// Живое время с последней активности: тикает каждую секунду.
    private func liveTime(since date: Date) -> String {
        let s = max(0, Int(-date.timeIntervalSinceNow))
        if s < 3600 { return String(format: "%02d:%02d", s / 60, s % 60) }
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    private func relTime(_ d: Date) -> String {
        let s = Int(-d.timeIntervalSinceNow)
        if s < 45 { return L("сейчас") }
        if s < 3600 { return L("%d мин", s / 60) }
        if s < 86400 { return L("%d ч", s / 3600) }
        return L("%d д", s / 86400)
    }
}

private func openInTerminal(_ s: AgentSession) {
    guard let tty = s.tty else {
        NSWorkspace.shared.launchApplication("Terminal")
        return
    }
    let script = """
    tell application "Terminal"
        activate
        repeat with w in windows
            repeat with t in tabs of w
                if (tty of t) as text is "\(tty)" then
                    set selected of t to true
                    set index of w to 1
                    set frontmost of w to true
                    exit repeat
                end if
            end repeat
        end repeat
    end tell
    """
    var error: NSDictionary?
    NSAppleScript(source: script)?.executeAndReturnError(&error)
}
