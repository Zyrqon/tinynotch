import SwiftUI

/// Главная: часы, дата, мини-плеер, погода и заряд MacBook / наушников.
struct HomeView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var media: MediaController
    @ObservedObject var batteries: DeviceBatteryMonitor
    var openMusic: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            HomeLeftColumn(media: media, tasks: model.tasks,
                           calendar: model.reminders.calendar, openMusic: openMusic)
                .frame(width: 200)
                .staggered(0)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 1)
                .padding(.vertical, 10)

            HStack(spacing: 10) {
                WeatherCard(service: model.weather).staggered(1)
                BatteryCarousel(mac: batteries.mac, headphones: batteries.headphones,
                                accessories: batteries.accessories, phone: batteries.phone).staggered(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: batteries.devices)
        .onAppear {
            batteries.refresh()
            batteries.keepsFresh = true
        }
        .onDisappear { batteries.keepsFresh = false }
    }

}

/// Левая колонка главной: часы и дата; без музыки — ещё и сводка задач на сегодня.
private struct HomeLeftColumn: View {
    @ObservedObject var media: MediaController
    @ObservedObject var tasks: TasksStore
    @ObservedObject var calendar: CalendarService
    var openMusic: () -> Void

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            VStack(alignment: .center, spacing: 2) {
                // Без музыки время стоит по центру своей колонки, с музыкой — наверху, над мини-плеером.
                if !media.hasTrack { Spacer(minLength: 0) }
                // Без анимированной смены цифр: так время всегда остаётся идеально чётким.
                Text(ctx.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(ctx.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Loc.locale)).capitalizedFirst)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                if media.hasTrack {
                    Spacer(minLength: 6)
                    nowPlayingChip
                } else {
                    daySummary(now: ctx.date)
                        .padding(.top, 8)
                    Spacer(minLength: 0)
                }
            }
            .padding(.top, 0)
            .padding(.bottom, 2)
            .animation(.spring(response: 0.45, dampingFraction: 0.9), value: media.hasTrack)
        }
    }

    /// «3 задачи · 17:00 Спортзал» — ближайшая задача или встреча на сегодня.
    private func daySummary(now: Date) -> some View {
        let open = tasks.tasks(forOffset: 0).filter { !$0.done }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let nowText = f.string(from: now)
        var next: (time: String, title: String)? = open
            .compactMap { task in task.time.map { ($0, task.text) } }
            .first { $0.0 >= nowText }
        if let event = calendar.upcoming.first(where: { $0.start > now && Calendar.current.isDateInToday($0.start) }) {
            let time = f.string(from: event.start)
            if next == nil || time < next!.time { next = (time, event.title) }
        }
        let count = open.count
        let head = count == 0 ? L("Задач на сегодня нет")
            : "\(count) " + Loc.plural(count, "задача", "задачи", "задач", en: "task", enPlural: "tasks")
        return HStack(spacing: 4) {
            Text(head)
            if let next {
                Text("·")
                Text(next.time).monospacedDigit().foregroundStyle(.white.opacity(0.8))
                Text(next.title).lineLimit(1)
            }
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(.white.opacity(0.5))
        .lineLimit(1)
        .frame(maxWidth: 196)
    }


    @ViewBuilder
    private var nowPlayingChip: some View {
        if media.hasTrack {
            Button(action: openMusic) {
                HStack(spacing: 10) {
                    ArtworkView(image: media.artwork, accent: media.accent, cornerRadius: 8)
                        .frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(media.title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(media.artist)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    EqualizerView(isPlaying: media.isPlaying, color: .white)
                        .frame(width: 15, height: 12)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white.opacity(0.07)))
            }
            .buttonStyle(PressableStyle())
            .transition(.blurFade)
        }
    }
}

/// Кольцо заряда: при появлении заполняется от нуля.
struct BatteryRing: View {
    var percent: Int
    var charging: Bool
    var symbol: String
    var size: CGFloat = 46
    @ViewState private var progress: Double = 0

