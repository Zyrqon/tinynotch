import SwiftUI
import CoreWLAN

/// Запуск системных команд и разбор результата.
enum Shell {
    @discardableResult
    static func run(_ command: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - 029 Монитор CPU/RAM

struct SysMonitorsTool: View {
    @ViewState private var cpuLine = "…"
    @ViewState private var ramLine = "…"
    @ViewState private var timer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            monitorRow(L("Процессор"), cpuLine)
            monitorRow(L("Память"), ramLine)
            Text(L("Обновляется каждые 2 секунды")).font(.caption2).foregroundStyle(.secondary)
        }
        .onAppear { refresh(); timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in refresh() } }
        .onDisappear { timer?.invalidate(); timer = nil }
    }

    private func monitorRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        }
    }

    private func refresh() {
        let top = Shell.run("top -l 1 -n 0 | grep -E 'CPU usage|PhysMem'")
        let lines = top.split(separator: "\n").map(String.init)
        if let cpu = lines.first(where: { $0.contains("CPU usage") }) {
            cpuLine = cpu.replacingOccurrences(of: "CPU usage:", with: "").trimmingCharacters(in: .whitespaces)
        }
        if let mem = lines.first(where: { $0.contains("PhysMem") }) {
            ramLine = mem.replacingOccurrences(of: "PhysMem:", with: "").trimmingCharacters(in: .whitespaces)
        }
    }
}

// MARK: - 030 Место на дисках

struct DiskSpaceTool: View {
    @ViewState private var output = "…"
    @ViewState private var usedRatio: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: usedRatio)
                .progressViewStyle(.linear)
            HStack {
                Text(L("Корень диска")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%% занято", usedRatio * 100)).font(.system(.caption, design: .monospaced))
            }
            Text(output).font(.system(size: 10, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        let raw = Shell.run("df -h / | tail -1")
        output = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let columns = output.split(whereSeparator: { $0 == " " }).map(String.init)
        if columns.count >= 5 {
            let percent = columns[4].replacingOccurrences(of: "%", with: "")
            usedRatio = (Double(percent) ?? 0) / 100
        }
    }
}

// MARK: - 031 Батарея

struct BatteryInfoTool: View {
    @ViewState private var line = "…"
    @ViewState private var cycles = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(line).font(.headline)
            if cycles.isEmpty {
                Button(L("Показать циклы")) {
                    let raw = Shell.run("system_profiler SPPowerDataType | grep -E 'Cycle Count' | head -1")
                    cycles = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                }.buttonStyle(.bordered).controlSize(.small)
            } else {
                Text(cycles).font(.system(.caption, design: .monospaced))
            }
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        let raw = Shell.run("pmset -g batt")
        line = raw.split(separator: "\n").last.map(String.init) ?? "…"
    }
}

// MARK: - 032 Uptime

struct UptimeInfoTool: View {
    @ViewState private var line = "…"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(line).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        line = Shell.run("uptime").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 033 Публичный IP

struct PublicIPTool: View {
    @ViewState private var info = L("Проверяю…")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(info).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            Button(L("Обновить")) { fetch() }.buttonStyle(.bordered).controlSize(.small)
        }
        .onAppear { fetch() }
    }

    private func fetch() {
        info = L("Проверяю…")
        guard let url = URL(string: "https://ipinfo.io/json") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
                DispatchQueue.main.async { info = L("Не получилось получить") }
                return
            }
            let ip = payload["ip"] ?? "—"
            let city = payload["city"] ?? ""
            let country = payload["country"] ?? ""
            let org = payload["org"] ?? ""
            DispatchQueue.main.async {
                info = "ip: \(ip)\n\(city) \(country)\n\(org)"
            }
        }.resume()
    }
}

// MARK: - 034 Пинг

