import SwiftUI
import AppKit

// MARK: - 060 Git-статус

struct GitStatusTool: View {
    @ViewState private var path = ""
    @ViewState private var output = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DropZone(hint: L("Перетащи папку с git-репозиторием")) { url in
                path = url.path
                refresh()
            }
            if !path.isEmpty {
                HStack {
                    Text(path).font(.system(size: 10, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button(L("Обновить")) { refresh() }.buttonStyle(.bordered).controlSize(.mini)
                }
            }
            Text(output.isEmpty ? "—" : output)
                .font(.system(size: 10, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                .textSelection(.enabled)
        }
    }

    private func refresh() {
        let escaped = path.replacingOccurrences(of: "\"", with: "")
        let branch = Shell.run("git -C \"\(escaped)\" branch --show-current").trimmingCharacters(in: .whitespacesAndNewlines)
        let status = Shell.run("git -C \"\(escaped)\" status --short")
        output = (branch.isEmpty ? "" : "ветка: " + branch + "\n") + status.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.isEmpty { output = L("Чисто, либо это не git-репозиторий") }
    }
}

// MARK: - 061 Коммиты

struct GitLogTool: View {
    @ViewState private var path = ""
    @ViewState private var output = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DropZone(hint: L("Перетащи папку с git-репозиторием")) { url in
                path = url.path
                refresh()
            }
            Text(output.isEmpty ? "—" : output)
                .font(.system(size: 10, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
                .textSelection(.enabled)
        }
    }

    private func refresh() {
        let escaped = path.replacingOccurrences(of: "\"", with: "")
        output = Shell.run("git -C \"\(escaped)\" log --oneline -8 2>&1").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 062 TODO-счётчик

struct TodoCountTool: View {
    @ViewState private var path = ""
    @ViewState private var output = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DropZone(hint: L("Перетащи папку проекта")) { url in
                path = url.path
                refresh()
            }
            Text(output.isEmpty ? "—" : output)
                .font(.system(size: 10, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
                .textSelection(.enabled)
        }
    }

    private func refresh() {
        let escaped = path.replacingOccurrences(of: "\"", with: "")
        let raw = Shell.run("grep -rn \"TODO\\|FIXME\" \"\(escaped)\" --include=\"*.swift\" --include=\"*.py\" --include=\"*.js\" --include=\"*.ts\" --include=\"*.go\" 2>/dev/null | head -10")
        let count = Shell.run("grep -rn \"TODO\\|FIXME\" \"\(escaped)\" --include=\"*.swift\" --include=\"*.py\" --include=\"*.js\" --include=\"*.ts\" --include=\"*.go\" 2>/dev/null | wc -l").trimmingCharacters(in: .whitespacesAndNewlines)
        output = L("Найдено: ") + count + "\n\n" + raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if count == "0" { output = L("TODO и FIXME не нашлось") }
    }
}

// MARK: - 063 Открыть в редакторе

struct OpenEditorTool: View {
    @ViewState private var path = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DropZone(hint: L("Перетащи папку или файл")) { url in path = url.path }
            HStack(spacing: 6) {
                Button(L("VS Code")) { open(with: "Visual Studio Code") }
                Button(L("Finder")) { open(with: "Finder") }
                Button(L("Терминал")) { open(with: "Terminal") }
            }.buttonStyle(.bordered).controlSize(.small)
            if !path.isEmpty {
                Text(path).font(.system(size: 10, design: .monospaced)).lineLimit(2)
            }
        }
    }

    private func open(with app: String) {
        guard !path.isEmpty else { return }
        let escaped = path.replacingOccurrences(of: "\"", with: "")
        Shell.run("open -a \"\(app)\" \"\(escaped)\"")
    }
}

// MARK: - 064 Локальный сервер

struct LocalServerTool: View {
    @ViewState private var path = ""
    @ViewState private var port = "8000"
    @ViewState private var running = false
    @ViewState private var process: Process?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DropZone(hint: L("Перетащи папку, которую раздаём")) { url in path = url.path }
            HStack(spacing: 6) {
                TextField(L("Порт"), text: $port).textFieldStyle(.roundedBorder).frame(width: 70)
                Button(running ? L("Стоп") : L("Запустить")) { running ? stop() : start() }
                    .buttonStyle(.bordered).controlSize(.small)
                if running {
                    Text("http://localhost:\(port)").font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        guard !path.isEmpty else { return }
        let escaped = path.replacingOccurrences(of: "\"", with: "")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "python3 -m http.server \(port) --directory \"\(escaped)\""]
        try? process.run()
        self.process = process
        running = process.isRunning
    }

    private func stop() {
        process?.terminate()
        process = nil
        running = false
    }
}

// MARK: - 065 Порты

struct PortWhoTool: View {
    @ViewState private var port = "8000"
    @ViewState private var output = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField(L("Порт"), text: $port).textFieldStyle(.roundedBorder)
                Button(L("Кто слушает")) { run() }.buttonStyle(.bordered).controlSize(.small)
                Button(L("Убить")) { kill() }.buttonStyle(.bordered).controlSize(.small)
            }
            Text(output.isEmpty ? "—" : output)
                .font(.system(size: 10, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
                .textSelection(.enabled)
        }
    }

    private func run() {
        output = Shell.run("lsof -nP -iTCP:\(port) -sTCP:LISTEN").trimmingCharacters(in: .whitespacesAndNewlines)
        if output.isEmpty { output = L("Никто не слушает") }
    }

    private func kill() {
        let pids = Shell.run("lsof -ti tcp:\(port) -sTCP:LISTEN").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pids.isEmpty else { output = L("Никого не слушает, убивать нечего"); return }
        Shell.run("kill -9 \(pids.replacingOccurrences(of: "\n", with: " "))")
        run()
    }
}

// MARK: - 066 Git-диф

struct GitDiffTool: View {
    @ViewState private var path = ""
    @ViewState private var output = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DropZone(hint: L("Перетащи папку с git-репозиторием")) { url in
                path = url.path
                refresh()
            }
            ToolCopyRow(text: output)
        }
    }

    private func refresh() {
        let escaped = path.replacingOccurrences(of: "\"", with: "")
        let stat = Shell.run("git -C \"\(escaped)\" diff HEAD --stat 2>&1 | head -20").trimmingCharacters(in: .whitespacesAndNewlines)
        if stat.isEmpty {
            output = L("Несохранённых изменений нет")
        } else {
            let detail = Shell.run("git -C \"\(escaped)\" diff HEAD 2>&1 | head -50").trimmingCharacters(in: .whitespacesAndNewlines)
            output = stat + "\n\n" + detail
        }
    }
}