    private var color: Color {
        if charging { return .green }
        if percent <= 20 { return .red }
        if percent <= 40 { return .orange }
        return .green
    }

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.1), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color.gradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: charging ? "bolt.fill" : symbol)
                .font(.system(size: size * 0.33, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .symbolEffect(.pulse, isActive: charging)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.85).delay(0.15)) {
                progress = Double(percent) / 100
            }
        }
        .onChange(of: percent) { _, value in
            withAnimation(.spring(response: 0.8)) { progress = Double(value) / 100 }
        }
    }
}

private struct WeatherCard: View {
    @ObservedObject var service: WeatherService

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let w = service.weather {
                HStack(alignment: .top) {
                    Text("\(w.temperature)°")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText(value: Double(w.temperature)))
                    Spacer(minLength: 6)
                    // Пульс крутит Core Animation, а не SwiftUI: иначе остров перерисовывался бы каждый кадр.
                    PulsingSymbol(name: w.symbol, pointSize: 22, multicolor: true, speed: 0.3)
                }
                Text(w.summary)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text("↑\(w.high)°  ↓\(w.low)°" + (w.city.map { "  ·  \($0)" } ?? ""))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            } else {
                ProgressView().controlSize(.small)
                Text(L("Погода загружается…"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 132, height: 104, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture {
            // Пока погода определена по IP, нажатие предлагает точную геолокацию; потом — открывает прогноз.
            if service.canAskForPreciseLocation { service.askForPreciseLocation() }
            else if let w = service.weather { NSWorkspace.shared.open(w.forecastURL) }
        }
        .help(service.canAskForPreciseLocation ? L("Нажмите, чтобы уточнить город по геолокации")
                                                : L("Открыть прогноз погоды на несколько дней"))
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)))
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}


/// Одна карточка заряда, которую можно листать: MacBook ↔ наушники ↔ мышь и другие устройства ↔ iPhone.
private struct BatteryCarousel: View {
    var mac: BatteryInfo?
    var headphones: [DeviceBattery]
    var accessories: [DeviceBattery]
    var phone: PhoneBattery?
    @ViewState private var page: Int? = SnapshotFlags.batteryPage

    private enum Page { case mac, headphones(DeviceBattery), accessory(DeviceBattery), phone(PhoneBattery) }

    private var pages: [Page] {
        var result: [Page] = [.mac]
        result += headphones.map(Page.headphones)
        result += accessories.map(Page.accessory)
        if let phone { result.append(.phone(phone)) }
        return result
    }

    var body: some View {
        let pages = pages
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(pages.indices, id: \.self) { i in
                        pageView(pages[i])
                            .containerRelativeFrame(.horizontal)
                            // Страница при листании мягко гаснет и чуть уменьшается — без рывков.
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .opacity(1 - abs(phase.value) * 0.8)
                                    .scaleEffect(1 - abs(phase.value) * 0.06)
                                    .offset(x: phase.value * -18)
                            }
                            .id(i)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $page)

