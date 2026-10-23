import SwiftUI

/// Всплывающая карточка события, как на iPhone: зарядка MacBook или подключение наушников.
struct EventView: View {
    var event: IslandEvent
    var model: IslandModel
    var onClose: () -> Void

    private var notchHeight: CGFloat { model.notchSize.height }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            card
        }
    }

    @ViewBuilder
    private var card: some View {
        switch event {
        case .charging(let info):
            ChargingEvent(info: info)
                .padding(.horizontal, 26)
                .padding(.bottom, 16)
                .frame(maxHeight: .infinity)
        case .device(let device):
            DeviceEvent(device: device)
                .padding(.horizontal, 26)
                .padding(.bottom, 16)
                .frame(maxHeight: .infinity)
        case .deviceSheet(let device):
            DeviceSheet(device: device, onClose: onClose)
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
                .frame(maxHeight: .infinity)
        case .notification(let item):
            NotificationEvent(item: item, pop: model.settings.notificationPop)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .frame(maxHeight: .infinity)
        case .printer(let status):
            PrinterEvent(status: status)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .frame(maxHeight: .infinity)
        case .wake:
            WakeView()
                .padding(.horizontal, 26)
                .padding(.bottom, 16)
                .frame(maxHeight: .infinity)
        case .otp(let code):
            OtpEvent(code: code, onClose: onClose)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .frame(maxHeight: .infinity)
        case .download(let path, let bytes):
            DownloadEvent(path: path, bytes: bytes, onClose: onClose)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .frame(maxHeight: .infinity)
        case .reminder(let reminder):
            ReminderEvent(reminder: reminder, model: model, onClose: onClose)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .frame(maxHeight: .infinity)
        case .focus(let transition):
            FocusEvent(transition: transition, model: model)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .frame(maxHeight: .infinity)
        case .timerDone(let duration):
            ActionCard(symbol: "hourglass.bottomhalf.filled", tint: .orange,
                       title: L("Таймер завершён"),
                       subtitle: duration.durationText) {
                CardButton(title: L("Ещё раз"), systemImage: "arrow.clockwise") {
                    model.countdown.start(seconds: Int(duration.rounded()))
                    model.dismissEvent()
                }
                CardButton(title: L("Готово"), prominent: true) { model.dismissEvent() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .frame(maxHeight: .infinity)
        case .alarm(let alarm):
            ActionCard(symbol: "alarm.fill", tint: .yellow, title: L("Будильник · %@", "\(alarm.time)"),
                       subtitle: L("Пора!")) {
                CardButton(title: L("+5 мин")) {
                    model.alarms.snooze()
                    model.dismissEvent()
                }
                CardButton(title: L("Стоп"), systemImage: "stop.fill", prominent: true) { model.dismissEvent() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .frame(maxHeight: .infinity)
        }
    }
}

/// Небольшая кнопка-капсула для карточек.
private struct CardButton: View {
    var title: String
    var systemImage: String? = nil
    var prominent = false
    var tint: Color = .white
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 10.5, weight: .bold)) }
                Text(title).font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(prominent ? .black : .white.opacity(0.85))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(prominent ? AnyShapeStyle(tint) : AnyShapeStyle(.white.opacity(0.14))))
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(PressableStyle())
    }
}

/// Карточка с иконкой, заголовком, подписью и кнопками справа.
private struct ActionCard<Buttons: View>: View {
    var symbol: String
    var tint: Color
    var title: String
    var subtitle: String
    @ViewBuilder var buttons: () -> Buttons
    @ViewState private var appeared = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer(minLength: 6)
            HStack(spacing: 6) { buttons() }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -4)
        .onAppear { withAnimation(.easeOut(duration: 0.35).delay(0.12)) { appeared = true } }
    }
}

// MARK: - Блютуз-устройство (карточка в стиле зарядки)

private struct DeviceEvent: View {
    var device: DeviceBattery
    @ViewState private var appeared = false
    @ViewState private var shownPercent = 0

