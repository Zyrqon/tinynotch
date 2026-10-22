import AppKit
import CryptoKit
import Network
import Security
import SwiftUI

/// Чат с Fo: остров пишет ему по MCP (streamable HTTP).
/// Вход по OAuth через браузер (кнопка «Войти»); токен хранится в UserDefaults.
final class FoChatModel: ObservableObject {
    struct Msg: Identifiable, Equatable {
        enum Role { case user, fo, error }
        let id = UUID()
        let role: Role
        var text: String
        let time: Date
    }

    struct Conv: Identifiable, Equatable {
        let id: String
        let title: String
        let channel: String
        let when: Date?
    }

    @Published var messages: [Msg] = []
    @Published var busy = false
    @Published var endpoint: String {
        didSet { UserDefaults.standard.set(endpoint, forKey: "settings.foEndpoint") }
    }
    @Published var token: String {
        didSet { UserDefaults.standard.set(token, forKey: "settings.foToken") }
    }
    @Published var showSettings = false
    @Published var draft = ""
    @Published var loginStatus = ""
    @Published var loggingIn = false
    @Published var showHistory = false
    @Published var convs: [Conv] = []
    @Published var convsStatus = ""
    @Published var loadingConvs = false
    @Published var openConv: Conv? = nil
    @Published var historyMsgs: [Msg] = []
    @Published var loadingConv = false

    private var rpcID = 0

