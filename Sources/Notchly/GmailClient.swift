import AppKit
import Network

struct MailItem: Identifiable, Equatable {
    var id: String
    var threadHex: String
    var senderName: String
    var senderEmail: String
    var subject: String
    var date: Date
}

/// Непрочитанные письма Gmail по IMAP. Вход — адрес и «пароль приложения» Google
/// (myaccount.google.com/apppasswords); пароль хранится в Связке ключей.
final class GmailClient: ObservableObject {
    @Published private(set) var account: String?
    @Published private(set) var mails: [MailItem] = []
    @Published private(set) var error: String?
    @Published private(set) var isLoading = false
    /// Пароль в Связке ключей недоступен этой сборке — нужно ввести заново.
    @Published private(set) var needsPassword = false

    private var timer: Timer?
    /// Соединение и пароль между обновлениями: раньше каждые 30 секунд заново читался пароль из Связки ключей
    /// (расшифровка в securityd), открывалось TLS-соединение, шёл вход и скачивались 20 заголовков.
    private let mailbox = GmailMailbox()
    private static let accountKey = "gmail.account"
    /// Новое непрочитанное письмо — остров показывает его карточкой.
    var onNew: ((MailItem) -> Void)?
    private var knownIDs: Set<String>?

    init() {
        account = UserDefaults.standard.string(forKey: Self.accountKey)
        if account != nil { refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
    }

    var isConnected: Bool { account != nil }

    func connect(email: String, appPassword: String) {
        let email = email.trimmingCharacters(in: .whitespaces)
        let password = appPassword.replacingOccurrences(of: " ", with: "")
        guard !email.isEmpty, !password.isEmpty else { return }
        isLoading = true
        error = nil
        Task {
            do {
                let mails = try await Self.fetchUnread(email: email, password: password)
                await self.mailbox.forget()
                await MainActor.run {
                    // Старую запись (от прежней подписи) удаляем, чтобы новая принадлежала этой сборке.
                    Keychain.delete(service: "gmail", account: email)
                    Keychain.set(Data(password.utf8), service: "gmail", account: email)
                    UserDefaults.standard.set(email, forKey: Self.accountKey)
                    self.account = email
                    self.mails = mails
                    self.knownIDs = Set(mails.map(\.id))
                    self.needsPassword = false
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = (error as? IMAPError)?.message ?? error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    func disconnect() {
        let mailbox = mailbox
        Task { await mailbox.forget() }
        if let account { Keychain.delete(service: "gmail", account: account) }
        UserDefaults.standard.removeObject(forKey: Self.accountKey)
        account = nil
        mails = []
    }

    func refresh() {
        guard let account, !isLoading else { return }
        isLoading = true
        // Пароль читаем не на главном потоке: если macOS спросит доступ к Связке ключей,
        // остров не должен замереть, пока запрос висит на экране.
        let mailbox = mailbox
        Task.detached {
            guard let password = await mailbox.password(for: account) else {
                await MainActor.run {
                    self.isLoading = false
                    // Обычно после пересборки без постоянной подписи: Связка ключей не отдаёт пароль новой сборке.
                    self.needsPassword = true
                    self.error = L("Введите пароль приложения ещё раз — старая сборка сохранила его недоступным")
                }
                return
            }
            let result = try? await Self.withTimeout(seconds: 25) {
                try await mailbox.unread(email: account, password: password)
            }
            // Не уложились — соединение в неизвестном состоянии, в следующий раз откроем новое.
            if result == nil { await mailbox.reset() }
            await MainActor.run {
                self.isLoading = false
                guard let result else {
                    self.error = L("Не удалось обновить почту")
                    return
                }
                self.error = nil
                self.announceNew(result)
                if result != self.mails { self.mails = result }
            }
        }
    }

    /// Проверка без интерфейса: вход и число непрочитанных (без содержимого писем).
    static func selfTest(_ done: @escaping (String) -> Void) {
        guard let account = UserDefaults.standard.string(forKey: accountKey) else { return done("аккаунт не подключён") }
        guard let data = Keychain.data(service: "gmail", account: account),
              let password = String(data: data, encoding: .utf8) else { return done("пароль недоступен в Связке ключей") }
        Task {
            do {
                let mails = try await withTimeout(seconds: 25) { try await fetchUnread(email: account, password: password) }
                let newest = mails.first.map { shortTimestamp($0.date) } ?? "—"
                done("вход OK, непрочитанных во «Входящих»: \(mails.count), самое новое: \(newest)")
            } catch {
                done("ошибка: \((error as? IMAPError)?.message ?? error.localizedDescription)")
            }
        }
    }

    private func announceNew(_ mails: [MailItem]) {
        let ids = Set(mails.map(\.id))
        defer { knownIDs = (knownIDs ?? []).union(ids) }
        // Первая загрузка — это старые письма, их не показываем.
        guard let known = knownIDs,
              let fresh = mails.filter({ !known.contains($0.id) }).max(by: { $0.date < $1.date }) else { return }
        onNew?(fresh)
    }

    private static func withTimeout<T: Sendable>(seconds: Double, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw IMAPError(message: L("Gmail не ответил вовремя"))
            }
            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }

    func open(_ mail: MailItem) {
        guard let account else { return }
        let encoded = account.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? account
        if let url = URL(string: "https://mail.google.com/mail/u/?authuser=\(encoded)#all/\(mail.threadHex)") {
            NSWorkspace.shared.open(url)
        }
    }

    func openInbox() {
        guard let account else { return }
        let encoded = account.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? account
        if let url = URL(string: "https://mail.google.com/mail/u/?authuser=\(encoded)#inbox") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - IMAP

    static func fetchUnread(email: String, password: String) async throws -> [MailItem] {
        let session = IMAPSession(host: "imap.gmail.com", port: 993)
        defer { session.close() }
        try await session.open()
        let login = try await session.run("LOGIN \(quote(email)) \(quote(password))")
        guard login.ok else { throw IMAPError(message: L("Gmail не принял адрес или пароль приложения")) }
        _ = try await session.run("EXAMINE INBOX")
        let search = try await session.run("SEARCH UNSEEN")
        let ids = String(decoding: search.data, as: UTF8.self)
            .components(separatedBy: "\r\n")
            .first { $0.hasPrefix("* SEARCH") }?
            .split(separator: " ").dropFirst(2).compactMap { Int($0) } ?? []
        guard !ids.isEmpty else { return [] }
        let latest = ids.suffix(20).map(String.init).joined(separator: ",")
        let fetch = try await session.run("FETCH \(latest) (X-GM-THRID X-GM-MSGID BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE)])")
        _ = try? await session.run("LOGOUT")
        return parseFetch(fetch.data).sorted { $0.date > $1.date }
    }

    static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Разбирает ответы FETCH: у каждого письма есть X-GM-THRID/X-GM-MSGID и литерал с заголовками.
    static func parseFetch(_ data: Data) -> [MailItem] { parseFetchWithUIDs(data).map(\.item) }

    /// То же, но с UID письма (если сервер его прислал) — по нему кэшируются уже скачанные заголовки.
    static func parseFetchWithUIDs(_ data: Data) -> [(uid: UInt64?, item: MailItem)] {
        let bytes = [UInt8](data)
        var items: [(uid: UInt64?, item: MailItem)] = []
        var index = 0
        let literal = try! NSRegularExpression(pattern: #"\{(\d+)\}\r\n$"#)
        var lineStart = 0
        while index < bytes.count {
            guard bytes[index] == 0x0A else { index += 1; continue }
            let line = String(decoding: bytes[lineStart...index], as: UTF8.self)
            index += 1
            if line.hasPrefix("* "), line.contains("FETCH"),
               let m = literal.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let lenRange = Range(m.range(at: 1), in: line), let length = Int(line[lenRange]),
               index + length <= bytes.count {
                let headers = String(decoding: bytes[index..<(index + length)], as: UTF8.self)
                index += length
                let thread = firstNumber(after: "X-GM-THRID", in: line) ?? 0
                let msgID = firstNumber(after: "X-GM-MSGID", in: line) ?? UInt64(items.count)
                items.append((firstNumber(after: "UID", in: line), makeItem(headers: headers, thread: thread, msgID: msgID)))
            }
            lineStart = index
        }
        return items
    }

    private static func firstNumber(after key: String, in line: String) -> UInt64? {
        guard let r = line.range(of: " " + key + " ") ?? line.range(of: "(" + key + " ") else { return nil }
        return UInt64(line[r.upperBound...].prefix { $0.isNumber })
    }

    private static func makeItem(headers: String, thread: UInt64, msgID: UInt64) -> MailItem {
        let unfolded = headers.replacingOccurrences(of: "\r\n ", with: " ").replacingOccurrences(of: "\r\n\t", with: " ")
        var fields: [String: String] = [:]
        for line in unfolded.components(separatedBy: "\r\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            fields[line[..<colon].lowercased()] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        let from = MIMEHeader.decode(fields["from"] ?? "")
        var name = from, email = ""
        if let lt = from.lastIndex(of: "<"), let gt = from.lastIndex(of: ">"), lt < gt {
            email = String(from[from.index(after: lt)..<gt])
            name = from[..<lt].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
        }
        if name.isEmpty { name = email.isEmpty ? from : email }
        return MailItem(id: String(msgID), threadHex: String(thread, radix: 16),
                        senderName: name, senderEmail: email,
                        subject: MIMEHeader.decode(fields["subject"] ?? L("(без темы)")),
                        date: MIMEHeader.date(fields["date"] ?? "") ?? Date())
    }
}

struct IMAPError: Error {
    var message: String
    /// Повтор на новом соединении не поможет (например, неверный пароль).
    var final = false
}

/// Почтовый ящик Gmail между обновлениями: одно открытое соединение (EXAMINE INBOX), пароль в памяти
/// и кэш уже скачанных заголовков по UID. Обновление — это NOOP и UID SEARCH UNSEEN; заголовки качаются
/// только у новых писем. Если соединение умерло (сон, смена сети) — одна попытка на новом.
actor GmailMailbox {
    private var session: IMAPSession?
    private var sessionAccount: String?
    private var cache: [UInt64: MailItem] = [:]
    /// С какого UID искать непрочитанные. Во «Входящих» их бывают десятки тысяч, и полный SEARCH UNSEEN
    /// каждые 30 секунд приносил сотни килобайт номеров. Нужны же только 20 самых свежих — ищем среди
    /// последних писем и расширяем окно, только если там их меньше 20.
    private var searchFrom: UInt64 = 1
    /// UIDNEXT при открытии ящика: от него отсчитывается окно поиска.
    private var uidTop: UInt64 = 1
    private static let searchWindow: UInt64 = 1000
    private var cachedPassword: (account: String, password: String)?

    /// Пароль приложения: из памяти, а в первый раз — из Связки ключей.
    func password(for account: String) -> String? {
        if let cachedPassword, cachedPassword.account == account { return cachedPassword.password }
        guard let data = Keychain.data(service: "gmail", account: account),
              let password = String(data: data, encoding: .utf8) else { return nil }
        cachedPassword = (account, password)
        return password
    }

    func unread(email: String, password: String) async throws -> [MailItem] {
        do {
            return try await attempt(email: email, password: password)
        } catch let error as IMAPError where error.final {
            forget()
            throw error
        } catch {
            reset()
            return try await attempt(email: email, password: password)
        }
    }

    private static func number(after key: String, in data: Data) -> UInt64? {
        let text = String(decoding: data, as: UTF8.self)
        guard let r = text.range(of: key) else { return nil }
        return UInt64(text[r.upperBound...].prefix { $0.isNumber })
    }

    /// Закрыть соединение (кэш заголовков живёт вместе с ним).
    func reset() {
        session?.close()
        session = nil
        sessionAccount = nil
        cache = [:]
    }

    /// Забыть и соединение, и пароль (отключили почту или сменили пароль).
    func forget() {
        reset()
        cachedPassword = nil
    }

    private func attempt(email: String, password: String) async throws -> [MailItem] {
        let session: IMAPSession
        if let open = self.session, sessionAccount == email {
            session = open
            guard try await session.run("NOOP").ok else { throw IMAPError(message: L("Не удалось обновить почту")) }
        } else {
            reset()
            session = IMAPSession(host: "imap.gmail.com", port: 993)
            self.session = session
            try await session.open()
            guard try await session.run("LOGIN \(GmailClient.quote(email)) \(GmailClient.quote(password))").ok else {
                throw IMAPError(message: L("Gmail не принял адрес или пароль приложения"), final: true)
            }
            let examine = try await session.run("EXAMINE INBOX")
            guard examine.ok else { throw IMAPError(message: L("Не удалось обновить почту")) }
            uidTop = Self.number(after: "[UIDNEXT ", in: examine.data) ?? 1
            searchFrom = uidTop > Self.searchWindow ? uidTop - Self.searchWindow : 1
            sessionAccount = email
        }
        var uids: [UInt64] = []
        while true {
            let search = try await session.run("UID SEARCH UNSEEN UID \(searchFrom):*")
            guard search.ok else { throw IMAPError(message: L("Не удалось обновить почту")) }
            // На «x:*» сервер может добавить последнее письмо, даже если его UID меньше x, — отсекаем.
            uids = (String(decoding: search.data, as: UTF8.self)
                .components(separatedBy: "\r\n")
                .first { $0.hasPrefix("* SEARCH") }?
                .split(separator: " ").dropFirst(2).compactMap { UInt64($0) } ?? [])
                .filter { $0 >= searchFrom }
            guard uids.count < 20, searchFrom > 1 else { break }
            // В окне меньше 20 непрочитанных — смотрим глубже (окно в 8 раз больше), пока не дойдём до начала.
            let window = max(uidTop > searchFrom ? uidTop - searchFrom : 0, Self.searchWindow) * 8
            searchFrom = uidTop > window ? uidTop - window : 1
        }
        let latest = Array(uids.sorted().suffix(20))
        let missing = latest.filter { cache[$0] == nil }
        if !missing.isEmpty {
            let list = missing.map(String.init).joined(separator: ",")
            let fetch = try await session.run("UID FETCH \(list) (X-GM-THRID X-GM-MSGID BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE)])")
            let parsed = GmailClient.parseFetchWithUIDs(fetch.data)
            if parsed.allSatisfy({ $0.uid != nil }) {
                for (uid, item) in parsed { cache[uid!] = item }
            } else if parsed.count == missing.count {
                // UID пришёл не в строке с заголовками. Ответы FETCH идут по возрастанию номеров,
                // а значит и UID, — сопоставляем по порядку.
                for (uid, entry) in zip(missing.sorted(), parsed) { cache[uid] = entry.item }
            } else {
                throw IMAPError(message: L("Не удалось обновить почту"))
            }
        }
        let keep = Set(latest)
        cache = cache.filter { keep.contains($0.key) }
        return latest.compactMap { cache[$0] }.sorted { $0.date > $1.date }
    }
}

// MARK: - Соединение IMAP поверх TLS

/// Потокобезопасный флаг «уже сделано» для одноразового возобновления continuation.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

final class IMAPSession {
    struct Response { var ok: Bool; var data: Data }

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "notchly.imap")
    private var buffer = Data()
    private var tag = 0

    init(host: String, port: UInt16) {
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tls)
    }

    func open() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            // Продолжение можно возобновить только один раз; состояния приходят на отдельной очереди.
            let once = ResumeOnce()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: if once.claim() { cont.resume() }
                case .failed(let e), .waiting(let e): if once.claim() { cont.resume(throwing: e) }
                default: break
                }
            }
            connection.start(queue: queue)
        }
        _ = try await readUntil { $0.range(of: Data("\r\n".utf8)) != nil }
    }

    func run(_ command: String) async throws -> Response {
        tag += 1
        let t = "a\(tag)"
        try await send(Data("\(t) \(command)\r\n".utf8))
        let marker = Data("\r\n\(t) ".utf8)
        let data = try await readUntil { data in
            (data.starts(with: Data("\(t) ".utf8)) || data.range(of: marker) != nil) && data.suffix(2) == Data("\r\n".utf8)
        }
        let text = String(decoding: data.suffix(200), as: UTF8.self)
        return Response(ok: text.contains("\(t) OK"), data: data)
    }

    func close() { connection.cancel() }

    private func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    private func readUntil(_ done: @escaping (Data) -> Bool) async throws -> Data {
        let deadline = Date().addingTimeInterval(20)
        while !done(buffer) {
            guard Date() < deadline else { throw IMAPError(message: L("Gmail не отвечает")) }
            let chunk = try await receive()
            guard !chunk.isEmpty else { throw IMAPError(message: L("Соединение с Gmail закрыто")) }
            buffer.append(chunk)
        }
        let result = buffer
        buffer.removeAll()
        return result
    }

    private func receive() async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { data, _, isComplete, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: data ?? (isComplete ? Data() : Data())) }
            }
        }
    }
}

