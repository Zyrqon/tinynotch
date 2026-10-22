import Foundation

/// Обычный таймер обратного отсчёта.
final class CountdownTimer: ObservableObject {
    /// Быстрый выбор в минутах.
    static let presets: [Int] = [1, 5, 10, 15, 30, 60]
    static let maxSeconds = 3 * 3600

    /// Выбранная длительность в секундах (1 с … 3 ч). Меняется через setSeconds / step —
    /// присваивание в didSet у @Published уходило бы в бесконечную рекурсию.
    @Published private(set) var seconds = 600

    var minutes: Int { seconds / 60 }
    func setSeconds(_ value: Int) { seconds = min(max(value, 1), Self.maxSeconds) }
    func setMinutes(_ value: Int) { setSeconds(value * 60) }
    /// Шаг в секундах (кнопки ± и стрелки).
    func step(seconds delta: Int) { setSeconds(seconds + delta) }
    @Published private(set) var endDate: Date?
    @Published private(set) var pausedRemaining: TimeInterval?
    /// Длительность запущенного отсчёта (для кольца и карточки).
    @Published private(set) var runningDuration: TimeInterval = 0

    var onFinish: ((TimeInterval) -> Void)?
    private var timer: Timer?

    var isActive: Bool { endDate != nil || pausedRemaining != nil }
    var isPaused: Bool { pausedRemaining != nil }

    func remaining(at now: Date = Date()) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endDate else { return TimeInterval(seconds) }
        return max(0, endDate.timeIntervalSince(now))
    }

    func progress(at now: Date = Date()) -> Double {
        guard isActive, runningDuration > 0 else { return 0 }
        return 1 - remaining(at: now) / runningDuration
    }

    /// На сколько прогресс вырастет за секунду (0 — на паузе): по нему дугу ведёт Core Animation.
    func progressRate(at now: Date = Date()) -> Double {
        max(0, progress(at: now.addingTimeInterval(1)) - progress(at: now))
    }

    func start(seconds: Int? = nil) {
        if let seconds { setSeconds(seconds) }
        runningDuration = TimeInterval(self.seconds)
        pausedRemaining = nil
        endDate = Date().addingTimeInterval(runningDuration)
        tickEverySecond()
    }

    func togglePause() {
        if let left = pausedRemaining {
            pausedRemaining = nil
            endDate = Date().addingTimeInterval(left)
            tickEverySecond()
        } else if isActive {
            pausedRemaining = remaining()
            endDate = nil
            timer?.invalidate()
        }
    }

    func reset() {
        timer?.invalidate()
        endDate = nil
        pausedRemaining = nil
    }

    /// Для снапшотов.
    func debugSet(minutes: Int, remaining: TimeInterval) {
        timer?.invalidate()
        setMinutes(minutes)
        runningDuration = TimeInterval(minutes * 60)
        pausedRemaining = nil
        endDate = Date().addingTimeInterval(remaining)
    }

    private func tickEverySecond() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard let endDate, Date() >= endDate else { return }
        let duration = runningDuration
        reset()
        onFinish?(duration)
    }
}

/// Будильники: время «ЧЧ:ММ», срабатывают один раз и выключаются.
struct Alarm: Identifiable, Codable, Equatable {
    var id = UUID()
    var time: String
    var enabled = true
    /// Будильник из «+5 мин»: после срабатывания удаляется, а не остаётся в списке выключенным.
    var isSnooze: Bool? = nil
}

final class AlarmStore: ObservableObject {
    @Published private(set) var alarms: [Alarm] = []
    var onFire: ((Alarm) -> Void)?

    private let persistent: Bool
    private var timer: Timer?
    private let key = "alarms"

    init(persistent: Bool = true) {
        self.persistent = persistent
        if persistent, let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Alarm].self, from: data) {
            alarms = saved
        }
    }

    func start() {
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.check() }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
        check()
    }

    func add(_ time: String, snooze: Bool = false) {
        if let i = alarms.firstIndex(where: { $0.time == time }) {
            alarms[i].enabled = true
        } else {
            alarms.append(Alarm(time: time, isSnooze: snooze ? true : nil))
            alarms.sort { $0.time < $1.time }
        }
        persist()
    }

    func toggle(_ id: UUID) {
        guard let i = alarms.firstIndex(where: { $0.id == id }) else { return }
        alarms[i].enabled.toggle()
        persist()
    }

    func remove(_ id: UUID) {
        alarms.removeAll { $0.id == id }
        persist()
    }

    /// «+5 мин»: одноразовый будильник через 5 минут.
    func snooze(minutes: Int = 5) {
        add(Self.format(Date().addingTimeInterval(TimeInterval(minutes * 60))), snooze: true)
    }

    /// Ближайший включённый будильник — для подписи.
    var next: Alarm? {
        let now = Self.format(Date())
        let enabled = alarms.filter(\.enabled)
        return enabled.first { $0.time > now } ?? enabled.first
    }

    func debugSet(_ alarms: [Alarm]) { self.alarms = alarms }

    static func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func check() {
        let now = Self.format(Date())
        for alarm in alarms where alarm.enabled && alarm.time == now {
            if alarm.isSnooze == true {
                alarms.removeAll { $0.id == alarm.id }
            } else if let i = alarms.firstIndex(where: { $0.id == alarm.id }) {
                alarms[i].enabled = false
            }
            persist()
            onFire?(alarm)
        }
    }

    private func persist() {
        guard persistent, let data = try? JSONEncoder().encode(alarms) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
