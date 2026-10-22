import SwiftUI

/// Цвет заряда: 100% — зелёный, к 20% плавно переходит в красный, ниже 20% — красный.
/// Оттенки чуть приглушённые, чтобы не «кричали» на чёрном острове.
enum BatteryTint {
    static func color(_ percent: Int) -> Color {
        let t = min(max(Double(percent - 20) / 80, 0), 1)
        return Color(hue: 0.33 * t, saturation: 0.78, brightness: 0.74 + 0.04 * t)
    }
}

/// Один наушник AirPods сбоку: головка, амбушюра (у Pro), сеточка, ножка с серебристым торцом.
/// Нарисован в холсте 60 × 92 и масштабируется целиком.
struct EarbudArt: View {
    var pro = true

    private let shell = LinearGradient(
        stops: [.init(color: .white, location: 0),
                .init(color: Color(white: 0.95), location: 0.5),
                .init(color: Color(white: 0.8), location: 1)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Ножка.
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.8), .white, Color(white: 0.86)],
                                     startPoint: .leading, endPoint: .trailing))
                .overlay(Capsule().stroke(.black.opacity(0.1), lineWidth: 0.5))
                .frame(width: 13, height: pro ? 50 : 56)
                .offset(x: 13, y: 28)
            // Серебристый торец ножки.
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.85), Color(white: 0.5)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 11, height: 4)
                .offset(x: 14, y: pro ? 75 : 81)
            // Амбушюра Pro — серая «шляпка» сбоку головки.
            if pro {
                Ellipse()
                    .fill(LinearGradient(colors: [Color(white: 0.9), Color(white: 0.72)], startPoint: .top, endPoint: .bottom))
                    .overlay(Ellipse().stroke(.black.opacity(0.12), lineWidth: 0.5))
                    .overlay(Ellipse().fill(Color(white: 0.45)).frame(width: 7, height: 9).offset(x: 3))
                    .frame(width: 20, height: 24)
                    .offset(x: 36, y: 9)
            }
            // Головка.
            Ellipse()
                .fill(shell)
                .overlay(Ellipse().stroke(.black.opacity(0.12), lineWidth: 0.5))
                .frame(width: pro ? 40 : 38, height: pro ? 33 : 34)
                .offset(x: 4, y: 3)
            // Сеточка микрофона и блик.
            Capsule()
                .fill(Color(white: 0.18))
                .frame(width: 9, height: 5)
                .rotationEffect(.degrees(-25))
                .offset(x: 11, y: 11)
            Capsule()
                .fill(LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(width: 14, height: 5)
                .offset(x: 20, y: 6)
        }
        .frame(width: 60, height: 92, alignment: .topLeading)
    }
}

/// Пара наушников, как на iPhone: один стоит прямо, второй чуть позади и развёрнут амбушюрой к нам.
struct EarbudPair: View {
    var pro = true
    /// Высота рисунка; ширина — пропорционально.
    var height: CGFloat = 90

    var body: some View {
        ZStack(alignment: .topLeading) {
            EarbudArt(pro: pro)
                .scaleEffect(x: -1, y: 1)
                .rotationEffect(.degrees(-14))
                .scaleEffect(0.92)
                .offset(x: 34, y: -2)
            EarbudArt(pro: pro)
                .offset(x: 0, y: 4)
        }
        .frame(width: 100, height: 100, alignment: .topLeading)
        .scaleEffect(height / 100)
        .frame(width: height, height: height)
    }
}

/// Кольцо заряда, как в окне подключения на iPhone: дуга по проценту, молния при зарядке.
struct ChargeRing: View {
    var percent: Int
    var charging = false
    var size: CGFloat = 30
    @ViewState private var progress: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.12), lineWidth: size * 0.12)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(BatteryTint.color(percent), style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(BatteryTint.color(percent))
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.smooth(duration: 0.9).delay(0.5)) { progress = Double(percent) / 100 }
        }
        .onChange(of: percent) { _, value in
            withAnimation(.smooth(duration: 0.6)) { progress = Double(value) / 100 }
        }
    }
}
