import SwiftUI

struct ControlsView: View {
    @ObservedObject var volume: VolumeController
    @ObservedObject var brightness: BrightnessController
    @ObservedObject var mixer: AppAudioMixer
    var openSettings: () -> Void = {}

    private var volumeIcon: String {
        speakerIcon(volume.isMuted ? 0 : volume.volume)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(spacing: 14) {
                row(title: L("Громкость"), available: volume.isAvailable,
                    hint: L("Устройство вывода не поддерживает регулировку")) {
                    CapsuleSlider(value: volume.isMuted ? 0 : Double(volume.volume),
                                  icon: volumeIcon,
                                  iconAction: { volume.toggleMute() },
                                  onChange: { volume.set(Float($0)) })
                }
                row(title: L("Яркость"), available: brightness.isAvailable,
                    hint: L("Недоступно для этого дисплея")) {
                    CapsuleSlider(value: Double(brightness.brightness),
                                  icon: brightness.brightness < 0.33 ? "sun.min.fill" : "sun.max.fill",
                                  onChange: { brightness.set(Float($0)) })
                }
            }
            .frame(width: 240)

            AppMixerList(mixer: mixer, openSettings: openSettings)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func row<Content: View>(title: String, available: Bool, hint: String,
                                    @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(title)
            if available {
                content()
            } else {
                Text(hint)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Capsule().fill(.white.opacity(0.06)))
            }
        }
    }
}

private func sectionTitle(_ title: String) -> some View {
    Text(title)
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(.white.opacity(0.55))
        .padding(.leading, 4)
}

private func speakerIcon(_ level: Float) -> String {
    if level < 0.01 { return "speaker.slash.fill" }
    if level < 0.33 { return "speaker.wave.1.fill" }
    if level < 0.66 { return "speaker.wave.2.fill" }
    return "speaker.wave.3.fill"
}

/// Приложения, которые сейчас играют звук, с отдельной громкостью и mute.
private struct AppMixerList: View {
    @ObservedObject var mixer: AppAudioMixer
    var openSettings: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionTitle(L("Приложения"))
                Spacer()
                // Настройки Notchly открываются отдельным окном, а остров остаётся раскрытым —
                // так изменения видно сразу.
                Button(action: openSettings) {
                    Label(L("Настройки"), systemImage: "gearshape.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(hovering ? 0.95 : 0.6))
                        .padding(.horizontal, 9)
                        .frame(height: 20)
                        .background(Capsule().fill(.white.opacity(hovering ? 0.14 : 0.07)))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
                .help(L("Настройки Notchly: вкладки, функции, уведомления, буфер обмена"))
            }
            if mixer.access == .denied {
                notice(icon: "waveform.badge.exclamationmark",
                       text: L("Разрешите запись системного аудио, чтобы менять громкость приложений"),
                       button: L("Открыть настройки")) { mixer.openPrivacySettings() }
            } else if mixer.access == .unsupported {
                notice(icon: "waveform.slash",
                       text: L("Нужна macOS 14.2 или новее"), button: nil) {}
            } else if mixer.apps.isEmpty {
                notice(icon: "speaker.zzz.fill", text: L("Сейчас ничего не играет"), button: nil) {}
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 7) {
                        ForEach(mixer.apps) { app in
                            AppMixerRow(app: app, mixer: mixer)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.9), value: mixer.apps.map(\.id))
                }
            }
        }
    }

    private func notice(icon: String, text: String, button: String?, action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
            if let button {
                Button(action: action) {
                    Text(button)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.06)))
    }
}

private struct AppMixerRow: View {
    var app: AudioApp
    @ObservedObject var mixer: AppAudioMixer

    var body: some View {
        let muted = mixer.isMuted(app)
        let level = muted ? 0 : mixer.level(for: app)
        HStack(spacing: 10) {
            Group {
                if let icon = app.icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "app.fill").resizable().foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(width: 26, height: 26)
            .opacity(app.isPlaying ? 1 : 0.5)
            .help(app.name)

            CapsuleSlider(value: Double(level),
                          icon: speakerIcon(level),
                          height: 30,
                          iconAction: { mixer.toggleMute(app) },
                          onChange: { mixer.setLevel(Float($0), for: app) })
        }
    }
}
