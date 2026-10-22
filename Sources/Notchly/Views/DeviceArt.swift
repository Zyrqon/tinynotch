import SwiftUI

/// Нарисованные устройства для карточек: кейс AirPods с открывающейся крышкой,
/// AirPods Max и прочие наушники. Всё векторное и без размытия, чтобы было чётко.
struct DeviceArt: View {
    enum Kind {
        case airPodsPro, airPods, symbol(String)

        init(device: DeviceBattery) {
            let n = device.name.lowercased()
            if n.contains("airpods") && n.contains("pro") { self = .airPodsPro }
            else if n.contains("airpods") && !n.contains("max") { self = .airPods }
            else { self = .symbol(device.symbol) }
        }

        var isPro: Bool { if case .airPodsPro = self { return true } else { return false } }
    }

    var kind: Kind
    /// 0 — крышка закрыта, 1 — открыта, наушники видны.
    var open: CGFloat
    /// Ширина рисунка; всё остальное масштабируется от неё.
    var width: CGFloat = 160

    var body: some View {
        Group {
            switch kind {
            case .airPodsPro: CaseArt(pro: true, open: open)
            case .airPods: CaseArt(pro: false, open: open)
            case .symbol(let name): SymbolArt(name: name)
            }
        }
        .frame(width: 160, height: 140)
        .scaleEffect(width / 160)
        .frame(width: width, height: width * 140 / 160)
    }
}

// MARK: - Кейс AirPods

private struct CaseArt: View {
    var pro: Bool
    var open: CGFloat

    // Pro — широкий «горизонтальный» кейс, обычные AirPods — более узкий и высокий.
    private var bodySize: CGSize { pro ? CGSize(width: 128, height: 64) : CGSize(width: 100, height: 70) }
    private var lidHeight: CGFloat { pro ? 30 : 34 }
    private var radius: CGFloat { pro ? 26 : 24 }

    private let white = LinearGradient(
        stops: [.init(color: Color(white: 1.0), location: 0),
                .init(color: Color(white: 0.965), location: 0.45),
                .init(color: Color(white: 0.84), location: 1)],
        startPoint: .top, endPoint: .bottom)
    private let sideShade = LinearGradient(
        stops: [.init(color: .black.opacity(0.16), location: 0),
                .init(color: .clear, location: 0.2),
                .init(color: .clear, location: 0.8),
                .init(color: .black.opacity(0.18), location: 1)],
        startPoint: .leading, endPoint: .trailing)

    var body: some View {
        let floorY: CGFloat = 132
        let bodyTop = floorY - bodySize.height
        let well = 16 * open                       // видимая «чаша» открытого кейса
        let lidBottom = bodyTop - well
        let lidH = lidHeight + 16 * open            // открытая крышка выглядит выше — стоит вертикально

        ZStack(alignment: .topLeading) {
            // Тень на «полу» — градиент, а не размытие.
            Ellipse()
                .fill(RadialGradient(colors: [.black.opacity(0.7), .clear], center: .center, startRadius: 1, endRadius: 72))
                .frame(width: bodySize.width + 30, height: 14)
                .position(x: 80, y: floorY + 2)

            // Крышка: снаружи белая, изнутри (когда открыта) — сероватая.
            UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: 6 * open,
                                   bottomTrailingRadius: 6 * open, topTrailingRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.97 - 0.1 * open), Color(white: 0.88 - 0.12 * open)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: 6 * open,
                                           bottomTrailingRadius: 6 * open, topTrailingRadius: radius, style: .continuous)
                        .fill(sideShade))
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: 6 * open,
                                           bottomTrailingRadius: 6 * open, topTrailingRadius: radius, style: .continuous)
                        .stroke(.white.opacity(0.9), lineWidth: 0.6))
                .frame(width: bodySize.width - 6 * open, height: lidH)
                .position(x: 80, y: lidBottom - lidH / 2)

            // Внутренность кейса с наушниками.
            if open > 0.01 {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [Color(white: 0.62), Color(white: 0.8)], startPoint: .top, endPoint: .bottom))
                    HStack(spacing: pro ? 18 : 10) {
                        BudHead(pro: pro, mirrored: false)
                        BudHead(pro: pro, mirrored: true)
                    }
                    .offset(y: -6 * open)
                }
                .frame(width: bodySize.width - 18, height: max(well + 8, 1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .opacity(Double(open))
                .position(x: 80, y: bodyTop - well / 2 + 2)
            }

            // Корпус.
            UnevenRoundedRectangle(topLeadingRadius: 8 + 6 * (1 - open), bottomLeadingRadius: radius,
                                   bottomTrailingRadius: radius, topTrailingRadius: 8 + 6 * (1 - open), style: .continuous)
                .fill(white)
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: radius,
                                           bottomTrailingRadius: radius, topTrailingRadius: 8, style: .continuous)
                        .fill(sideShade))
                .overlay(alignment: .top) {
                    // Шов между крышкой и корпусом.
                    Rectangle().fill(Color(white: 0.55).opacity(0.8)).frame(height: 1.2).padding(.horizontal, 8)
                }
                .overlay(alignment: .topLeading) {
                    // Блик.
                    Capsule()
                        .fill(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: bodySize.width * 0.45, height: 5)
                        .offset(x: 14, y: 8)
                }
                .overlay {
                    // Индикатор зарядки спереди.
                    Circle()
                        .fill(Color.green.opacity(0.35 + 0.6 * Double(open)))
                        .frame(width: 4, height: 4)
                        .offset(y: -bodySize.height * 0.08)
                }
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: radius,
                                           bottomTrailingRadius: radius, topTrailingRadius: 8, style: .continuous)
                        .stroke(.black.opacity(0.12), lineWidth: 0.6))
                .frame(width: bodySize.width, height: bodySize.height)
                .position(x: 80, y: floorY - bodySize.height / 2)
        }
        .frame(width: 160, height: 140)
    }
}