    private var disconnected: Bool { !device.isConnected }
    private var accent: Color { disconnected ? Color.orange : Color.green }
    /// Заряд основных наушников, если система его сообщила.
    private var percent: Int? {
        let pair = device.levels.filter { $0.label == "Левый" || $0.label == "Правый" }
        return pair.min(by: { $0.percent < $1.percent })?.percent ?? device.levels.first?.percent
    }

    var body: some View {
        HStack(spacing: 22) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: device.symbol)
                    .font(.system(size: 50, weight: .light))
                    .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.78)], startPoint: .top, endPoint: .bottom))
                Image(systemName: disconnected ? "bluetooth.slash" : "checkmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(accent)
                    .offset(x: 10, y: -8)
                    .scaleEffect(appeared ? 1 : 0.2)
                    .opacity(appeared ? 1 : 0)
            }
            .frame(width: 92, height: 80)
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.9)

            VStack(alignment: .leading, spacing: 6) {
                Text(L(disconnected ? "Отключено" : "Подключено"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                Text(device.name)
                    .font(.system(size: 17, weight: .bold))
                if let percent {
                    HStack(spacing: 10) {
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.14))
                            Capsule()
                                .fill(accent)
                                .frame(width: 150 * CGFloat(shownPercent) / 100)
                        }
                        .frame(width: 150, height: 8)
                        Text("\(shownPercent)%")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(shownPercent)))
                    }
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(x: appeared ? 0 : 10)
            Spacer(minLength: 0)
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.45).delay(0.1)) { appeared = true }
            if let percent {
                withAnimation(.smooth(duration: 0.9).delay(0.3)) { shownPercent = percent }
            }
        }
    }
}

// MARK: - Фокус

private struct FocusEvent: View {
    var transition: FocusTimer.Transition
    var model: IslandModel
    @ViewState private var appeared = false

    private var title: String {
        switch transition {
        case .workFinished(let next, _): return next == .longBreak ? L("Длинный перерыв · 15 мин") : L("Перерыв · 5 мин")
        case .breakFinished: return L("Перерыв окончен")
        }
    }

    private var subtitle: String {
        switch transition {
        case .workFinished(_, let held):
            let done = L("Подходов сегодня: %@", "\(model.focus.completedToday)")
            return held > 0 ? L("%@ · ждут уведомления: %@", "\(done)", "\(held)") : done
        case .breakFinished: return L("Готовы к следующему подходу?")
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transition == .breakFinished ? "timer" : "cup.and.saucer.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(transition == .breakFinished ? Color.red.gradient : Color.green.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer(minLength: 6)
            switch transition {
            case .workFinished:
                CardButton(title: L("Пропустить")) {
                    model.focus.skip()
                    model.dismissEvent()
                }
            case .breakFinished:
                CardButton(title: L("Начать фокус"), systemImage: "play.fill", prominent: true) {
                    model.startFocus(taskID: model.focus.taskID, title: model.focus.taskTitle)
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -4)
        .onAppear { withAnimation(.easeOut(duration: 0.35).delay(0.12)) { appeared = true } }
    }
}

// MARK: - Напоминание

private struct ReminderEvent: View {
    var reminder: Reminder
    var model: IslandModel
    var onClose: () -> Void
    @ViewState private var appeared = false

    private var isCalendar: Bool { reminder.source == .calendar }

    private var isMeeting: Bool {
        let host = reminder.link?.host ?? ""
        return ["zoom", "meet.google", "teams", "facetime", "telemost"].contains { host.contains($0) }
    }

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 12) {
                Image(systemName: isCalendar ? "calendar" : "checklist")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isCalendar ? Color.red.gradient : Color.orange.gradient))