    init() {
        endpoint = UserDefaults.standard.string(forKey: "settings.foEndpoint") ?? ""
        token = UserDefaults.standard.string(forKey: "settings.foToken") ?? ""
    }

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        guard !endpoint.isEmpty else {
            showSettings = true
            messages.append(Msg(role: .error, text: "Сначала укажи адрес подключения.", time: Date()))
            return
        }
        if let conv = openConv {
            historyMsgs.append(Msg(role: .user, text: text, time: Date()))
            busy = true
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let reply = self?.ask(text, convID: conv.id) ?? "Не получилось связаться."
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.busy = false
                    self.historyMsgs.append(Msg(role: reply.hasPrefix("⚠️") ? .error : .fo, text: reply, time: Date()))
                }
            }
            return
        }
        messages.append(Msg(role: .user, text: text, time: Date()))
        busy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let reply = self?.ask(text) ?? "Не получилось связаться."
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                self.messages.append(Msg(role: reply.hasPrefix("⚠️") ? .error : .fo, text: reply, time: Date()))
            }
        }
    }

    // MARK: - Все чаты

    static let stampFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM HH:mm"
        f.locale = Locale(identifier: "ru_RU")
        return f
    }()

    private func foToolCall(_ name: String, _ args: [String: Any]) -> (ok: Bool, text: String) {
        let reply: String
        do {
            reply = try rpc("tools/call", params: ["name": name, "arguments": args])
        } catch {
            return (false, "⚠️ \(error.localizedDescription)")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any],
              let result = obj["result"] as? [String: Any],
              let content = result["content"] as? [[String: Any]],
              let first = content.first?["text"] as? String, !first.isEmpty else {
            return (false, reply.hasPrefix("⚠️") ? reply : "⚠️ Пустой ответ сервера")
        }
        return (true, first)
    }

    func loadConversations() {
        guard !loadingConvs else { return }
        loadingConvs = true
        convsStatus = ""
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let pair: (ok: Bool, text: String)? = self?.foToolCall("list_fo_conversations", [:])
            guard let res = pair else {
                DispatchQueue.main.async { self?.loadingConvs = false }
                return
            }
            DispatchQueue.main.async {
                self?.loadingConvs = false
                guard res.ok else {
                    self?.convsStatus = res.text
                    return
                }
                let list = FoChatModel.parseConvList(res.text)
                self?.convs = list
                if list.isEmpty {
                    self?.convsStatus = "Чатов пока нет."
                }
            }
        }
    }

    /// Строка сервера: "Название (канал, дата) – id".
    private static func parseConvList(_ text: String) -> [Conv] {
        text.split(separator: "\n").compactMap { line in
            guard let range = line.range(of: " – ", options: .backwards) else { return nil }
            let id = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard id.count >= 8 else { return nil }
            let head = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            var title = head, channel = "", stamp = ""
            if let o = head.range(of: "("), let c = head.range(of: ")", options: .backwards),
               o.upperBound < c.lowerBound {
                title = String(head[..<o.lowerBound]).trimmingCharacters(in: .whitespaces)
                let inner = String(head[o.upperBound..<c.lowerBound])
                if let comma = inner.range(of: ", ") {
                    channel = String(inner[..<comma.lowerBound])
                    stamp = String(inner[comma.upperBound...])
                } else {
                    channel = inner
                }
            }
            return Conv(id: id,
                        title: title.isEmpty ? "Без названия" : title,
                        channel: channel,
                        when: parseStamp(stamp))
        }
    }

    private static func parseStamp(_ s: String) -> Date? {
        guard !s.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        return f.date(from: s)
    }

    func openConversation(_ c: Conv) {
        openConv = c
        historyMsgs = []
        loadingConv = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let pair: (ok: Bool, text: String)? = self?.foToolCall("get_fo_conversation", ["conversationId": c.id])
            guard let res = pair else {
                DispatchQueue.main.async { self?.loadingConv = false }
                return
            }
            DispatchQueue.main.async {
                self?.loadingConv = false
                guard res.ok else {
                    self?.historyMsgs = [FoChatModel.Msg(role: .error, text: res.text, time: Date())]
                    return
                }
                let msgs = FoChatModel.parseTranscript(res.text)
                if msgs.isEmpty {
                    self?.historyMsgs = [FoChatModel.Msg(role: .error, text: "Расшифровка пуста.", time: Date())]
                } else {
                    self?.historyMsgs = msgs
                }
            }
        }
    }

    /// Расшифровка: "user: ..." / "assistant: ..." через пустую строку; первая строка без префикса — название чата.
    private static func parseTranscript(_ text: String) -> [Msg] {
        var out: [Msg] = []
        for raw in text.split(separator: "\n\n") {
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { continue }
            if s.hasPrefix("user:") {
                out.append(Msg(role: .user, text: String(s.dropFirst(5)).trimmingCharacters(in: .whitespaces), time: Date()))
            } else if s.hasPrefix("assistant:") {
                out.append(Msg(role: .fo, text: String(s.dropFirst(10)).trimmingCharacters(in: .whitespaces), time: Date()))
            } else if out.isEmpty {
                continue
            } else {
                out[out.count - 1].text += "\n\n" + s
            }
        }
        return out
    }

    // MARK: - MCP (streamable HTTP)

    private struct ToolResult {
        var status = ""
        var conversationID = ""
        var response = ""
        var progress = ""
    }

    private func ask(_ text: String, convID: String? = nil) -> String {
        do {
            try rpc("initialize", params: ["protocolVersion": "2025-06-18", "capabilities": [:],
                                           "clientInfo": ["name": "Notchly", "version": "0.3"]])
            try notify("notifications/initialized")
            let saved = UserDefaults.standard.string(forKey: "settings.foConversation")
            var args: [String: Any] = ["message": text]
            if let cid = convID, !cid.isEmpty {
                args["conversationId"] = cid
            } else if let cid = saved, !cid.isEmpty {
                args["conversationId"] = cid
            } else {
                args["newConversation"] = true
            }
            var out = try callTool("ask_fo", args)
            var rounds = 0
            while out.status == "working", rounds < 15 {
                rounds += 1
                if !out.progress.isEmpty {
                    let line = out.progress
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        let m = Msg(role: .fo, text: "· " + line, time: Date())
                        if self.openConv != nil {
                            self.historyMsgs.append(m)
                        } else {
                            self.messages.append(m)
                        }
                    }
                }
                var poll: [String: Any] = ["waitSeconds": 40]
                if !out.conversationID.isEmpty { poll["conversationId"] = out.conversationID }
                out = try callTool("get_fo_reply", poll)
            }
            if convID == nil, !out.conversationID.isEmpty {
                UserDefaults.standard.set(out.conversationID, forKey: "settings.foConversation")
            }
            if out.status == "complete" || out.status == "failed" { return out.response }
            return "⚠️ Не дождался ответа за ~10 минут, попробуй спросить ещё раз."
        } catch {
            return "⚠️ \(error.localizedDescription)"
        }
    }

    private func callTool(_ name: String, _ args: [String: Any]) throws -> ToolResult {
        let raw = try rpc("tools/call", params: ["name": name, "arguments": args])
        return Self.parseToolOutput(raw)
    }

    /// Результат tools/call: structuredContent, либо JSON внутри content[].text.
    private static func parseToolOutput(_ raw: String) -> ToolResult {
        var r = ToolResult()
        func fill(_ obj: [String: Any]) {
            r.status = obj["status"] as? String ?? ""
            r.conversationID = obj["conversationId"] as? String ?? ""
            r.response = obj["response"] as? String ?? ""
            r.progress = obj["progress"] as? String ?? ""
        }
        func attempt(_ s: String) -> Bool {
            guard let d = s.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return false }
            if let result = obj["result"] as? [String: Any] {
                if let sc = result["structuredContent"] as? [String: Any] { fill(sc); return true }
                if let content = result["content"] as? [[String: Any]] {
                    for c in content {
                        if let t = c["text"] as? String, let inner = try? JSONSerialization.jsonObject(with: Data(t.utf8)) as? [String: Any] {
                            fill(inner); return true
                        }
                    }
                }
            }
            if obj["status"] != nil { fill(obj); return true }
            return false
        }
        if attempt(raw) { return r }
        for line in raw.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.hasPrefix("data:") else { continue }
            if attempt(String(s.dropFirst(5)).trimmingCharacters(in: .whitespaces)) { return r }
        }
        r.status = "failed"
        r.response = raw.isEmpty ? "Пустой ответ сервера" : raw
        return r
    }

    func foLog(_ line: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Notchly", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let p = dir.appendingPathComponent("fo.log")
        let df = DateFormatter(); df.dateFormat = "HH:mm:ss"
        let s = "[" + df.string(from: Date()) + "] " + line + "\n"
        if let h = try? FileHandle(forWritingTo: p) {
            _ = try? h.seekToEnd(); h.write(Data(s.utf8)); try? h.close()
        } else { try? Data(s.utf8).write(to: p) }
    }

    // MARK: - OAuth вход (кнопка «Войти»)

    private var refreshToken: String {
        get { UserDefaults.standard.string(forKey: "settings.foRefresh") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "settings.foRefresh") }
    }

    private var oauthBase: String {
        if var c = URLComponents(string: endpoint.trimmingCharacters(in: .whitespaces)) {
            c.path = ""
            if let s = c.string, let u = URL(string: s), !s.isEmpty { return s }
        }
        return "https://mcp.api.wajo.ai"
    }

    func startLogin() {
        guard !loggingIn else { return }
        DispatchQueue.main.async {
            self.loggingIn = true
            self.loginStatus = "Готовим вход…"
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let base = self.oauthBase
                let (listenFD, port) = try Self.bindListener()
                defer { close(listenFD) }
                let redirect = "http://127.0.0.1:\(port)/callback"
                self.foLog("oauth: порт \(port), регистрирую клиента")
                let clientID = try self.registerClient(base: base, redirect: redirect)
                let verifier = Self.randomVerifier()
                let state = Self.randomVerifier()
                var comps = URLComponents(string: base + "/oauth/authorize")!
                comps.queryItems = [
                    .init(name: "response_type", value: "code"),
                    .init(name: "client_id", value: clientID),
                    .init(name: "redirect_uri", value: redirect),
                    .init(name: "scope", value: "mcp"),
                    .init(name: "code_challenge", value: Self.s256(verifier)),
                    .init(name: "code_challenge_method", value: "S256"),
                    .init(name: "state", value: state),
                ]
                guard let authURL = comps.url else {
                    throw NSError(domain: "fo", code: 7, userInfo: [NSLocalizedDescriptionKey: "Не собрали ссылку входа"])
                }
                DispatchQueue.main.async { self.loginStatus = "Открываю браузер — войди и разреши доступ." }
                let code = try self.awaitCode(listenFD: listenFD, url: authURL, expectedState: state)
                DispatchQueue.main.async { self.loginStatus = "Обмениваю код на токен…" }
                let pair = try self.exchangeToken(base: base, code: code, verifier: verifier, clientID: clientID, redirect: redirect)
                DispatchQueue.main.async {
                    self.token = pair.access
                    self.refreshToken = pair.refresh
                    self.loggingIn = false
                    self.loginStatus = pair.access.isEmpty ? "⚠️ Сервер прислал пустой токен" : ""
                    if !pair.access.isEmpty { self.foLog("oauth: вход выполнен, токен сохранён") }
                }
            } catch {
                self.foLog("oauth: ошибка \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.loggingIn = false
                    self.loginStatus = "⚠️ \(error.localizedDescription)"
                }
            }
        }
    }

    /// Слушатель ответа браузера на обычных сокетах: NWListener на этой macOS падает с EINVAL.
    private static func bindListener() throws -> (Int32, UInt16) {
        for port in [UInt16](8765...8774) {
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else { break }
            var one: Int32 = 1
            _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)
            var bound = false
            withUnsafePointer(to: &addr) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                    bound = bind(fd, sp, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                }
            }
            guard bound, listen(fd, 8) == 0 else { close(fd); continue }
            var flags = fcntl(fd, F_GETFL)
            flags |= O_NONBLOCK
            _ = fcntl(fd, F_SETFL, flags)
            return (fd, port)
        }
        throw NSError(domain: "fo", code: 3, userInfo: [NSLocalizedDescriptionKey: "Не удалось занять порт 8765-8774"])
    }

    private func awaitCode(listenFD: Int32, url: URL, expectedState: String) throws -> String {
        DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        let deadline = Date().addingTimeInterval(240)
        while Date() < deadline {
            var clientAddr = sockaddr()
            var len = socklen_t(MemoryLayout<sockaddr>.size)
            let cfd = accept(listenFD, &clientAddr, &len)
            guard cfd >= 0 else { usleep(100_000); continue }
            var buf = [UInt8](repeating: 0, count: 16384)
            let r = buf.withUnsafeMutableBytes { raw in recv(cfd, raw.baseAddress!, raw.count, 0) }
            let head = r > 0 ? String(decoding: buf[..<r], as: UTF8.self) : ""
            var code: String?
            var state: String?
            let parts = head.split(separator: "\r\n").first.map(String.init)?.split(separator: " ") ?? []
            let target = parts.count > 1 ? String(parts[1]) : ""
            if let c = URLComponents(string: "http://local" + target) {
                code = c.queryItems?.first(where: { $0.name == "code" })?.value
                state = c.queryItems?.first(where: { $0.name == "state" })?.value
            }
            let body = "<h3 style='font-family:sans-serif'>Вход выполнен. Вернись в Notchly.</h3>"
            let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n" + body
            let respData = Array(resp.utf8)
            respData.withUnsafeBytes { raw in _ = Darwin.send(cfd, raw.baseAddress, raw.count, 0) }
            close(cfd)
            if let code = code, !code.isEmpty {
                guard state == expectedState else {
                    throw NSError(domain: "fo", code: 4, userInfo: [NSLocalizedDescriptionKey: "Проверка state не прошла"])
                }
                return code
            }
        }
        throw NSError(domain: "fo", code: 4, userInfo: [NSLocalizedDescriptionKey: "Браузер не вернул код за 4 минуты"])
    }

    private func registerClient(base: String, redirect: String) throws -> String {
        let payload: [String: Any] = [
            "client_name": "Notchly",
            "redirect_uris": [redirect],
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "token_endpoint_auth_method": "none",
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (status, data) = try httpSync(URL(string: base + "/oauth/register")!, method: "POST",
                                          contentType: "application/json", body: body)
        guard (200...299).contains(status),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cid = obj["client_id"] as? String else {
            throw NSError(domain: "fo", code: 5, userInfo: [NSLocalizedDescriptionKey: "Сервер не выдал client_id (код \(status))"])
        }
        UserDefaults.standard.set(cid, forKey: "settings.foClient")
        return cid
    }

    private func exchangeToken(base: String, code: String, verifier: String, clientID: String, redirect: String) throws -> (access: String, refresh: String) {
        var c = URLComponents()
        c.queryItems = [
            .init(name: "grant_type", value: "authorization_code"),
            .init(name: "code", value: code),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "client_id", value: clientID),
            .init(name: "code_verifier", value: verifier),
        ]
        let body = c.percentEncodedQuery?.data(using: .utf8) ?? Data()
        let (status, data) = try httpSync(URL(string: base + "/oauth/token")!, method: "POST",
                                          contentType: "application/x-www-form-urlencoded", body: body)
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let at = obj?["access_token"] as? String {
            return (at, obj?["refresh_token"] as? String ?? "")
        }
        let msg = (obj?["error_description"] as? String) ?? (obj?["error"] as? String) ?? ""
        throw NSError(domain: "fo", code: 6, userInfo: [NSLocalizedDescriptionKey: "Токен не выдан (код \(status)) \(msg)"])
    }

    private func refreshAccessToken() -> String? {
        guard let cid = UserDefaults.standard.string(forKey: "settings.foClient"), !cid.isEmpty,
              let tokenURL = URL(string: oauthBase + "/oauth/token") else { return nil }
        var c = URLComponents()
        c.queryItems = [
            .init(name: "grant_type", value: "refresh_token"),
            .init(name: "refresh_token", value: refreshToken),
            .init(name: "client_id", value: cid),
        ]
        guard let body = c.percentEncodedQuery?.data(using: .utf8),
              let (status, data) = try? httpSync(tokenURL, method: "POST",
                                                 contentType: "application/x-www-form-urlencoded", body: body),
              (200...299).contains(status),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let at = obj["access_token"] as? String else {
            foLog("oauth: refresh не удался")
            return nil
        }
        refreshToken = obj["refresh_token"] as? String ?? refreshToken
        foLog("oauth: токен обновлён по refresh")
        return at
    }

    private func httpSync(_ url: URL, method: String, contentType: String, body: Data) throws -> (Int, Data) {
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = method
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        var resp: URLResponse?
        var data: Data?
        var err: Error?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { d, r, e in data = d; resp = r; err = e; sem.signal() }.resume()
        sem.wait()
        if let e = err { throw NSError(domain: "fo", code: 8, userInfo: [NSLocalizedDescriptionKey: "Сеть: \(e.localizedDescription)"]) }
        guard let http = resp as? HTTPURLResponse else {
            throw NSError(domain: "fo", code: 8, userInfo: [NSLocalizedDescriptionKey: "Нет ответа сервера"])
        }
        return (http.statusCode, data ?? Data())
    }

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64url(Data(bytes))
    }

    private static func s256(_ value: String) -> String {
        base64url(Data(SHA256.hash(data: Data(value.utf8))))
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    @discardableResult
    private func rpc(_ method: String, params: [String: Any]) throws -> String {
        rpcID += 1
        let body: [String: Any] = ["jsonrpc": "2.0", "id": rpcID, "method": method, "params": params]
        guard let reply = post(body) else { throw NSError(domain: "fo", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Нет связи с сервером"]) }
        guard reply.0 else { throw NSError(domain: "fo", code: 1,
            userInfo: [NSLocalizedDescriptionKey: reply.1]) }
        return reply.1
    }

    private func notify(_ method: String) throws {
        _ = post(["jsonrpc": "2.0", "method": method, "params": [:]])
    }

    /// Возвращает (успех, текст результата).
    private func post(_ body: [String: Any], alreadyRetried: Bool = false) -> (Bool, String)? {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespaces)) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 90)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("2025-06-18", forHTTPHeaderField: "MCP-Protocol-Version")
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        var resp: URLResponse?
        var data: Data?
        var taskError: Error?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { d, r, e in taskError = e; data = d; resp = r; sem.signal() }.resume()
        sem.wait()
        if let e = taskError { foLog("ошибка сети: \(e)"); return (false, "⚠️ Сеть: \(e.localizedDescription)") }
        guard let http = resp as? HTTPURLResponse else {
            foLog("нет ответа: \(String(describing: resp))"); return (false, "⚠️ Нет ответа сервера")
        }
        foLog("запрос status=\(http.statusCode) bytes=\(data?.count ?? 0)")
        guard (200...299).contains(http.statusCode), let raw = data, !raw.isEmpty else {
            if http.statusCode == 401, !alreadyRetried, !refreshToken.isEmpty {
                if let fresh = refreshAccessToken() {
                    DispatchQueue.main.async { self.token = fresh }
                    return post(body, alreadyRetried: true)
                }
            }
            return (false, "⚠️ Сервер ответил кодом \(http.statusCode)")
        }
        return (true, Self.text(from: raw))
    }

    /// Ответ может быть обычным JSON или потоком SSE — приводим оба к тексту.
    static func text(from raw: Data) -> String {
        func decode(_ d: Data) -> String? {
            guard let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
            if let error = obj["error"] as? [String: Any],
               let message = error["message"] as? String { return "⚠️ \(message)" }
            if obj["result"] != nil || obj["method"] != nil {
                return String(decoding: d, as: UTF8.self)
            }
            return nil
        }
        if let direct = decode(raw) { return direct }
        let text = String(decoding: raw, as: UTF8.self)
        var last: String?
        for line in text.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.hasPrefix("data:") else { continue }
            let payload = s.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if let decoded = decode(Data(payload.utf8)) { last = decoded }
        }
        return last ?? "⚠️ Непонятный ответ сервера"
    }
}