/// Головка наушника, лежащего в кейсе: белый корпус, серая амбушюра (у Pro) и сеточка.
private struct BudHead: View {
    var pro: Bool
    var mirrored: Bool

    var body: some View {
        ZStack {
            Ellipse()
                .fill(LinearGradient(colors: [.white, Color(white: 0.86)], startPoint: .top, endPoint: .bottom))
                .frame(width: 30, height: 22)
                .overlay(Ellipse().stroke(.black.opacity(0.12), lineWidth: 0.5))
            if pro {
                Ellipse()
                    .fill(LinearGradient(colors: [Color(white: 0.82), Color(white: 0.68)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 17, height: 12)
                    .overlay(Ellipse().fill(Color(white: 0.35)).frame(width: 7, height: 4))
                    .offset(x: mirrored ? 6 : -6, y: -2)
            } else {
                Capsule()
                    .fill(Color(white: 0.2))
                    .frame(width: 10, height: 3)
                    .offset(x: mirrored ? 5 : -5, y: -3)
            }
        }
    }
}

// MARK: - Наушники без кейса

private struct SymbolArt: View {
    var name: String

    private static let silver = LinearGradient(
        stops: [.init(color: Color(white: 1), location: 0),
                .init(color: Color(white: 0.8), location: 0.55),
                .init(color: Color(white: 0.92), location: 1)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    /// AirPods Max в цвете Midnight: тёмно-синий алюминий с мягким бликом сверху.
    private static let midnight = LinearGradient(
        stops: [.init(color: Color(red: 0.42, green: 0.48, blue: 0.62), location: 0),
                .init(color: Color(red: 0.24, green: 0.29, blue: 0.40), location: 0.45),
                .init(color: Color(red: 0.15, green: 0.18, blue: 0.26), location: 1)],
        startPoint: .top, endPoint: .bottom)

    var body: some View {
        ZStack {
            Ellipse()
                .fill(RadialGradient(colors: [.black.opacity(0.7), .clear], center: .center, startRadius: 1, endRadius: 70))
                .frame(width: 130, height: 14)
                .offset(y: 60)
            Image(systemName: name)
                .font(.system(size: 92, weight: .light))
                .foregroundStyle(name.contains("airpodsmax") ? Self.midnight : Self.silver)
        }
    }
}

/// MacBook спереди в цвете Midnight: тёмно-синий корпус, чёрная рамка, экран с обоями и вырезом.
struct MacBookArt: View {
    var width: CGFloat

    static let midnight = [Color(red: 0.20, green: 0.23, blue: 0.29), Color(red: 0.12, green: 0.14, blue: 0.19)]

    var body: some View {
        let w = width
        let lidW = w * 0.84, lidH = w * 0.56
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // Кромка крышки цвета Midnight.
                UnevenRoundedRectangle(topLeadingRadius: w * 0.06, topTrailingRadius: w * 0.06, style: .continuous)
                    .fill(LinearGradient(colors: Self.midnight, startPoint: .top, endPoint: .bottom))
                // Чёрная рамка экрана.
                UnevenRoundedRectangle(topLeadingRadius: w * 0.05, topTrailingRadius: w * 0.05, style: .continuous)
                    .fill(Color.black)
                    .padding([.top, .horizontal], w * 0.012)
                // Экран с обоями.
                RoundedRectangle(cornerRadius: w * 0.025, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.24, blue: 0.55),
                                                  Color(red: 0.38, green: 0.26, blue: 0.62),
                                                  Color(red: 0.07, green: 0.10, blue: 0.22)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(.horizontal, w * 0.035)
                    .padding(.top, w * 0.035)
                    .padding(.bottom, w * 0.02)
                // Вырез камеры.
                UnevenRoundedRectangle(bottomLeadingRadius: w * 0.012, bottomTrailingRadius: w * 0.012)
                    .fill(Color.black)
                    .frame(width: w * 0.13, height: w * 0.028)
                    .padding(.top, w * 0.035)
            }
            .frame(width: lidW, height: lidH)

            // Нижняя часть корпуса с выемкой для открытия крышки.
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(bottomLeadingRadius: w * 0.03, bottomTrailingRadius: w * 0.03, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.30, green: 0.34, blue: 0.41), Self.midnight[1]],
                                         startPoint: .top, endPoint: .bottom))
                UnevenRoundedRectangle(bottomLeadingRadius: w * 0.02, bottomTrailingRadius: w * 0.02)
                    .fill(Self.midnight[1].opacity(0.9))
                    .frame(width: w * 0.16, height: w * 0.018)
            }
            .frame(width: w, height: w * 0.05)
        }
        .frame(width: w)
    }
}
