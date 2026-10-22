import SwiftUI

/// Свёрнутый остров во время воспроизведения: обложка слева от выреза, эквалайзер справа.
/// После смены трека на пару секунд опускается «шторка» с названием.
struct CompactMusicView: View {
    @ObservedObject var media: MediaController
    @ObservedObject var model: IslandModel

    var body: some View {
        let h = model.notchSize.height
        let art = min(h - 10, 26)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ArtworkView(image: media.artwork, accent: media.accent, cornerRadius: 6)
                    .frame(width: art, height: art)
                Spacer(minLength: model.notchSize.width)
                EqualizerView(isPlaying: media.isPlaying, color: media.accent)
                    .frame(width: 18, height: 13)
                    .padding(.trailing, 3)
            }
            .padding(.horizontal, 9)
            .frame(height: h)

            if model.peek && media.hasTrack {
                HStack(spacing: 6) {
                    Text(media.title)
                        .foregroundStyle(.white)
                        .fontWeight(.semibold)
                    if !media.artist.isEmpty {
                        Text("·").foregroundStyle(.white.opacity(0.4))
                        Text(media.artist).foregroundStyle(media.accent.opacity(0.9))
                    }
                }
                .font(.system(size: 12.5))
                .lineLimit(1)
                .padding(.horizontal, 18)
                .frame(height: IslandMetrics.peekExtraHeight - 6)
                .id(media.peekID)
                .transition(.asymmetric(
                    insertion: .offset(y: -6).combined(with: .opacity).animation(.easeOut(duration: 0.35).delay(0.08)),
                    removal: .opacity.animation(.easeIn(duration: 0.18))))
            }
        }
    }
}

/// Индикатор громкости или яркости по бокам от выреза.
struct HUDView: View {
    var state: HUDState
    var notchWidth: CGFloat

    private var isSilent: Bool { state.kind == .volume && (state.muted || state.value < 0.01) }

    var body: some View {
        let shown = state.muted ? 0 : CGFloat(state.value)
        HStack(spacing: 0) {
            // Одна и та же иконка с «переменным значением»: дуги загораются плавно,
            // без замены символа на каждом шаге.
            ZStack {
                if isSilent {
                    Image(systemName: "speaker.slash.fill")
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                } else {
                    Image(systemName: state.kind == .volume ? "speaker.wave.3.fill" : "sun.max.fill",
                          variableValue: Double(state.value))
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 26, alignment: .leading)
            .padding(.leading, 14)
            .animation(.smooth(duration: 0.25), value: isSilent)
            Spacer(minLength: notchWidth)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule()
                    .fill(Color.white.gradient)
                    .frame(width: 48 * shown)
            }
            .frame(width: 48, height: 5)
            .padding(.trailing, 14)
            .animation(.smooth(duration: 0.22), value: shown)
        }
        .frame(maxHeight: .infinity)
    }
}

/// «Скопировано из …»: иконка приложения слева от выреза, значок буфера справа.
struct ClipPeekView: View {
    var group: ClipGroup
    var icon: NSImage
    var notchWidth: CGFloat
    @ViewState private var appeared = false

    var body: some View {
        HStack(spacing: 0) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 20, height: 20)
                .scaleEffect(appeared ? 1 : 0.4)
                .padding(.leading, 16)
            Spacer(minLength: notchWidth)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: appeared)
                .scaleEffect(appeared ? 1 : 0.4)
                .padding(.trailing, 18)
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78).delay(0.05)) { appeared = true }
        }
    }
}

/// Фокус в свёрнутом острове: слева кольцо прогресса, справа обратный отсчёт.
struct FocusCompactView: View {
    @ObservedObject var focus: FocusTimer
    var notchWidth: CGFloat

    static func tint(for phase: FocusTimer.Phase) -> Color {
        phase.isBreak ? BatteryTint.color(100) : Color(hue: 0.02, saturation: 0.72, brightness: 0.88)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let tint = Self.tint(for: focus.phase)
            HStack(spacing: 0) {
                ZStack {
                    Circle().stroke(.white.opacity(0.15), lineWidth: 2.5)
                    CountdownArc(progress: focus.progress(at: context.date),
                                 rate: focus.progressRate(at: context.date), tint: tint, lineWidth: 2.5)
                    Image(systemName: focus.phase.isBreak ? "cup.and.saucer.fill" : "timer")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 20, height: 20)
                .padding(.leading, 14)
                Spacer(minLength: notchWidth)
                Text(focus.remaining(at: context.date).clock)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(focus.isPaused ? .white.opacity(0.45) : .white)
                    .padding(.trailing, 14)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// Обычный таймер в свёрнутом острове: песочные часы в кольце и обратный отсчёт.
struct CountdownCompactView: View {
    @ObservedObject var countdown: CountdownTimer
    var notchWidth: CGFloat

    static let tint = Color(hue: 0.09, saturation: 0.8, brightness: 0.9)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 0) {
                ZStack {
                    Circle().stroke(.white.opacity(0.15), lineWidth: 2.5)
                    CountdownArc(progress: countdown.progress(at: context.date),
                                 rate: countdown.progressRate(at: context.date), tint: Self.tint, lineWidth: 2.5)
                    Image(systemName: "hourglass")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 20, height: 20)
                .padding(.leading, 14)
                Spacer(minLength: notchWidth)
                Text(countdown.remaining(at: context.date).clock)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(countdown.isPaused ? .white.opacity(0.45) : .white)
                    .padding(.trailing, 14)
            }
            .frame(maxHeight: .infinity)
        }
    }
}