                VStack(alignment: .leading, spacing: 2) {
                    Text(reminder.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(reminder.subtitle())
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                HStack(spacing: 6) {
                    if let link = reminder.link {
                        CardButton(title: isMeeting ? L("Войти") : L("Открыть"),
                                   systemImage: isMeeting ? "video.fill" : "link",
                                   prominent: true, tint: isMeeting ? .green : .white) {
                            NSWorkspace.shared.open(link)
                            onClose()
                        }
                    }
                    CardButton(title: L("+5 мин")) { model.snoozeReminder(reminder) }
                        .help(L("Напомнить через 5 минут"))
                    if reminder.taskID != nil {
                        CardButton(title: L("Готово"), systemImage: "checkmark",
                                   prominent: reminder.link == nil) { model.completeReminder(reminder) }
                    }
                }
            }
            // «ОК»: белая овальная кнопка, просто закрывает карточку.
            Button(action: onClose) {
                Text(L("ОК"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 36)
                    .frame(height: 27)
                    .background(Capsule().fill(Color.white))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -4)
        .onAppear { withAnimation(.easeOut(duration: 0.35).delay(0.12)) { appeared = true } }
    }
}

// MARK: - Зелёная галочка агента: круг по кругу, как разблокировка Mac

/// Иконка «задача выполнена»: белое кольцо прочерчивается по часовой стрелке
/// (заполняется только обод, внутри пусто), затем внутри прорисовывается галочка.
private struct AgentDoneMark: View {
    var color: Color
    @ViewState private var ring: CGFloat = 0
    @ViewState private var check: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(color.gradient)
            Circle()
                .trim(from: 0, to: ring)
                .stroke(.white.opacity(0.95), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .padding(3)
                .rotationEffect(.degrees(-90))
            CheckShape()
                .trim(from: 0, to: check)
                .stroke(.white, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                .padding(13)
        }
        .frame(width: 40, height: 40)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.45).delay(0.3)) { ring = 1 }
            withAnimation(.easeOut(duration: 0.25).delay(0.75)) { check = 1 }
        }
    }
}

/// Контур галочки в normalized-координатах своего прямоугольника.
private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.08))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.maxY - rect.height * 0.08))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.1))
        return p
    }
}

// MARK: - Уведомление

private struct NotificationEvent: View {
    var item: AppNotification
    /// Вкл/выкл пружинки появления (настройка).
    var pop = true
    @ViewState private var appeared = false
    @ViewState private var iconPopped = false

    private var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.bundleID) }

    /// Кто прислал: подзаголовок уведомления (так делает macOS), иначе имя приложения.
    private var sender: String? {
        if !item.subtitle.isEmpty { return item.subtitle }
        if item.bundleID == AppNotification.gmailID { return "Gmail" }
        guard let url = appURL, let bundle = Bundle(url: url) else { return nil }
        let info = bundle.infoDictionary
        return (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String)
    }

    private var time: String {
        guard Date().timeIntervalSince(item.date) > 60 else { return L("сейчас") }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        f.locale = Locale(identifier: "ru_RU")
        return f.localizedString(for: item.date, relativeTo: Date())
    }

    /// Свой цвет для уведомлений от агентов: как на вкладке «Агенты».
    private var agentColor: Color {
        item.body == L("Задача выполнена") ? AgentPalette.done.main : AgentPalette.opencode.main
    }

    private var icon: some View {
        Group {
            if item.bundleID == "ru.iabrik.agents" {
                if item.body == L("Задача выполнена") {
                    AgentDoneMark(color: agentColor)
                } else {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(agentColor.gradient))
                }
            } else if item.bundleID == AppNotification.gmailID {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.red.gradient))
            } else if let url = appURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Image(systemName: "app.badge.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.55))
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.08)))
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    var body: some View {
        HStack(spacing: 12) {
            icon
                .scaleEffect(iconPopped ? 1 : 0.25)
                .rotationEffect(.degrees(iconPopped ? 0 : -10))
                .opacity(iconPopped ? 1 : 0)
                .shadow(color: iconPopped ? .white.opacity(0.25) : .clear, radius: 12)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let sender {
                        Text(sender.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.42))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(time)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if !item.body.isEmpty {
                    Text(item.body)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
                }
            }
        }
        .id(item.id)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -10)
        .scaleEffect(appeared ? 1 : 0.94, anchor: .top)
        .onAppear {
            if pop {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) { appeared = true }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.1)) { iconPopped = true }
            } else {
                appeared = true
                iconPopped = true
            }
        }
    }
}

// MARK: - Зарядка

private struct ChargingEvent: View {
    var info: BatteryInfo
    @ViewState private var appeared = false
    @ViewState private var shownPercent = 0