// MARK: - Заголовки писем

enum MIMEHeader {
    /// Раскодирует «=?UTF-8?B?...?=» и «=?UTF-8?Q?...?=» — так приходят русские темы и имена.
    static func decode(_ value: String) -> String {
        let pattern = try! NSRegularExpression(pattern: #"=\?([^?]+)\?([BbQq])\?([^?]*)\?="#)
        let ns = value as NSString
        var result = ""
        var last = 0
        var previousWasEncoded = false
        for m in pattern.matches(in: value, range: NSRange(location: 0, length: ns.length)) {
            let between = ns.substring(with: NSRange(location: last, length: m.range.location - last))
            // Пробелы между соседними закодированными словами не выводятся.
            if !(previousWasEncoded && between.trimmingCharacters(in: .whitespaces).isEmpty) { result += between }
            let charset = ns.substring(with: m.range(at: 1))
            let kind = ns.substring(with: m.range(at: 2)).uppercased()
            let text = ns.substring(with: m.range(at: 3))
            var bytes: Data?
            if kind == "B" {
                var padded = text
                while padded.count % 4 != 0 { padded += "=" }
                bytes = Data(base64Encoded: padded)
            } else {
                bytes = quotedPrintable(text.replacingOccurrences(of: "_", with: " "))
            }
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            let encoding = cfEncoding == kCFStringEncodingInvalidId
                ? String.Encoding.utf8
                : String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
            result += bytes.flatMap { String(data: $0, encoding: encoding) } ?? text
            last = m.range.location + m.range.length
            previousWasEncoded = true
        }
        result += ns.substring(from: last)
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func quotedPrintable(_ s: String) -> Data {
        var out = Data()
        var chars = Array(s.utf8)[...]
        while let c = chars.popFirst() {
            if c == UInt8(ascii: "="), chars.count >= 2,
               let v = UInt8(String(decoding: chars.prefix(2), as: UTF8.self), radix: 16) {
                out.append(v)
                chars = chars.dropFirst(2)
            } else {
                out.append(c)
            }
        }
        return out
    }

    static func date(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let cleaned = value.replacingOccurrences(of: #"\s*\(.*\)$"#, with: "", options: .regularExpression)
        for format in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z"] {
            formatter.dateFormat = format
            if let d = formatter.date(from: cleaned) { return d }
        }
        return nil
    }
}
