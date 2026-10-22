import AppKit
import Combine

/// Запускает задачи для локального opencode прямо с острова.
/// Сессия появляется во вкладке «Агенты» сама — её следит AgentsStore.
final class AgentRunner: ObservableObject {
    @Published var running = false
    @Published var output = ""
    @Published var folder: String {
        didSet { UserDefaults.standard.set(folder, forKey: "settings.agentFolder") }
    }

    private var proc: Process?

    init() {
        folder = UserDefaults.standard.string(forKey: "settings.agentFolder") ?? NSHomeDirectory()
    }

    func launch(_ task: String, continueLast: Bool) {
        let text = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !running, !text.isEmpty else { return }
        var dir = folder.trimmingCharacters(in: .whitespaces)
        if dir.hasPrefix("~") { dir = NSHomeDirectory() + dir.dropFirst() }
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: dir, isDirectory: &isDir) || !isDir.boolValue { dir = NSHomeDirectory() }
        running = true
        output = ""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: NSHomeDirectory() + "/.opencode/bin/opencode")
        p.arguments = continueLast ? ["run", "--continue", text] : ["run", text]
        p.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + NSHomeDirectory() + "/.opencode/bin",
            "HOME": NSHomeDirectory(),
            "TERM": "dumb",
        ]
        p.currentDirectoryURL = URL(fileURLWithPath: dir)
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.running = false
                self?.output += "\n…готово"
            }
        }
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty { h.readabilityHandler = nil; return }
            let chunk = AgentRunner.stripANSI(String(decoding: data, as: UTF8.self))
            DispatchQueue.main.async {
                guard let self else { return }
                self.output = String(self.output.suffix(6000)) + chunk
            }
        }
        do { try p.run(); proc = p }
        catch {
            running = false
            output = "Не удалось запустить opencode: \(error.localizedDescription)"
        }
    }

    func stop() { proc?.terminate() }

    /// Убирает escape-последовательности терминала из вывода.
    static func stripANSI(_ s: String) -> String {
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "\u{1B}" {
                var j = s.index(after: i)
                while j < s.endIndex, !s[j].isLetter { j = s.index(after: j) }
                i = j < s.endIndex ? s.index(after: j) : j
            } else {
                out.append(s[i])
                i = s.index(after: i)
            }
        }
        return out
    }
}
