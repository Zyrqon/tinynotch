import Foundation

/// Отвечает на запросы подтверждения opencode через его локальный сервер
/// (TUI держит его на случайном порту): список ждущих и ответ «разрешить/запретить».
enum AgentPermission {
    struct Request: Equatable {
        let id: String
        let sessionID: String
        let permission: String
    }

    /// Порт локального сервера opencode по pid процесса.
    static func serverPort(pid: Int32) -> UInt16? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        p.arguments = ["-a", "-p", String(pid), "-iTCP", "-sTCP:LISTEN", "-F", "Pn"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("n") {
            let addr = line.dropFirst()
            if let idx = addr.lastIndex(of: ":"), let port = UInt16(addr[addr.index(after: idx)...]) {
                return port
            }
        }
        return nil
    }

    /// Ждущие подтверждения на этом сервере.
    static func pending(port: UInt16) -> [Request] {
        guard let data = get(url: URL(string: "http://127.0.0.1:\(port)/permission")!) else { return [] }
        guard let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let id = row["id"] as? String, let sid = row["sessionID"] as? String else { return nil }
            return Request(id: id, sessionID: sid, permission: row["permission"] as? String ?? "")
        }
    }

    /// Ответ на запрос: «once» — разрешить один раз, «always» — навсегда, «reject» — запретить.
    @discardableResult
    static func reply(port: UInt16, requestID: String, reply: String) -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/permission/\(requestID)/reply") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["reply": reply])
        req.timeoutInterval = 4
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            ok = (resp as? HTTPURLResponse)?.statusCode == 200
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 4)
        return ok
    }

    private static func get(url: URL) -> Data? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 4
        let sem = DispatchSemaphore(value: 0)
        var out: Data?
        URLSession.shared.dataTask(with: req) { data, _, _ in
            out = data
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 4)
        return out
    }
}
