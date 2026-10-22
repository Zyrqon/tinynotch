import AppKit
import EventKit

/// Напоминание, которое показывается «каплей»: задача со временем или событие календаря.
struct Reminder: Equatable {
    enum Source: Equatable { case task, calendar }
    var id: String
    var title: String
    var date: Date
    var minutesBefore: Int
    var source: Source
    /// Ссылка на созвон или на урок из описания задачи.
    var link: URL?
    /// Задача, к которой относится напоминание (для кнопки «Готово»).
    var taskID: UUID?

    /// «Через 10 мин · 17:00» или «Начинается сейчас · 17:00».
    func subtitle(now: Date = Date()) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded())
        let time = date.formatted(date: .omitted, time: .shortened)
        if minutes >= 1 { return L("Через %@ мин · %@", "\(minutes)", "\(time)") }
        return minutes > -2 ? L("Начинается сейчас · %@", "\(time)") : L("Началось в %@", "\(time)")
    }
}

/// Тихий приятный сигнал: короткий «бульк» и следом мягкий колокольчик.
/// Синтезируется один раз при первом использовании, без файлов в бандле.
enum SoftChime {
    private static let sound: NSSound? = NSSound(data: makeWAV())

    static var isAvailable: Bool { sound != nil }

    static func play(times: Int = 1) {
        guard let sound else { return }
        sound.stop()
        sound.volume = 0.35
        sound.play()
        // Будильник и таймер звучат несколько раз подряд, с паузами.
        for i in 1..<max(times, 1) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4 * Double(i)) {
                sound.stop()
                sound.play()
            }
        }
    }

    private static func makeWAV() -> Data {
        let rate = 44_100.0
        let count = Int(rate * 0.95)
        var samples = [Double](repeating: 0, count: count)

        // «Бульк»: пузырёк — тон быстро скользит вверх, огибающая — полусинус.
        let bubbleLength = 0.075
        var phase = 0.0
        for i in 0..<Int(rate * bubbleLength) {
            let t = Double(i) / rate
            let progress = t / bubbleLength
            phase += 2 * .pi * (420 + 560 * progress * progress) / rate
            samples[i] += sin(phase) * sin(.pi * progress) * 0.45
        }

        // «Дзынь»: мягкий колокольчик (ми и си шестой октавы) с плавным затуханием.
        let start = Int(rate * 0.06)
        let partials: [(freq: Double, amp: Double, decay: Double)] = [
            (1318.5, 0.34, 5.0), (1975.5, 0.12, 6.5), (2637.0, 0.06, 9.0)]
        for i in start..<count {
            let t = Double(i - start) / rate
            let attack = min(1, t / 0.006)
            for p in partials {
                samples[i] += sin(2 * .pi * p.freq * t) * p.amp * exp(-t * p.decay) * attack
            }
        }

        // Мягкое затухание в самом конце, чтобы не было щелчка.
        let fade = Int(rate * 0.05)
        for i in (count - fade)..<count { samples[i] *= Double(count - i) / Double(fade) }

        let peak = samples.map(abs).max() ?? 1
        var pcm = Data(capacity: count * 2)
        for s in samples {
            var v = Int16(max(-1, min(1, s / peak * 0.8)) * Double(Int16.max)).littleEndian
            withUnsafeBytes(of: &v) { pcm.append(contentsOf: $0) }
        }

        var wav = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { wav.append(contentsOf: $0) }
        }
        wav.append("RIFF".data(using: .ascii)!)
        append(UInt32(36 + pcm.count))
        wav.append("WAVEfmt ".data(using: .ascii)!)
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(rate)); append(UInt32(rate * 2)); append(UInt16(2)); append(UInt16(16))
        wav.append("data".data(using: .ascii)!)
        append(UInt32(pcm.count))
        wav.append(pcm)
        return wav
    }
}

/// Ближайшие события календаря. Доступ спрашивается один раз; без ключа в Info.plist ничего не делаем.
final class CalendarService: ObservableObject {
    struct Event: Equatable {
        var id: String
        var title: String
        var start: Date
        var link: URL?
    }

    @Published private(set) var upcoming: [Event] = []
    private let store = EKEventStore()
    private var timer: Timer?