struct PingTool: View {
    @ViewState private var host = "8.8.8.8"
    @ViewState private var output = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField(L("Хост"), text: $host).textFieldStyle(.roundedBorder)
                Button(L("Пинг")) { run() }.buttonStyle(.bordered).controlSize(.small)
            }
            Text(output.isEmpty ? "—" : output)
                .font(.system(size: 10, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                .textSelection(.enabled)
        }
    }

    private func run() {
        let safe = host.replacingOccurrences(of: ";", with: "")
        output = Shell.run("ping -c 4 \(safe) 2>&1 | tail -3").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 035 Скорость сети

struct SpeedTestTool: View {
    @ViewState private var result = L("Нажми «Тест»")
    @ViewState private var running = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(running ? L("Меряю…") : L("Тест")) { run() }
                .buttonStyle(.bordered).controlSize(.small).disabled(running)
            Text(result).font(.headline).textSelection(.enabled)
            Text(L("Скачиваю тестовый файл и считаю скорость"))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func run() {
        running = true
        result = L("Меряю…")
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=10000000") else { running = false; return }
        let start = Date()
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let seconds = max(Date().timeIntervalSince(start), 0.001)
            let bytes = Double(data?.count ?? 0)
            let mbps = bytes * 8 / seconds / 1_000_000
            DispatchQueue.main.async {
                running = false
                result = String(format: "%.1f Mbps", mbps)
            }
        }.resume()
    }
}

// MARK: - 036 Размер папки

struct FolderSizeTool: View {
    @ViewState private var path = ""
    @ViewState private var result = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Перетащи папку сюда")).font(.caption).foregroundStyle(.secondary)
            Text(path.isEmpty ? "…" : path).font(.system(size: 10, design: .monospaced)).lineLimit(2)
            Text(result).font(.headline).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    path = url.path
                    let escaped = url.path.replacingOccurrences(of: "\"", with: "")
                    result = Shell.run("du -sh \"\(escaped)\" | cut -f1").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return true
        }
    }
}

// MARK: - 037 Большие файлы

struct BigFilesTool: View {
    @ViewState private var path = NSHomeDirectory()
    @ViewState private var output = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(path).font(.system(size: 10, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button(L("Искать")) { run() }.buttonStyle(.bordered).controlSize(.small)
            }
            Text(L("Перетащи папку, чтобы сменить")).font(.caption2).foregroundStyle(.secondary)
            Text(output.isEmpty ? "—" : output)
                .font(.system(size: 10, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                .textSelection(.enabled)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    path = url.path
                    run()
                }
            }
            return true
        }
    }

    private func run() {
        let escaped = path.replacingOccurrences(of: "\"", with: "")
        output = Shell.run("find \"\(escaped)\" -type f -size +100M -maxdepth 4 2>/dev/null | head -10 | xargs -I{} du -h \"{}\" 2>/dev/null")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if output.isEmpty { output = L("Файлов больше 100 МБ не нашлось") }
    }
}

// MARK: - 038 Корзина

struct EmptyTrashTool: View {
    @ViewState private var size = ""
    @ViewState private var done = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(L("Сколько лежит")) { measure() }.buttonStyle(.bordered).controlSize(.small)
            Button(L("Очистить корзину")) { empty() }
                .buttonStyle(.bordered).controlSize(.small).tint(.red)
            if !size.isEmpty { Text(size).font(.caption) }
            if done { Text(L("Корзина очищена")).font(.caption).foregroundStyle(.green) }
        }
    }

    private var trashURL: URL {
        URL(fileURLWithPath: NSHomeDirectory() + "/.Trash")
    }

    private func measure() {
        let escaped = trashURL.path
        size = Shell.run("du -sh \"\(escaped)\" 2>/dev/null | cut -f1").trimmingCharacters(in: .whitespacesAndNewlines)
        if size.isEmpty { size = L("Пусто") }
    }

    private func empty() {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil) else {
            size = L("Не получилось прочитать корзину"); return
        }
        for item in contents {
            try? FileManager.default.removeItem(at: item)
        }
        done = true
        measure()
    }
}

// MARK: - 039 Не спать (caffeinate)

