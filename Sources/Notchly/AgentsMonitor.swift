import AppKit
import Combine

/// Один запущенный агент: codex или opencode.
struct AgentSession: Identifiable, Equatable {
    enum Kind: String { case codex, opencode }
    enum State: Equatable { case idle, working, waiting }
    let id: String
    let kind: Kind
    var state: State
    var lastActivity: Date
    var title: String
    /// Папка проекта, где работает агент (как в Vibe Island).
    var directory: String? = nil
    /// Терминал (ttys…), где агент реально запущен, если удалось найти.
    var tty: String? = nil
    /// Пид процесса агента — по нему находим локальный сервер opencode для кнопок подтверждения.
    var pid: Int32? = nil

    /// Показываем «opencode · название сессии».
    var displayName: String {
        kind.rawValue + " · " + title
    }
}

/// Смотрит на сессии codex (~/.codex/sessions) и opencode (~/.local/share/opencode) раз в две секунды
/// и понимает, кто работает, а кто ждёт подтверждения. Ждущий даёт красный бейдж и карточку.
final class AgentsStore: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []
    /// Сколько агентов прямо сейчас ждут подтверждения — столько на вкладке «Агенты».
    @Published private(set) var waitingCount = 0
    /// Вызывается, когда агент впервые переходит в «ждёт подтверждения».
    var onApproval: ((String) -> Void)?
    /// Вызывается, когда агент закончил работу (перешёл из «работает» в «спит»).
    var onFinish: ((String) -> Void)?

    private var timer: Timer?
    private var waitingSeen = Set<String>()
    private var workingSeen = Set<String>()
    private var inFlight = false
    private var lastLogged = ""
    private var scanCount = 0
    private var pendingMap: [String: Int] = [:]
    private var lastOpenCode: [AgentSession] = []
    private var logURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchly", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("agents.log")
    }()

    private func log(_ text: String) {
        let line = "\(Date().formatted(date: .omitted, time: .standard)) \(text)\n"
        if let h = try? FileHandle(forWritingTo: logURL) {
            defer { try? h.close() }
            _ = try? h.seekToEndOfFile()
            h.write(Data(line.utf8))
        } else {
            try? line.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

    private var codexDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions", isDirectory: true)
    }
    private var openCodeDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/opencode", isDirectory: true)
    }

    func start() {
        guard timer == nil else { return }
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.scan() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func scan() {
        guard !inFlight else { return }
        inFlight = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let found = self?.collect() ?? []
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                self.sessions = found
                let sig = found.map { "\($0.kind.rawValue):\($0.state):\($0.title)" }.joined(separator: " | ")
                if sig != self.lastLogged { self.lastLogged = sig; self.log("sessions=\(found.count) \(sig.isEmpty ? "пусто" : sig)") }
                let nowWaiting = Set(found.filter { $0.state == .waiting }.map(\.id))
                for s in found where s.state == .waiting && !self.waitingSeen.contains(s.id) {
                    self.onApproval?(s.displayName)
                }
                self.waitingSeen = nowWaiting
                self.waitingCount = nowWaiting.count
                let nowWorking = Set(found.filter { $0.state == .working }.map(\.id))
                for s in found where s.state == .idle && self.workingSeen.contains(s.id) {
                    self.onFinish?(s.displayName)
                }
                self.workingSeen = nowWorking
            }
        }
    }

    private func collect() -> [AgentSession] {
        var out: [AgentSession] = codexSessions()
        scanCount += 1
        if scanCount % 5 == 0 { refreshPending() }
        if let oc = openCodeSessions() { lastOpenCode = oc }
        out.append(contentsOf: lastOpenCode)
        let rank: (AgentSession.State) -> Int = { $0 == .waiting ? 0 : ($0 == .working ? 1 : 2) }
        return out.sorted {
            rank($0.state) != rank($1.state) ? rank($0.state) < rank($1.state) : $0.lastActivity > $1.lastActivity
        }
    }

    // MARK: - codex (~/.codex/sessions/ГГГГ/ММ/ДД/rollout-*.jsonl)

    private func codexSessions() -> [AgentSession] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: codexDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var files: [(URL, Date, Date)] = []
        for case let url as URL in en {
            guard url.pathExtension == "jsonl" else { continue }
            let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            guard let date = vals?.contentModificationDate else { continue }
            guard date.timeIntervalSinceNow > -7 * 24 * 3600 else { continue }
            files.append((url, date, vals?.creationDate ?? date))
        }
        files.sort { $0.1 > $1.1 }
        return files.prefix(14).map { parseCodex($0.0, modified: $0.1, created: $0.2) }
    }

    /// Читает хвост журнала сессии: заявка на подтверждение остаётся «висеть», пока не появится
    /// следующее действие (запуск команды, ответ, конец хода) или сообщение пользователя.
    private func parseCodex(_ url: URL, modified: Date, created: Date) -> AgentSession {
        var sawApproval = false
        var title = ""
        var cwd: String?
        for raw in tail(of: url, bytes: 200_000).split(separator: "\n", omittingEmptySubsequences: true) {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] else { continue }
            var type = obj["type"] as? String ?? ""
            var payload = obj["payload"] as? [String: Any] ?? [:]
            if type == "session_meta", let cwdValue = payload["cwd"] as? String { cwd = cwdValue }
            if type == "event_msg" || type == "response_item" {
                type = payload["type"] as? String ?? ""
            } else {
                payload = [:]
            }
            switch type {
            case "user_message":
                sawApproval = false
                if let m = payload["message"] as? String, !m.isEmpty { title = String(m.prefix(48)) }
            case "exec_command_begin", "task_complete", "turn_aborted":
                sawApproval = false
            case let t where t.contains("decision") || t.contains("approved"):
                sawApproval = false
            case let t where t.contains("approval_request") || t.contains("apply_patch_approval"):
                sawApproval = true
            default: break
            }
        }
        let state: AgentSession.State
        if sawApproval { state = .waiting }
        else if -modified.timeIntervalSinceNow < 20 { state = .working }
        else { state = .idle }
        if title.isEmpty { title = modified.shortClock() }
        var s = AgentSession(id: url.path, kind: .codex, state: state, lastActivity: modified, title: title)
        s.directory = cwd
        s.tty = bestProc(created: created, procs: agentProcesses().filter { $0.kind == .codex })?.tty
        return s
    }

    // MARK: - opencode (его собственная база opencode.db)

    /// opencode сам держит SQLite-базу: сессии и части сообщений.
    /// Инструмент, который ждёт подтверждения, лежит в базе со статусом "pending";
    /// это и есть настоящий сигнал, а не слова в журнале.
    private func openCodeSessions() -> [AgentSession]? {
        let dbURL = openCodeDir.appendingPathComponent("opencode.db")
        guard FileManager.default.fileExists(atPath: dbURL.path) else { log("opencode: нет файла базы"); return nil }
        // Быстрый запрос без parts: состояние «работает» считаем по свежести сессии.
        let query = "SELECT id, title, directory, time_created, time_updated FROM session WHERE time_archived IS NULL ORDER BY time_updated DESC LIMIT 20;"
        guard let out = runSQLite(query, db: dbURL) else { return nil }
        guard let data = out.data(using: .utf8),
              let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return nil }

        let procs = agentProcesses().filter { $0.kind == .opencode }
        let plugin = pluginStatuses()
        var result: [AgentSession] = []
        for row in rows {
            let id = row["id"] as? String ?? UUID().uuidString
            let createdMs = (row["time_created"] as? NSNumber)?.doubleValue ?? 0
            let updatedMs = (row["time_updated"] as? NSNumber)?.doubleValue ?? 0
            let pending = pendingMap[id] ?? 0
            let created = Date(timeIntervalSince1970: createdMs / 1000)
            let updated = Date(timeIntervalSince1970: updatedMs / 1000)
            let age = -updated.timeIntervalSinceNow
            guard age >= 0, age < 7 * 24 * 3600 else { continue } // сессии за последнюю неделю
            var state: AgentSession.State
            if pending > 0 { state = .waiting }
            else if age < 45 { state = .working }
            else { state = .idle }
            // Точный статус от плагина opencode перекрывает эвристику (файл свежее 2 минут).
            if let fresh = plugin[id] { state = fresh }
            var title = row["title"] as? String ?? ""
            if title.isEmpty || title == "New session" { title = "opencode" }
            if title.count > 46 { title = String(title.prefix(46)) }
            var s = AgentSession(id: id, kind: .opencode, state: state, lastActivity: updated, title: title)
            s.directory = row["directory"] as? String
            let hit = bestProc(created: created, procs: procs)
            s.tty = hit?.tty
            s.pid = hit?.pid
            result.append(s)
        }
        return result
    }

    /// Точные статусы от плагина opencode: notch.json рядом с базой.
    /// Плагин сам сообщает working/waiting/idle по событиям, остров больше не угадывает.
    private func pluginStatuses() -> [String: AgentSession.State] {
        let url = openCodeDir.appendingPathComponent("notch.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let map = root["sessions"] as? [String: Any] else { return [:] }
        var out: [String: AgentSession.State] = [:]
        for (id, raw) in map {
            guard let info = raw as? [String: Any],
                  let status = info["status"] as? String,
                  let ts = (info["ts"] as? NSNumber)?.doubleValue else { continue }
            guard -Date(timeIntervalSince1970: ts / 1000).timeIntervalSinceNow < 120 else { continue }
            out[id] = status == "waiting" ? .waiting : (status == "working" ? .working : .idle)
        }
        return out
    }

    // MARK: - Процессы агентов и их терминалы

    private struct AgentProc { let kind: AgentSession.Kind; let pid: Int32; let tty: String; let started: Date }

    /// Живые процессы opencode/codex и в каком терминале (ttys…) каждый висит.
    private func agentProcesses() -> [AgentProc] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["ax", "-o", "pid=,tty=,etimes=,command="]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var out: [AgentProc] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 4 else { continue }
            let base = (parts[3] as NSString).lastPathComponent
            let kind: AgentSession.Kind
            if base == "opencode" { kind = .opencode }
            else if base == "codex" { kind = .codex }
            else { continue }
            let tty = parts[1]
            guard tty.hasPrefix("ttys"), let et = Double(parts[2]) else { continue }
            out.append(AgentProc(kind: kind, pid: Int32(parts[0]) ?? 0, tty: tty, started: Date().addingTimeInterval(-et)))
        }
        return out
    }

    /// Какой терминал открывать для сессии: совпадение по времени создания (±30 мин),
    /// иначе самое свежее запущенное окно этого агента.
    private func bestProc(created: Date, procs: [AgentProc]) -> AgentProc? {
        var best: (AgentProc, TimeInterval)?
        for p in procs {
            let d = abs(p.started.timeIntervalSince(created))
            if d < 30 * 60, best == nil || d < best!.1 { best = (p, d) }
        }
        return best?.0 ?? procs.max { $0.started < $1.started }
    }

    /// Ждущие подтверждения: части со статусом pending за последние 15 минут. Раз в ~10с, отдельно.
    private func refreshPending() {
        let dbURL = openCodeDir.appendingPathComponent("opencode.db")
        let query = "SELECT p.session_id AS sid, COUNT(*) AS pending FROM part p WHERE p.time_updated > (strftime('%s','now')*1000 - 900000) AND json_extract(p.data,'$.type')='tool' AND json_extract(p.data,'$.state.status')='pending' GROUP BY p.session_id;"
        guard let out = runSQLite(query, db: dbURL),
              let data = out.data(using: .utf8),
              let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return }
        var map: [String: Int] = [:]
        for row in rows {
            if let sid = row["sid"] as? String { map[sid] = (row["pending"] as? NSNumber)?.intValue ?? 0 }
        }
        pendingMap = map
    }

    /// Короткая заметка о последнем действии (кнопки «Разрешить/Запретить»).
    @Published private(set) var actionNote: String?

    /// Отвечает на запрос подтверждения opencode прямо с острова.
    func replyToPermission(_ session: AgentSession, allow: Bool) {
        guard let pid = session.pid else {
            setNote(L("Не вижу процесс агента — подтверди в терминале"))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let port = AgentPermission.serverPort(pid: pid) else {
                DispatchQueue.main.async { self?.setNote(L("Сервер opencode не найден — подтверди в терминале")) }
                return
            }
            let requests = AgentPermission.pending(port: port).filter { $0.sessionID == session.id }
            guard !requests.isEmpty else {
                DispatchQueue.main.async { self?.setNote(L("Запросов подтверждения нет")) }
                return
            }
            for r in requests {
                AgentPermission.reply(port: port, requestID: r.id, reply: allow ? "once" : "reject")
            }
            DispatchQueue.main.async {
                self?.setNote(allow ? L("Разрешено") : L("Запрещено"))
                self?.scan()
            }
        }
    }

    private func setNote(_ text: String) {
        actionNote = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.actionNote == text { self?.actionNote = nil }
        }
    }

    private func runSQLite(_ query: String, db: URL) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        // База opencode в WAL-режиме: читаем напрямую в mode=ro, копировать гигабайты не нужно.
        p.arguments = ["-json", "file:\(db.path)?mode=ro", ".timeout 2000", query]
        let pipe = Pipe()
        p.standardOutput = pipe
        let errPipe = Pipe()
        p.standardError = errPipe
        do { try p.run() } catch { return nil }
        // Страховка: если sqlite всё же завис, убиваем через 12с, чтобы цикл не встал.
        let watchdog = DispatchWorkItem { if p.isRunning { p.terminate(); self.log("sqlite: не ответил, убит по таймауту") } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 12, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        watchdog.cancel()
        p.waitUntilExit()
        guard p.terminationStatus == 0, !data.isEmpty else {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            log("sqlite exit=\(p.terminationStatus) err=\(err.prefix(200)) out=\((String(data: data, encoding: .utf8) ?? "").prefix(200))")
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Утилиты

    private func tail(of url: URL, bytes: Int) -> String {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? fh.close() }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let start = max(0, size - bytes)
        if start > 0 { try? fh.seek(toOffset: UInt64(start)) }
        let data = (try? fh.readToEnd()) ?? Data()
        var text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        if start > 0, let i = text.firstIndex(of: "\n") { text = String(text[text.index(after: i)...]) }
        return text
    }
}

extension Date {
    func shortClock() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: self)
    }
}
