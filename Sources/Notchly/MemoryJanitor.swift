import AppKit
import Darwin

// MARK: - Уборщик памяти (по мотивам Mint)

/// Раз в полторы минуты смотрит на браузеры. Если браузер давно ничего не делал
/// (нулевой расход процессорного времени) и при этом работают ИИ-агенты —
/// корректно закрывает его и возвращает памяти десятки сотен мегабайт.
/// Оригиналы не трогает: закрытие как Cmd+Q, вкладки браузер восстановит сам.
final class MemoryJanitor {
    struct Watched: Equatable {
        let bundleID: String
        let name: String
    }

    static let watched: [Watched] = [
        Watched(bundleID: "com.google.Chrome", name: "Chrome"),
        Watched(bundleID: "com.google.Chrome.canary", name: "Chrome Canary"),
        Watched(bundleID: "org.chromium.Chromium", name: "Chromium"),
        Watched(bundleID: "com.yandex.yandexbrowser", name: "Яндекс Браузер"),
        Watched(bundleID: "company.thebrowser.Browser", name: "Arc"),
        Watched(bundleID: "com.apple.Safari", name: "Safari"),
        Watched(bundleID: "org.mozilla.firefox", name: "Firefox"),
        Watched(bundleID: "com.microsoft.edgemac", name: "Edge"),
        Watched(bundleID: "com.brave.Browser", name: "Brave"),
        Watched(bundleID: "com.vivaldi.Vivaldi", name: "Vivaldi"),
        Watched(bundleID: "com.operasoftware.Opera", name: "Opera"),
    ]

    struct Sample {
        var cpuTotal: UInt64
        var rss: UInt64
        var idleSince: Date?
    }

    /// Карточка «Освободилось …» (подставляет IslandModel): заголовок и текст.
    var onFreed: ((String, String) -> Void)?
    /// Настройки приходят замыканиями, чтобы уборщик не знал про UserDefaults.
    var isEnabled: () -> Bool = { false }
    var idleMinutes: () -> Int = { 10 }
    var onlyWithAgents: () -> Bool = { true }
    var isAgentActive: () -> Bool = { false }

    private var timer: Timer?
    private var samples: [Int32: Sample] = [:]

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        samples.removeAll()
    }

    private func check() {
        guard isEnabled() else { return }
        guard !onlyWithAgents() || isAgentActive() else { return }
        let limit = TimeInterval(max(idleMinutes(), 1) * 60)
        var candidates: [(app: NSRunningApplication, name: String, rss: UInt64)] = []
        let running = NSWorkspace.shared.runningApplications
        for app in running {
            guard app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier,
                  let watched = Self.watched.first(where: { $0.bundleID == bundleID }) else { continue }
            let pid = app.processIdentifier
            guard pid > 0 else { continue }
            // Браузер сейчас перед пользователем — не считаем его простаивающим.
            if app.isActive {
                samples[pid] = nil
                continue
            }
            guard let usage = usage(of: pid) else {
                samples[pid] = nil
                continue
            }
            var sample = samples[pid] ?? Sample(cpuTotal: usage.cpuNanos, rss: usage.rss, idleSince: Date())
            let delta = usage.cpuNanos >= sample.cpuTotal ? usage.cpuNanos - sample.cpuTotal : 0
            // Больше полсекунды процессорного времени за полторы минуты — браузер работает.
            if delta > 500_000_000 {
                sample = Sample(cpuTotal: usage.cpuNanos, rss: usage.rss, idleSince: Date())
                samples[pid] = sample
                continue
            }
            if sample.idleSince == nil { sample.idleSince = Date() }
            if let since = sample.idleSince, Date().timeIntervalSince(since) >= limit {
                candidates.append((app, watched.name, usage.rss))
            } else {
                samples[pid] = sample
            }
        }
        // Подчищаем образцы процессов, которых уже нет.
        let live = Set(running.map { $0.processIdentifier })
        samples = samples.filter { live.contains($0.key) }
        guard !candidates.isEmpty else { return }
        var freed: UInt64 = 0
        var names: [String] = []
        for candidate in candidates {
            freed += candidate.rss
            if !names.contains(candidate.name) { names.append(candidate.name) }
            candidate.app.terminate()
            samples[candidate.app.processIdentifier] = nil
        }
        let gigabytes = Double(freed) / 1_073_741_824
        let list = names.joined(separator: ", ")
        let body: String
        if gigabytes >= 0.1 {
            body = L("Закрыл \(list): простаивал дольше \(max(idleMinutes(), 1)) мин, освободилось ~\(String(format: "%.1f", gigabytes)) ГБ")
        } else {
            let megabytes = Int(Double(freed) / 1_048_576)
            body = L("Закрыл \(list): простаивал дольше \(max(idleMinutes(), 1)) мин, освободилось ~\(megabytes) МБ")
        }
        onFreed?(L("Память освобождена"), body)
    }

    /// Процессорное время (наносекунды) и резидентная память (байты) процесса.
    private func usage(of pid: pid_t) -> (cpuNanos: UInt64, rss: UInt64)? {
        var info = proc_taskinfo()
        let flavor: Int32 = 3  // PROC_PIDTASKINFO из proc_info.h
        let size = withUnsafeMutablePointer(to: &info) { pointer -> Int32 in
            proc_pidinfo(pid, flavor, 0, pointer, Int32(MemoryLayout<proc_taskinfo>.stride))
        }
        guard size >= Int32(MemoryLayout<proc_taskinfo>.size) else { return nil }
        return (info.pti_total_user &+ info.pti_total_system, info.pti_resident_size)
    }
}