    private var started = false
    private var hasUsageKey: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") != nil
    }

    /// При запуске ничего не спрашиваем: подключаемся, только если доступ уже выдан.
    func start() {
        guard hasUsageKey, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        begin()
    }

    /// Спросить доступ к календарю — когда он действительно нужен (первое открытие «Задач»).
    func requestIfNeeded() {
        guard hasUsageKey, !started, EKEventStore.authorizationStatus(for: .event) == .notDetermined else { return }
        store.requestFullAccessToEvents { [weak self] granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { self?.begin() }
        }
    }

    private func begin() {
        guard !started else { return }
        started = true
        reload()
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.reload()
        }
        let t = Timer(timeInterval: 300, repeats: true) { [weak self] _ in self?.reload() }
        t.tolerance = 30
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func reload() {
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-60),
                                                 end: now.addingTimeInterval(24 * 3600), calendars: nil)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled }
            .map { Event(id: $0.calendarItemIdentifier + "@\(Int($0.startDate.timeIntervalSince1970))",
                         title: $0.title ?? L("Событие"), start: $0.startDate, link: Self.meetingLink(in: $0)) }
            .sorted { $0.start < $1.start }
        if events != upcoming { upcoming = events }
    }

    /// Ссылка на созвон: сначала поле URL, потом Zoom / Meet / Teams / FaceTime в месте или заметках.
    private static func meetingLink(in event: EKEvent) -> URL? {
        let text = [event.location, event.notes].compactMap { $0 }.joined(separator: "\n")
        let links = TaskItem.links(in: text)
        let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "facetime.apple.com", "telemost.yandex"]
        let eventURL = event.url.flatMap { TaskItem.isSafeLink($0) ? $0 : nil }
        return links.first { url in hosts.contains { url.host?.contains($0) == true } } ?? eventURL ?? links.first
    }
}

/// Напоминает о задачах со временем и о событиях календаря за 10 и за 5 минут и в момент начала.
/// Время берётся с часов Mac; уже показанные напоминания запоминаются, чтобы не повторяться.
final class ReminderCenter {
    static let offsets = [10, 5, 0]

    var onFire: ((Reminder) -> Void)?
    let calendar = CalendarService()
    private let tasks: TasksStore
    private var timer: Timer?
    private var fired: [String: Date]
    /// Отложенные напоминания: покажутся снова в указанное время.
    private var snoozed: [(reminder: Reminder, at: Date)] = []
    private let firedKey = "reminders.fired"

    init(tasks: TasksStore) {
        self.tasks = tasks
        fired = UserDefaults.standard.dictionary(forKey: firedKey) as? [String: Date] ?? [:]
    }

    func start() {
        calendar.start()
        let t = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.check() }
        t.tolerance = 2
        RunLoop.main.add(t, forMode: .common)
        timer = t
        // После сна и при переводе часов проверяем сразу.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in self?.check() }
        NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil,
                                               queue: .main) { [weak self] _ in self?.check() }
        check()
    }

    /// Задачи со временем на сегодня и на завтра (невыполненные).
    private func taskCandidates(now: Date) -> [Reminder] {
        let cal = Calendar.current
        // Сегодняшние (включая перенесённые со вчера) и завтрашние: без завтрашних задача на 00:05
        // не получила бы напоминаний «за 10» и «за 5 минут», они приходятся на вчерашний вечер.
        // Дальние сроки отсекает окно в check().
        return [0, 1].flatMap { offset -> [Reminder] in
            guard let day = cal.date(byAdding: .day, value: offset, to: now) else { return [] }
            return tasks.tasks(forOffset: offset).compactMap { task in
                guard !task.done, let time = task.time else { return nil }
                let parts = time.split(separator: ":").compactMap { Int($0) }
                guard parts.count == 2,
                      let date = cal.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day) else { return nil }
                return Reminder(id: "task-\(task.id.uuidString)-\(time)", title: task.text, date: date,
                                minutesBefore: 0, source: .task, link: task.links.first, taskID: task.id)
            }
        }
    }

    /// «Отложить»: напомнить ещё раз через 5 минут.
    func snooze(_ reminder: Reminder, minutes: Double = 5) {
        snoozed.removeAll { $0.reminder.id == reminder.id }
        snoozed.append((reminder, Date().addingTimeInterval(minutes * 60)))
    }

    /// `now` подменяется только в самотесте (--reminders-selftest).
    func check(now: Date = Date()) {
        let due = snoozed.filter { $0.at <= now }
        snoozed.removeAll { $0.at <= now }
        for item in due {
            // Задачу могли уже выполнить, пока напоминание было отложено.
            if let id = item.reminder.taskID, tasks.items.first(where: { $0.id == id })?.done != false { continue }
            onFire?(item.reminder)
        }
        let candidates = taskCandidates(now: now) + calendar.upcoming.map {
            Reminder(id: "cal-\($0.id)", title: $0.title, date: $0.start, minutesBefore: 0, source: .calendar, link: $0.link)
        }
        let day = Self.dayStamp(now)
        var changed = false
        for item in candidates {
            // Если сразу подходят оба срока (задачу создали за 4 минуты), показываем только ближайший.
            for offset in Self.offsets.sorted() {
                let moment = item.date.addingTimeInterval(-Double(offset) * 60)
                // Окно в 2 минуты: после долгого сна старые напоминания не всплывают.
                guard now >= moment, now < moment.addingTimeInterval(120) else { continue }
                let key = "\(item.id)|\(day)|\(offset)"
                guard fired[key] == nil else { break }
                fired[key] = now
                changed = true
                var reminder = item
                reminder.minutesBefore = offset
                onFire?(reminder)
                break
            }
        }
        let cutoff = now.addingTimeInterval(-2 * 86_400)
        let pruned = fired.filter { $0.value > cutoff }
        if pruned.count != fired.count { fired = pruned; changed = true }
        if changed { UserDefaults.standard.set(fired, forKey: firedKey) }
    }

    private static func dayStamp(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}
