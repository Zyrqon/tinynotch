import SwiftUI
import AppKit
import UserNotifications

// MARK: - 080 Помодоро

struct PomodoroTool: View {
    @ViewState private var secondsLeft = 25 * 60
    @ViewState private var isRunning = false
    @ViewState private var isBreak = false
    @ViewState private var sessions = Int(ToolStorage.load("pomodoro.count") ?? "0") ?? 0
    @ViewState private var timer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(timeString).font(.system(size: 44, design: .monospaced).weight(.semibold))
                .frame(maxWidth: .infinity)
            Text(isBreak ? L("Перерыв") : L("Фокус 25 минут"))
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                Button(isRunning ? L("Пауза") : L("Старт")) { toggle() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button(L("Сброс")) { reset() }.buttonStyle(.bordered).controlSize(.small)
            }.frame(maxWidth: .infinity)
            Text(L("Помодоро сделано: ") + "\(sessions)").font(.caption2).foregroundStyle(.secondary)
        }
        .onDisappear { timer?.invalidate(); timer = nil }
    }

    private var timeString: String {
        String(format: "%02d:%02d", secondsLeft / 60, secondsLeft % 60)
    }

    private func toggle() {
        if isRunning {
            timer?.invalidate()
            timer = nil
            isRunning = false
            return
        }
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if secondsLeft > 1 {
                secondsLeft -= 1
            } else {
                timer?.invalidate()
                timer = nil
                isRunning = false
                if !isBreak {
                    sessions += 1
                    ToolStorage.save("pomodoro.count", String(sessions))
                    isBreak = true
                    secondsLeft = 5 * 60
                } else {
                    isBreak = false
                    secondsLeft = 25 * 60
                }
                NSSound.beep()
            }
        }
    }

    private func reset() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        isBreak = false
        secondsLeft = 25 * 60
    }
}

// MARK: - 081 Метроном

struct MetronomeTool: View {
    @ViewState private var bpm: Double = 100
    @ViewState private var running = false
    @ViewState private var timer: Timer?
    @ViewState private var beat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("BPM"))
                Slider(value: $bpm, in: 40...240, step: 1)
                Text("\(Int(bpm))").font(.system(.caption, design: .monospaced))
            }
            Button(running ? L("Стоп") : L("Играть")) { toggle() }
                .buttonStyle(.bordered).controlSize(.small)
            Circle()
                .fill(beat % 4 == 0 ? Color.red : Color.secondary.opacity(0.3))
                .frame(width: 18, height: 18)
                .frame(maxWidth: .infinity)
        }
        .onDisappear { timer?.invalidate(); timer = nil }
    }

    private func toggle() {
        if running {
            timer?.invalidate()
            timer = nil
            running = false
            return
        }
        running = true
        restart()
    }

    private func restart() {
        timer?.invalidate()
        let interval = 60.0 / bpm
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            beat += 1
            NSSound.beep()
        }
    }
}

// MARK: - 082 Секундомер

struct StopwatchTool: View {
    @ViewState private var seconds: Double = 0
    @ViewState private var running = false
    @ViewState private var laps: [String] = []
    @ViewState private var timer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(format: "%.1f с", seconds))
                .font(.system(size: 40, design: .monospaced).weight(.semibold))
                .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                Button(running ? L("Стоп") : L("Старт")) { toggle() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button(L("Круг")) { laps.insert(String(format: "%.1f с", seconds), at: 0) }
                    .buttonStyle(.bordered).controlSize(.small).disabled(!running)
                Button(L("Сброс")) { reset() }.buttonStyle(.bordered).controlSize(.small)
            }.frame(maxWidth: .infinity)
            ForEach(Array(laps.enumerated()), id: \.offset) { pair in
                Text("\(pair.offset + 1). \(pair.element)").font(.system(.caption, design: .monospaced))
            }
        }
        .onDisappear { timer?.invalidate(); timer = nil }
    }

    private func toggle() {
        if running {
            timer?.invalidate()
            timer = nil
            running = false
            return
        }
        running = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in seconds += 0.1 }
    }

    private func reset() {
        timer?.invalidate()
        timer = nil
        running = false
        seconds = 0
        laps = []
    }
}

// MARK: - 083 Отсчёт до даты

struct CountdownDateTool: View {
    @ViewState private var target = Date().addingTimeInterval(86400 * 7)

    private var remaining: String {
        let interval = max(target.timeIntervalSinceNow, 0)
        let days = Int(interval / 86400)
        let hours = Int(interval.truncatingRemainder(dividingBy: 86400) / 3600)
        let minutes = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        return "\(days) дн. \(hours) ч. \(minutes) мин."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker(L("До какой даты"), selection: $target).labelsHidden()
            Text(remaining).font(.title2.weight(.semibold)).textSelection(.enabled)
        }
    }
}

// MARK: - 086 Напоминание «вернись к задаче»

enum ToolNotifications {
    static func send(title: String, body: String, inSeconds seconds: Double) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(seconds, 1), repeats: false)
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger))
    }
}