/// Вкладка «Fo»: чат.
struct FoChatView: View {
    @ObservedObject var model: FoChatModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Fo").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button(action: {
                    model.showHistory.toggle()
                    model.openConv = nil
                    if model.showHistory { model.loadConversations() }
                }) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Capsule().fill(Color.secondary.opacity(model.showHistory ? 0.18 : 0)))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                Button(action: { model.showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Capsule().fill(Color.secondary.opacity(model.showSettings ? 0.18 : 0)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 6)

            if model.showSettings || model.endpoint.isEmpty || model.token.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Подключение к Fo. Нажми «Войти»: откроется браузер, войди в аккаунт Wajo и разреши доступ.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("Адрес (endpoint)", text: $model.endpoint)
                            .textFieldStyle(.roundedBorder).font(.system(size: 12))
                        Button("Войти") { model.startLogin() }
                            .font(.system(size: 12, weight: .semibold))
                            .disabled(model.loggingIn)
                    }
                    if !model.loginStatus.isEmpty {
                        Text(model.loginStatus).font(.system(size: 11)).foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 8)
            }

            if model.showHistory {
                historyView
            } else {
                chatList
            }

            if !model.showHistory || model.openConv != nil {
                inputRow
            }
        }
    }

    // MARK: - Чат

    private var chatList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 7) {
                    if model.messages.isEmpty {
                        Text("Пиши задачи Fo — он выполнит и ответит здесь.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .padding(.top, 24).frame(maxWidth: .infinity)
                    }
                    ForEach(model.messages) { m in msgBubble(m) }
                    if model.busy { typingIndicator }
                    Color.clear.frame(height: 1).id("chatBottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.top, 2)
                .padding(.bottom, 10)
            }
            .onChange(of: model.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("chatBottom", anchor: .bottom) }
            }
            .onChange(of: model.busy) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("chatBottom", anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo("chatBottom", anchor: .bottom) }
        }
    }

    private var typingIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: 5, height: 5)
                    .opacity(i == 1 ? 1 : 0.4)
            }
            Text("Fo печатает…").font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
    }

    private func msgBubble(_ m: FoChatModel.Msg) -> some View {
        let text = m.role == .user ? m.text : Self.plain(m.text)
        return HStack(alignment: .bottom) {
            if m.role == .user { Spacer(minLength: 0) }
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(m.role == .error ? Color.red : Color.primary)
                .textSelection(.enabled)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    m.role == .user
                        ? AnyShapeStyle(Color.accentColor.opacity(0.18))
                        : AnyShapeStyle(Color.secondary.opacity(0.13)),
                    in: RoundedRectangle(cornerRadius: 13)
                )
                .frame(maxWidth: 440, alignment: m.role == .user ? .trailing : .leading)
            if m.role != .user { Spacer(minLength: 0) }
        }
    }

    // MARK: - Ввод

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("Спросить Fo…", text: $model.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .lineLimit(1...3)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(model.busy || model.draft.trimmingCharacters(in: .whitespaces).isEmpty
                        ? Color.accentColor.opacity(0.35)
                        : Color.accentColor))
            }
            .buttonStyle(.plain)
            .disabled(model.busy || model.draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.secondary.opacity(0.10)))
        .padding(.horizontal, 22)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    // MARK: - История

    private var historyView: some View {
        Group {
            if let open = model.openConv {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Button(action: { model.openConv = nil }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 24, height: 22)
                                .background(Capsule().fill(Color.secondary.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        Text(open.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 22).padding(.top, 2)
                    if model.loadingConv {
                        Text("Загружаю…").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 20)
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView(.vertical, showsIndicators: false) {
                                VStack(alignment: .leading, spacing: 7) {
                                    ForEach(model.historyMsgs) { m in msgBubble(m) }
                                    Color.clear.frame(height: 1).id("histBottom")
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 22).padding(.top, 4).padding(.bottom, 10)
                            }
                            .onChange(of: model.historyMsgs.count) { _, _ in
                                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("histBottom", anchor: .bottom) }
                            }
                            .onAppear { proxy.scrollTo("histBottom", anchor: .bottom) }
                        }
                    }
                }
            } else {
                VStack(spacing: 6) {
                    HStack {
                        Text("Все чаты").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Button(action: { model.loadConversations() }) {
                            Image(systemName: "arrow.clockwise").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 22).padding(.top, 2)
                    if model.loadingConvs {
                        Text("Загружаю…").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 16)
                    } else if !model.convsStatus.isEmpty {
                        Text(model.convsStatus).font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 16)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 5) {
                                ForEach(model.convs) { c in
                                    Button(action: { model.openConversation(c) }) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(c.title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.primary).lineLimit(1)
                                            HStack(spacing: 6) {
                                                if !c.channel.isEmpty {
                                                    Text(c.channel).font(.system(size: 10)).foregroundStyle(.secondary)
                                                }
                                                if let d = c.when {
                                                    Text(FoChatModel.stampFmt.string(from: d)).font(.system(size: 10)).foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 10).padding(.vertical, 8)
                                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 22).padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Утилиты

    /// Fo отвечает с разметкой: чистим звёздочки, решётки и бэктики, чтобы текст не выглядел «сырым».
    private static func plain(_ s: String) -> String {
        var lines: [String] = []
        for line in s.components(separatedBy: "\n") {
            var l = line
            while l.hasPrefix("#") { l = String(l.dropFirst()) }
            l = l.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("```") || l == "---" || l == "___" { l = "" }
            l = l.replacingOccurrences(of: "**", with: "")
            l = l.replacingOccurrences(of: "__", with: "")
            l = l.replacingOccurrences(of: "`", with: "")
            lines.append(l)
        }
        var out = lines.joined(separator: "\n")
        while out.contains("\n\n\n") { out = out.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return out.isEmpty ? s : out
    }

    private func send() {
        model.send(model.draft)
        model.draft = ""
    }
}