struct CaffeinateTool: View {
    @ViewState private var active = false
    @ViewState private var process: Process?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(L("Mac не засыпает, пока включено"), isOn: Binding(
                get: { active },
                set: { newValue in newValue ? start() : stop() }
            )).toggleStyle(.switch)
            Text(L("Запускает caffeinate и держит его живым"))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func start() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-dimsu"]
        try? process.run()
        self.process = process
        active = process.isRunning
    }

    private func stop() {
        process?.terminate()
        process = nil
        active = false
    }
}

// MARK: - 040 Тёмная/светлая тема

struct ThemeToggleTool: View {
    @ViewState private var isDark: Bool? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let isDark {
                Text(isDark ? L("Сейчас: тёмная") : L("Сейчас: светлая"))
                    .font(.headline)
            }
            Button(L("Переключить тему")) { toggle() }.buttonStyle(.bordered).controlSize(.small)
        }
        .onAppear { read() }
    }

    private func read() {
        let raw = Shell.run("defaults read -g AppleInterfaceStyle 2>/dev/null")
        isDark = raw.trimmingCharacters(in: .whitespacesAndNewlines) == "Dark"
    }

    private func toggle() {
        let next = (isDark ?? false) ? "false" : "true"
        Shell.run("osascript -e 'tell application \"System Events\" to tell appearance preferences to set dark mode to \(next)'")
        read()
    }
}

// MARK: - 041 Не беспокоить

struct DNDToggleTool: View {
    @ViewState private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(L("Включить «Не беспокоить»")) { Shell.run("shortcuts run \"Не беспокоить\""); status = L("Запустил шорткат") }
                .buttonStyle(.bordered).controlSize(.small)
            Text(L("Нужен шорткат «Не беспокоить» в приложении Быстрые команды"))
                .font(.caption2).foregroundStyle(.secondary)
            Text(status).font(.caption)
        }
    }
}

// MARK: - 042 Процессы

private struct ProcRow: Identifiable {
    let id: Int
    let name: String
    let memoryMB: Double
}

struct KillProcessTool: View {
    @ViewState private var rows: [ProcRow] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(L("Обновить список")) { refresh() }.buttonStyle(.bordered).controlSize(.small)
            ForEach(rows) { row in
                HStack {
                    Text(row.name).font(.system(.caption, design: .monospaced)).lineLimit(1).truncationMode(.tail)
                    Spacer()
                    Text(String(format: "%.0f МБ", row.memoryMB)).font(.caption2).foregroundStyle(.secondary)
                    Button(L("Убить")) {
                        Shell.run("kill -9 \(row.id)")
                        refresh()
                    }.buttonStyle(.bordered).controlSize(.mini).tint(.red)
                }
            }
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        let raw = Shell.run("ps axo pid,rss,comm -m | head -12 | tail -10")
        rows = raw.split(separator: "\n").compactMap { line -> ProcRow? in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 2)
            guard parts.count >= 3, let pid = Int(parts[0]), let kb = Double(parts[1]) else { return nil }
            let path = String(parts[2])
            let name = path.split(separator: "/").last.map(String.init) ?? path
            return ProcRow(id: pid, name: name, memoryMB: kb / 1024)
        }
    }
}

// MARK: - 043 Wi-Fi

struct WifiListTool: View {
    @ViewState private var rows: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(L("Обновить")) { refresh() }.buttonStyle(.bordered).controlSize(.small)
            ForEach(rows, id: \.self) { Text($0).font(.system(.caption, design: .monospaced)) }
            if rows.isEmpty {
                Text(L("Сети не найдены")).font(.caption).foregroundStyle(.secondary)
            }
            Text(L("macOS может попросить доступ к геолокации для названий сетей"))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        var result: [String] = []
        if let interface = CWWiFiClient.shared().interface() {
            let ssid = interface.ssid() ?? L("скрыто системой")
            let rssi = interface.rssiValue()
            let noise = interface.noiseMeasurement()
            result.append("SSID: \(ssid) · RSSI: \(rssi ?? 0) dBm · шум: \(noise ?? 0) dBm")
            result.append("канал: \(interface.wlanChannel()?.channelNumber ?? 0)")
        }
        if result.isEmpty {
            let raw = Shell.run("networksetup -getairportnetwork en0")
            result = [raw.trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        rows = result
    }
}