struct BackToTaskTool: View {
    @ViewState private var task = ""
    @ViewState private var minutes: Double = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L("К какой задаче вернуться"), text: $task).textFieldStyle(.roundedBorder)
            HStack {
                Text(L("Через"))
                Slider(value: $minutes, in: 5...120, step: 5)
                Text("\(Int(minutes)) мин.").font(.system(.caption, design: .monospaced))
            }
            Button(L("Напомнить")) {
                ToolNotifications.send(title: L("Вернись к задаче"), body: task.isEmpty ? L("Задача ждёт") : task, inSeconds: minutes * 60)
            }.buttonStyle(.bordered).controlSize(.small)
        }
    }
}

// MARK: - 087 Стретчинг

struct StretchReminderTool: View {
    @ViewState private var enabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(L("Напоминать каждый час"), isOn: Binding(
                get: { enabled },
                set: { newValue in
                    enabled = newValue
                    if newValue { schedule() }
                }
            )).toggleStyle(.switch)
            Text(L("Повторяющееся уведомление: встать и размяться"))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func schedule() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = L("Пора размяться")
        content.body = L("Встань, потянись, посреди работы 30 секунд")
        content.sound = .default
        var dateComponents = DateComponents()
        dateComponents.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        center.add(UNNotificationRequest(identifier: "stretch-hourly", content: content, trigger: trigger))
    }
}

// MARK: - 088 Счётчик воды

struct WaterCounterTool: View {
    @ViewState private var glasses: Int = {
        let key = "water." + DateFormatter().dayKey()
        return Int(ToolStorage.load(key) ?? "0") ?? 0
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button(L("+ стакан")) {
                    glasses += 1
                    save()
                }.buttonStyle(.borderedProminent).controlSize(.small)
                Button(L("−")) {
                    glasses = max(glasses - 1, 0)
                    save()
                }.buttonStyle(.bordered).controlSize(.small)
                Spacer()
            }
            Text(L("Сегодня стаканов: ") + "\(glasses)")
                .font(.headline)
            Text(L("Норма примерно 8")).font(.caption2).foregroundStyle(.secondary)
            ProgressView(value: Double(min(glasses, 8)), total: 8).progressViewStyle(.linear)
        }
    }

    private func save() {
        ToolStorage.save("water." + DateFormatter().dayKey(), String(glasses))
    }
}

private extension DateFormatter {
    func dayKey() -> String {
        dateFormat = "yyyy-MM-dd"
        return string(from: Date())
    }
}

// MARK: - 089 Дыхание 4-7-8

struct BreatheTool: View {
    @ViewState private var phase = 0
    @ViewState private var secondsLeft = 4
    @ViewState private var running = false
    @ViewState private var timer: Timer?
    private let phases = ["Вдох 4 с", "Задержка 7 с", "Выдох 8 с"]
    private let lengths = [4, 7, 8]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(running ? 0.25 : 0.1))
                    .frame(width: running ? 120 : 90, height: running ? 120 : 90)
                    .animation(.easeInOut(duration: 1), value: running)
                Text(running ? "\(secondsLeft)" : "4-7-8")
                    .font(.title2.weight(.semibold))
            }.frame(maxWidth: .infinity)
            if running {
                Text(phases[phase]).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
            Button(running ? L("Стоп") : L("Начать")) { toggle() }
                .buttonStyle(.bordered).controlSize(.small).frame(maxWidth: .infinity)
        }
        .onDisappear { timer?.invalidate(); timer = nil }
    }

    private func toggle() {
        if running {
            timer?.invalidate()
            timer = nil
            running = false
            phase = 0
            secondsLeft = 4
            return
        }
        running = true
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in tick() }
    }

    private func tick() {
        if secondsLeft > 1 {
            secondsLeft -= 1
        } else {
            phase = (phase + 1) % phases.count
            secondsLeft = lengths[phase]
        }
    }
}

// MARK: - 090/091 Цитата и шутка дня

private let dayQuotes: [String] = [
    "Простота — высшая степень изощрённости.",
    "Сделать сегодня чуть лучше, чем вчера.",
    "Кто спрашивает — не заблудится.",
    "Лучшее время начать — вчера, второе лучшее — сейчас.",
    "Мелочи складываются в большое.",
    "Тише едешь — дальше будешь.",
    "Не откладывай на завтра то, что можно закрыть сегодня.",
]

private let dayJokes: [String] = [
    "— Сколько программистов нужно, чтобы вкрутить лампочку? — Ни одного, это аппаратная проблема.",
    "Мой код не работает, и я не знаю почему. Мой код работает, и я не знаю почему.",
    "— Как дела? — Как в Git: закоммитил и молюсь.",
    "Самая честная документация: «работает — не трогай».",
    "— Что делаешь? — Отлаживаю. — А давно? — С понедельника. — А сегодня четверг. — Да, с того понедельника.",
]

struct QuoteOfDayTool: View {
    private var quote: String {
        let index = Calendar.current.component(.day, from: Date()) % dayQuotes.count
        return dayQuotes[index]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("«" + quote + "»").font(.headline).frame(maxWidth: .infinity, alignment: .center)
            Button(L("Копировать")) { ToolClipboard.copy(quote) }.buttonStyle(.bordered).controlSize(.small)
                .frame(maxWidth: .infinity)
        }
    }
}

struct JokeOfDayTool: View {
    private var joke: String {
        let index = Calendar.current.component(.day, from: Date()) % dayJokes.count
        return dayJokes[index]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(joke).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
            Button(L("Копировать")) { ToolClipboard.copy(joke) }.buttonStyle(.bordered).controlSize(.small)
        }
    }
}
