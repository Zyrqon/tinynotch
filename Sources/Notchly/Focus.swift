import Foundation

/// Фокус-таймер по технике «Помидор»: 25 минут работы, 5 минут перерыва,
/// после каждого четвёртого подхода — длинный перерыв 15 минут.
final class FocusTimer: ObservableObject {
    enum Phase: Equatable {
        case idle, work, shortBreak, longBreak

        var isBreak: Bool { self == .shortBreak || self == .longBreak }

        var title: String {
            switch self {
            case .idle: return L("Фокус")
            case .work: return L("Фокус")
            case .shortBreak: return L("Перерыв")
            case .longBreak: return L("Длинный перерыв")
            }
        }

        var duration: TimeInterval {
            switch self {
            case .idle, .work: return 25 * 60
            case .shortBreak: return 5 * 60
            case .longBreak: return 15 * 60
            }
        }
    }

    /// Событие для острова: закончилась работа или перерыв.
    enum Transition: Equatable {
        case workFinished(next: Phase, heldNotifications: Int)
        case breakFinished
    }

    static let roundsBeforeLongBreak = 4

    @Published private(set) var phase: Phase = .idle
    /// Когда закончится текущая фаза (если не на паузе).
    @Published private(set) var endDate: Date?
    /// Сколько осталось, пока таймер на паузе.
    @Published private(set) var pausedRemaining: TimeInterval?
    /// Завершённые сегодня подходы.
    @Published private(set) var completedToday = 0
    @Published private(set) var taskTitle: String?
    private(set) var taskID: UUID?

    /// Уведомления приложений, пришедшие во время работы: не отвлекаем, показываем итогом.
    private(set) var heldNotifications = 0
    var onTransition: ((Transition) -> Void)?

    private var timer: Timer?
    private var countedDay = Calendar.current.startOfDay(for: Date())

    var isActive: Bool { phase != .idle }
    var isPaused: Bool { pausedRemaining != nil }
    /// Идёт работа (не перерыв и не пауза) — в это время уведомления не показываются.
    var isFocusing: Bool { phase == .work && !isPaused }

    func remaining(at now: Date = Date()) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endDate else { return phase.duration }
        return max(0, endDate.timeIntervalSince(now))
    }

    /// Доля прошедшего времени фазы (0…1) — для кольца.
    func progress(at now: Date = Date()) -> Double {
        guard isActive else { return 0 }
        return 1 - remaining(at: now) / phase.duration
    }

    /// На сколько прогресс вырастет за секунду (0 — на паузе): по нему дугу ведёт Core Animation.
    func progressRate(at now: Date = Date()) -> Double {
        max(0, progress(at: now.addingTimeInterval(1)) - progress(at: now))
    }

    func start(taskID: UUID? = nil, title: String? = nil) {
        self.taskID = taskID
        taskTitle = title
        heldNotifications = 0
        begin(.work)
    }

    func togglePause() {
        guard isActive else { return }
        if let left = pausedRemaining {
            pausedRemaining = nil
            endDate = Date().addingTimeInterval(left)
            startTicking()
        } else {
            pausedRemaining = remaining()
            endDate = nil
            timer?.invalidate()
        }
    }

    /// Пропустить текущую фазу: работа → перерыв, перерыв → новый подход.
    func skip() {
        switch phase {
        case .idle: return
        case .work: finishWork(counted: false)
        case .shortBreak, .longBreak: begin(.work)
        }
    }

    func stop() {
        timer?.invalidate()
        phase = .idle
        endDate = nil
        pausedRemaining = nil
        taskID = nil
        taskTitle = nil
        heldNotifications = 0
    }

    func holdNotification() { heldNotifications += 1 }

    /// Для снапшотов.
    func debugSet(phase: Phase, remaining: TimeInterval, title: String?, completed: Int) {
        timer?.invalidate()
        self.phase = phase
        taskTitle = title
        completedToday = completed
        pausedRemaining = nil
        endDate = Date().addingTimeInterval(remaining)
    }

    private func begin(_ next: Phase) {
        phase = next
        pausedRemaining = nil
        endDate = Date().addingTimeInterval(next.duration)
        startTicking()
    }

    private func startTicking() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard let endDate, Date() >= endDate else { return }
        switch phase {
        case .idle: timer?.invalidate()
        case .work: finishWork(counted: true)
        case .shortBreak, .longBreak:
            // После перерыва ждём, пока человек сам начнёт следующий подход.
            timer?.invalidate()
            phase = .idle
            self.endDate = nil
            onTransition?(.breakFinished)
        }
    }

    private func finishWork(counted: Bool) {
        let today = Calendar.current.startOfDay(for: Date())
        if today != countedDay { countedDay = today; completedToday = 0 }
        if counted { completedToday += 1 }
        let next: Phase = counted && completedToday % Self.roundsBeforeLongBreak == 0 ? .longBreak : .shortBreak
        let held = heldNotifications
        heldNotifications = 0
        begin(next)
        onTransition?(.workFinished(next: next, heldNotifications: held))
    }
}

extension TimeInterval {
    /// «24:05».
    var clock: String {
        let total = Int(self.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// «1 мин 30 с», «10 мин», «45 с», «1 ч 5 мин».
    var durationText: String {
        let total = Int(self.rounded())
        let h = total / 3600, m = total % 3600 / 60, s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append(L("%@ ч", "\(h)")) }
        if m > 0 { parts.append(L("%@ мин", "\(m)")) }
        if s > 0 && h == 0 { parts.append(L("%@ с", "\(s)")) }
        return parts.isEmpty ? L("0 с") : parts.joined(separator: " ")
    }
}