    var body: some View {
        HStack(spacing: 22) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 50, weight: .light))
                    .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.78)], startPoint: .top, endPoint: .bottom))
                Image(systemName: info.charging ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(info.charging ? Color.green : Color.orange)
                    .offset(x: 10, y: -8)
                    .scaleEffect(appeared ? 1 : 0.2)
                    .opacity(appeared ? 1 : 0)
            }
            .frame(width: 92, height: 80)
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.9)

            VStack(alignment: .leading, spacing: 6) {
                Text(L(info.charging ? "Зарядка" : "Зарядка отключена"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(info.charging ? Color.green : Color.orange)
                Text("MacBook")
                    .font(.system(size: 17, weight: .bold))
                HStack(spacing: 10) {
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.14))
                        Capsule()
                            .fill(info.charging ? Color.green : Color.orange)
                            .frame(width: 150 * CGFloat(shownPercent) / 100)
                    }
                    .frame(width: 150, height: 8)
                    Text("\(shownPercent)%")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(shownPercent)))
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(x: appeared ? 0 : 10)
            Spacer(minLength: 0)
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.45).delay(0.1)) { appeared = true }
            withAnimation(.smooth(duration: 0.9).delay(0.3)) { shownPercent = info.percent }
        }
    }
}

// MARK: - Наушники (карточка как на iPhone)

private struct DeviceSheet: View {
    var device: DeviceBattery
    var onClose: () -> Void
    @ViewState private var appeared = false

    /// «AirPods Max (Имя)» → «AirPods Max», как на iPhone.
    private var title: String {
        device.name.replacingOccurrences(of: #"\s*\(.*\)\s*$"#, with: "", options: .regularExpression)
    }

    private struct Column: Identifiable {
        enum Art { case pair(pro: Bool), bud(pro: Bool, mirrored: Bool), chargingCase(DeviceArt.Kind), headphones }
        var id: String
        var art: Art
        var level: DeviceBattery.Level?
    }

    /// Как на iPhone: наушники вместе (если заряд одинаковый) или по отдельности, и кейс.
    private var columns: [Column] {
        let kind = DeviceArt.Kind(device: device)
        let pro: Bool
        switch kind {
        case .airPodsPro: pro = true
        case .airPods: pro = false
        case .symbol: return [Column(id: "main", art: .headphones, level: device.primaryLevel)]
        }
        let left = device.levels.first { $0.label == "Левый" }
        let right = device.levels.first { $0.label == "Правый" }
        let casing = device.levels.first { $0.label == "Кейс" }
        var result: [Column] = []
        if let left, let right, left.percent != right.percent {
            result.append(Column(id: "L", art: .bud(pro: pro, mirrored: false), level: left))
            result.append(Column(id: "R", art: .bud(pro: pro, mirrored: true), level: right))
        } else if let bud = [left, right].compactMap({ $0 }).min(by: { $0.percent < $1.percent }) {
            var level = bud
            level.charging = (left?.charging ?? false) || (right?.charging ?? false)
            result.append(Column(id: "buds", art: .pair(pro: pro), level: level))
        } else {
            result.append(Column(id: "buds", art: .pair(pro: pro), level: nil))
        }
        result.append(Column(id: "case", art: .chargingCase(kind), level: casing))
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title)
                    .font(.system(size: 19, weight: .bold))
                    .lineLimit(1)
                    .padding(.horizontal, 36)
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(.white.opacity(0.14)))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .opacity(appeared ? 1 : 0)

            Spacer(minLength: 6)