            if pages.count > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        Capsule()
                            .fill(.white.opacity((page ?? 0) == i ? 0.9 : 0.25))
                            .frame(width: (page ?? 0) == i ? 14 : 5, height: 5)
                            .contentShape(Rectangle().inset(by: -4))
                            .onTapGesture { withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { page = i } }
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: page)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 104)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.06)))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func pageView(_ page: Page) -> some View {
        switch page {
        case .mac: macPage
        case .headphones(let device): headphonesPage(device)
        case .accessory(let device): accessoryPage(device)
        case .phone(let phone): phonePage(phone)
        }
    }

    private var macPage: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                MacBookArt(width: 58)
                if mac?.charging == true {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.green)
                        .offset(x: 5, y: -6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 60)
            info(title: "MacBook", percent: mac?.percent, charging: mac?.charging == true,
                 note: mac?.charging == true ? L("Заряжается") : nil)
        }
        .padding(.horizontal, 14)
        .animation(.smooth(duration: 0.4), value: mac?.charging)
    }

    private func accessoryPage(_ device: DeviceBattery) -> some View {
        HStack(spacing: 12) {
            Image(systemName: device.symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.75)], startPoint: .top, endPoint: .bottom))
                .frame(width: 60)
            info(title: device.name.replacingOccurrences(of: #"\s*\(.*\)\s*$"#, with: "", options: .regularExpression),
                 percent: device.primaryLevel?.percent, note: nil)
        }
        .padding(.horizontal, 14)
    }

    private func phonePage(_ phone: PhoneBattery) -> some View {
        let minutes = Int(Date().timeIntervalSince(phone.updated) / 60)
        let age = minutes < 1 ? L("только что") : minutes < 60 ? L("%@ мин назад", "\(minutes)") : L("%@ ч назад", "\(minutes / 60)")
        return HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "iphone")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.75)], startPoint: .top, endPoint: .bottom))
                if phone.charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.green)
                        .offset(x: 8, y: -4)
                }
            }
            .frame(width: 60)
            info(title: "iPhone", percent: phone.percent, charging: phone.charging, note: phone.charging ? L("Заряжается · %@", "\(age)") : age)
        }
        .padding(.horizontal, 14)
    }

    private func headphonesPage(_ device: DeviceBattery) -> some View {
        let name = device.name.replacingOccurrences(of: #"\s*\(.*\)\s*$"#, with: "", options: .regularExpression)
        let left = device.levels.first { $0.label == "Левый" }
        let right = device.levels.first { $0.label == "Правый" }
        let casing = device.levels.first { $0.label == "Кейс" }
        let pair = [left, right].compactMap { $0 }
        return HStack(spacing: 12) {
            headphonesArt(device)
                .frame(width: 60)
            if !pair.isEmpty || casing != nil {
                // Как у MacBook: название и крупные проценты с батарейкой — отдельно наушники, отдельно кейс.
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    if let bud = pair.min(by: { $0.percent < $1.percent }) {
                        let help = left != nil && right != nil
                            ? L("Левый %@%% · правый %@%%", "\(left!.percent)", "\(right!.percent)") : L("Наушники")
                        levelRow(bud.percent, charging: pair.contains(where: \.charging), symbol: device.symbol)
                            .help(help)
                    }
                    if let casing {
                        levelRow(casing.percent, charging: casing.charging,
                                 symbol: casing.symbol.isEmpty ? "airpodspro.chargingcase.wireless.fill" : casing.symbol)
                            .help(L("Кейс"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // AirPods Max и прочие наушники: один процент, а если система его не сообщила — просто «Подключены».
                let level = device.primaryLevel
                info(title: name, percent: level?.percent, note: level == nil ? L("Подключены") : nil,
                     monochrome: true)
            }
        }
        .padding(.horizontal, 14)
    }

    /// Строка заряда: значок (наушники или кейс), крупный процент и батарейка — как у MacBook.
    private func levelRow(_ percent: Int, charging: Bool, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 18)
            Text("\(percent)%")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText(value: Double(percent)))
                .animation(.smooth(duration: 0.6), value: percent)
                .frame(minWidth: 50, alignment: .leading)
            BatteryGlyph(percent: percent, charging: charging, width: 24, monochrome: true)
        }
    }

    /// Для AirPods — только кейс; для остальных наушников — их рисунок (AirPods Max — в цвете Midnight).
    private func headphonesArt(_ device: DeviceBattery) -> some View {
        DeviceArt(kind: DeviceArt.Kind(device: device), open: 0, width: 56)
    }

    private func info(title: String, percent: Int?, charging: Bool = false, note: String?,
                      monochrome: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            if let percent {
                HStack(spacing: 6) {
                    Text("\(percent)%")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(value: Double(percent)))
                        .animation(.smooth(duration: 0.6), value: percent)
                    BatteryGlyph(percent: percent, charging: charging, width: 28, monochrome: monochrome)
                }
            }
            if let note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