// MARK: - 067 API-тест

struct ApiTestTool: View {
    @ViewState private var method = "GET"
    @ViewState private var url = ""
    @ViewState private var payload = ""
    @ViewState private var output = ""

    private let methods = ["GET", "POST", "PUT", "DELETE", "PATCH"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(L("Метод"), selection: $method) {
                ForEach(methods, id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented)
            TextField(L("https://api.example.com"), text: $url)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
            if method != "GET" && method != "DELETE" {
                ToolInOut(placeholder: L("Тело запроса (JSON)"), input: $payload)
            }
            Button(L("Отправить")) { send() }.buttonStyle(.bordered).controlSize(.small)
            ToolCopyRow(text: output)
        }
    }

    private func send() {
        let clean = url.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, URL(string: clean) != nil else { output = L("Нужен корректный URL"); return }
        output = L("Отправляю…")
        let requestMethod = method
        let requestBody = payload
        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            var args = ["-s", "-S", "--max-time", "15", "-X", requestMethod,
                        "-w", "\n\n⇒ HTTP %{http_code} · %{time_total}s"]
            if !requestBody.isEmpty { args += ["-H", "Content-Type: application/json", "-d", requestBody] }
            args.append(clean)
            process.arguments = args
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            do { try process.run() } catch {
                DispatchQueue.main.async { output = L("Не смог запустить curl") }
                return
            }
            process.waitUntilExit()
            let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                var result = (stdout + (stderr.isEmpty ? "" : "\n" + stderr)).trimmingCharacters(in: .whitespacesAndNewlines)
                if result.count > 1600 { result = String(result.prefix(1600)) + "\n…" }
                output = result.isEmpty ? L("Пустой ответ") : result
            }
        }
    }
}

// MARK: - 068 Окружение

struct EnvInfoTool: View {
    @ViewState private var output = ""

    private let checks: [(String, String)] = [
        ("git", "git --version"),
        ("node", "node --version"),
        ("npm", "npm --version"),
        ("python3", "python3 --version"),
        ("swiftc", "swiftc --version | head -1"),
        ("go", "go version"),
        ("rustc", "rustc --version"),
        ("brew", "brew --version | head -1"),
        ("docker", "docker --version"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(L("Проверить окружение")) { refresh() }.buttonStyle(.bordered).controlSize(.small)
            Text(output.isEmpty ? "—" : output)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                .textSelection(.enabled)
        }
    }

    private func refresh() {
        output = "…"
        DispatchQueue.global().async {
            let lines = checks.map { name, command -> String in
                let line = Shell.run(command)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: .newlines).first ?? ""
                return "\(name): \(line.isEmpty ? "—" : line)"
            }
            let result = lines.joined(separator: "\n")
            DispatchQueue.main.async { output = result }
        }
    }
}

// MARK: - 069 Cron

struct CronExplainTool: View {
    @ViewState private var expression = "30 8 * * 1-5"
    @ViewState private var explanation = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolInOut(placeholder: L("мин час день месяц день_недели"), input: $expression)
            Button(L("Расшифровать")) { explain() }.buttonStyle(.bordered).controlSize(.small)
            Text(explanation.isEmpty ? "—" : explanation).font(.caption).textSelection(.enabled)
        }
    }

    private func explain() {
        let parts = expression.split(separator: " ").map(String.init)
        guard parts.count == 5 else { explanation = L("Нужно 5 полей"); return }
        var lines: [String] = []
        let names = [L("минуты"), L("часы"), L("день месяца"), L("месяц"), L("день недели")]
        for (index, part) in parts.enumerated() {
            let meaning = part == "*" ? L("любое") : (part.contains("/") ? L("каждые") + " " + part : part)
            lines.append("\(names[index]): \(meaning)")
        }
        explanation = lines.joined(separator: "\n")
    }
}