            let columns = columns
            HStack(alignment: .bottom, spacing: columns.count > 2 ? 26 : 44) {
                ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                    VStack(spacing: 8) {
                        art(column.art)
                            .frame(height: 86)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 8)
                            .animation(.smooth(duration: 0.5).delay(0.15 + Double(index) * 0.08), value: appeared)
                        if let level = column.level {
                            ChargeRing(percent: level.percent, charging: level.charging, size: 28)
                            Text("\(level.percent) %")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.9))
                        } else {
                            Text(L("Подключено"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }
            }
        }
        .onAppear { withAnimation(.smooth(duration: 0.4).delay(0.12)) { appeared = true } }
    }

    @ViewBuilder
    private func art(_ art: Column.Art) -> some View {
        switch art {
        case .pair(let pro):
            EarbudPair(pro: pro, height: 86)
        case .bud(let pro, let mirrored):
            EarbudArt(pro: pro)
                .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                .scaleEffect(86 / 92)
                .frame(width: 56, height: 86)
        case .chargingCase(let kind):
            DeviceArt(kind: kind, open: 0, width: 98)
        case .headphones:
            DeviceArt(kind: DeviceArt.Kind(device: device), open: 0, width: 98)
        }
    }
}

/// Маленькая батарейка, которая заполняется при появлении.
/// Значок батареи. Во время зарядки заливка плавно дорастает до текущего процента,
/// а по ней мягко пробегает световая волна — как на iPhone.
struct BatteryGlyph: View {
    var percent: Int
    var charging = false
    var width: CGFloat = 24
    /// Белая заливка без зелёного и красного — для карточки наушников.
    var monochrome = false

    private var height: CGFloat { width * 0.46 }
    private var color: Color {
        if monochrome { return .white.opacity(0.9) }
        return charging ? .green : percent <= 20 ? .red : .green
    }

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
                    .stroke(.white.opacity(0.45), lineWidth: 1)
                // Статичная заливка без анимаций: так батарейка ничего не стоит процессору.
                RoundedRectangle(cornerRadius: height * 0.16, style: .continuous)
                    .fill(color)
                    .frame(width: max(2, (width - 4) * CGFloat(percent) / 100))
                    .padding(2)
            }
            .frame(width: width, height: height)
            RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.45)).frame(width: 1.5, height: height * 0.38)
        }
    }
}

/// Карточка статуса печати с принтера.
struct PrinterEvent: View {
    var status: PrinterStatus
    @ViewState private var appeared = false

    private var title: String {
        switch status.state {
        case "printing": return L("Печатает")
        case "paused": return L("Пауза")
        case "finished": return L("Печать завершена")
        default: return L("Принтер свободен")
        }
    }

    private var timeLeft: String {
        guard status.isPrinting, status.remaining > 0 else { return "" }
        let min = max(1, status.remaining / 60)
        return L("осталось %@", min >= 60 ? String(format: "%d ч %d мин", min / 60, min % 60) : String(format: "%d мин", min))
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "printer.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.cyan.gradient))
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(status.name.isEmpty ? L("Bambu Lab") : status.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(status.isPrinting ? L("\(status.percent)%") : title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(status.state == "finished" ? Color.green : Color.white.opacity(0.7))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.14))
                        Capsule().fill(Color.cyan.gradient)
                            .frame(width: geo.size.width * CGFloat(status.percent) / 100)
                    }
                }
                .frame(height: 5)
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6))
                    if !timeLeft.isEmpty {
                        Text(timeLeft).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6))
                    }
                    if status.layer > 0 {
                        Text(L("слой \(status.layer)/\(max(status.layer, status.layers))"))
                            .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer(minLength: 4)
                    if status.nozzle > 0 || status.bed > 0 {
                        Text(String(format: "сопло %d° · стол %d°", status.nozzle, status.bed))
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -10)
        .scaleEffect(appeared ? 1 : 0.94, anchor: .top)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) { appeared = true }
        }
    }
}


/// Карточка одноразового кода, выловленного из буфера обмена.
struct OtpEvent: View {
    let code: String
    let onClose: () -> Void
    @ViewState private var copied = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.green.gradient))
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(L("Одноразовый код"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Text(code)
                    .font(.system(size: 27, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 8)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { onClose() }
            } label: {
                Text(copied ? L("Скопировано") : L("Скопировать"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.green.gradient))
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
        }
    }
}

/// Карточка завершённой загрузки.
struct DownloadEvent: View {
    let path: String
    let bytes: Int64
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.blue.gradient))
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(L("Загрузка завершена"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Text((path as NSString).lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if bytes > 0 {
                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                onClose()
            } label: {
                Text(L("Открыть"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.blue.gradient))
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
        }
    }
}
